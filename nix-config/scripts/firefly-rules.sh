#!/usr/bin/env bash
# Seed Firefly III category rules from a keyword table.
#
# The table lives OUTSIDE this repo, like accounts.tsv — the repo is public and
# a list of where you shop is personal data. Default location:
#   ~/.config/firefly/rules.tsv
# Two tab-separated columns, '#' comments and blank lines ignored:
#   category <TAB> keyword|keyword|keyword
# e.g.
#   Lebensmittel<TAB>Migros|Coop|Lidl|Denner
#
# A keyword matches the transaction description. Two prefixes match an account
# by exact name instead, which is what you want for money moving between your
# own accounts — their descriptions vary too much to rely on (a transfer to a
# savings account is sometimes named after the account, sometimes after
# whatever Zahlungsgrund you typed):
#   to:SJUMA     destination account is SJUMA
#   from:MWE     source account is MWE
#
# One rule per category, `strict: false` so its triggers are OR'd — any keyword
# matching the description sets the category. The importer config has
# `rules: true`, so these fire during import.
#
#   firefly-rules.sh [--apply]
#
# Rules only run on new transactions, so --apply also fires the whole group over
# everything already in Firefly. That is what you want after editing rules.tsv:
# without it the new keywords take effect on the next import only.
#
# Idempotent: rule titles are unique per user in Firefly, so an existing rule is
# updated in place (its triggers are replaced wholesale) rather than duplicated.
#
# Line order in the table IS evaluation order. Rules do not stop_processing, so
# when a payee matches two rules the LAST one to run wins — put the broad
# categories first and the specific ones below them.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/firefly-api.sh"

DATA="${FIREFLY_RULES:-${XDG_CONFIG_HOME:-$HOME/.config}/firefly/rules.tsv}"
GROUP="${FIREFLY_RULE_GROUP:-UBS auto-categorize}"
# Stamped into every generated rule's description. Rules without it are yours —
# make them in the UI, in this group or any other, and they are left alone.
MARKER="Generated from rules.tsv; edits here are overwritten."

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -h | --help)
      sed -n '2,26p' "$0"
      exit 0
      ;;
    *) die "unknown option: $arg" ;;
  esac
done

[ -r "$DATA" ] || die "rule table not found: $DATA
       Create it (see the header of this script for the format), or point
       FIREFLY_RULES at another file."

firefly_hello

# --- rule group --------------------------------------------------------------
groups=$(api GET '/api/v1/rule-groups?limit=200') || die "cannot list rule groups"
group_id=$(jq -r --arg t "$GROUP" '.data[] | select(.attributes.title == $t) | .id' <<<"$groups")
if [ -z "$group_id" ]; then
  echo "==> creating rule group '$GROUP'"
  if [ "$DRY_RUN" = 1 ]; then
    group_id="(dry-run)"
  else
    body=$(jq -n --arg t "$GROUP" \
      '{title: $t, description: "Category rules generated from rules.tsv", active: true}')
    group_id=$(api POST /api/v1/rule-groups "$body" | jq -r '.data.id') ||
      die "cannot create rule group"
  fi
else
  echo "==> rule group '$GROUP' (id $group_id)"
fi

existing=$(api GET "/api/v1/rule-groups/$group_id/rules?limit=500" 2>/dev/null || echo '{"data":[]}')

created=0 updated=0 deleted=0 failed=0
seen_titles=()
order=0
while IFS=$'\t' read -r category keywords; do
  [ -z "${category// /}" ] && continue
  case "$category" in \#*) continue ;; esac
  [ -n "${keywords:-}" ] || continue

  title="Category: $category"
  order=$((order + 1))

  # Triggers: one per keyword. A bare keyword matches the description; `to:` and
  # `from:` match an account by exact name instead. `description_contains`,
  # `destination_account_is` and `source_account_is` are all search operators
  # (config/search.php); `set_category` is a rule action (config/firefly.php) —
  # all checked against this Firefly version.
  triggers=$(printf '%s' "$keywords" | tr '|' '\n' |
    jq -R 'select(length>0)
           | (. | gsub("^\\s+|\\s+$";"")) as $kw
           | if   ($kw | startswith("to:"))   then {type: "destination_account_is", value: $kw[3:]}
             elif ($kw | startswith("from:")) then {type: "source_account_is",      value: $kw[5:]}
             else {type: "description_contains", value: $kw} end
           | . + {active: true, stop_processing: false}' |
    jq -s .)
  n=$(jq 'length' <<<"$triggers")
  [ "$n" -gt 0 ] || continue

  body=$(jq -n \
    --arg title "$title" \
    --arg group "$group_id" \
    --arg cat "$category" \
    --arg marker "$MARKER" \
    --argjson order "$order" \
    --argjson triggers "$triggers" \
    '{
       title: $title,
       description: "Set category \($cat) from the payee name. \($marker)",
       rule_group_id: $group,
       order: $order,
       trigger: "store-journal",
       active: true,
       strict: false,
       stop_processing: false,
       triggers: $triggers,
       actions: [{type: "set_category", value: $cat, active: true, stop_processing: false}]
     }')

  rule_id=$(jq -r --arg t "$title" '.data[] | select(.attributes.title == $t) | .id' <<<"$existing")

  # Record before any `continue`, or a dry run reports every rule as stale.
  seen_titles+=("$title")

  if [ "$DRY_RUN" = 1 ]; then
    echo "  would $([ -n "$rule_id" ] && echo update || echo create)  #$order $title ($n keyword(s))"
    created=$((created + 1))
    continue
  fi

  if [ -n "$rule_id" ]; then
    if resp=$(api PUT "/api/v1/rules/$rule_id" "$body"); then
      echo "  updated  #$order $title ($n keyword(s))"
      updated=$((updated + 1))
    else
      echo "  FAILED   $title: $(jq -r '.message // .' <<<"$resp" 2>/dev/null || printf '%s' "$resp")"
      failed=$((failed + 1))
    fi
  else
    if resp=$(api POST /api/v1/rules "$body"); then
      echo "  created  #$order $title ($n keyword(s))"
      created=$((created + 1))
    else
      echo "  FAILED   $title: $(jq -r '.message // .' <<<"$resp" 2>/dev/null || printf '%s' "$resp")"
      failed=$((failed + 1))
    fi
  fi
done <"$DATA"

# Rules are looked up by title, so renaming a category in rules.tsv would leave
# the old rule behind — still active, still setting the old category, invisibly
# double-categorising every future import. Delete generated rules the table no
# longer describes. Only generated ones: rules you write in the UI are the point
# of having a rule engine, and this script must never eat them.
while read -r rule_id title; do
  [ -n "$rule_id" ] || continue
  for keep in ${seen_titles+"${seen_titles[@]}"}; do
    [ "$keep" = "$title" ] && continue 2
  done
  if [ "$DRY_RUN" = 1 ]; then
    echo "  would delete  $title (no longer in $(basename "$DATA"))"
    continue
  fi
  if api DELETE "/api/v1/rules/$rule_id" >/dev/null; then
    echo "  deleted  $title (no longer in $(basename "$DATA"))"
    deleted=$((deleted + 1))
  else
    echo "  FAILED   to delete $title"
    failed=$((failed + 1))
  fi
done < <(jq -r --arg m "$MARKER" \
  '.data[] | select((.attributes.description // "") | contains($m)) | "\(.id) \(.attributes.title)"' \
  <<<"$existing")

echo
echo "created $created, updated $updated, deleted $deleted, failed $failed"

if [ "$APPLY" = 1 ] && [ "$DRY_RUN" != 1 ]; then
  echo
  echo "==> applying '$GROUP' to existing transactions"
  # No start/end: the group should cover everything already imported.
  api POST "/api/v1/rule-groups/$group_id/trigger" '{}' >/dev/null ||
    die "could not trigger rule group $group_id"
  echo "    done"
fi

[ "$failed" -eq 0 ]
