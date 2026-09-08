#!/usr/bin/env bash
# Show what is still uncategorized, ranked so the effort goes where the money is.
#
#   firefly-uncategorized.sh [--count] [--limit N] [--type TYPE]
#
# Categorising alphabetically is a waste of an evening: spending is a long tail,
# so a handful of payees is most of the total. Default ordering is by total
# amount; --count ranks by how often a payee appears instead, which is what you
# want when writing a rule that should keep paying off on future imports.
#
# The loop this is meant to drive:
#   1. run this
#   2. add the top payees to ~/.config/firefly/rules.tsv (or normalise their
#      spelling in payees.tsv first, if the same shop appears several ways)
#   3. scripts/firefly-rules.sh --apply      # re-runs over existing transactions
#   4. run this again — the list should be shorter
#
# For genuine one-offs, don't write a rule. Filter `has_no_category` in the
# Firefly UI and set those by hand.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/firefly-api.sh"

ORDER=amount
LIMIT=25
TYPE=withdrawal
while [ $# -gt 0 ]; do
  case "$1" in
    --count) ORDER=count ;;
    --limit) LIMIT=${2:?--limit needs a number}; shift ;;
    --type) TYPE=${2:?--type needs a transaction type}; shift ;;
    -h | --help)
      sed -n '2,24p' "$0"
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

firefly_hello

# Collect every page before aggregating: a partial read would quietly rank the
# wrong payees at the top, which is the one thing this report must not do.
rows=$(
  page=1
  while :; do
    resp=$(api GET "/api/v1/transactions?limit=200&page=$page&type=$TYPE") ||
      die "cannot list transactions"
    jq -c '.data[].attributes.transactions[]' <<<"$resp"
    total=$(jq -r '.meta.pagination.total_pages // 1' <<<"$resp")
    [ "$page" -ge "$total" ] && break
    page=$((page + 1))
  done
)

jq -sr --arg order "$ORDER" --argjson limit "$LIMIT" --arg type "$TYPE" '
  (map(select(.category_name == null))) as $un
  | (map(select(.category_name != null))) as $cat
  | ($un | map(.amount | tonumber) | add // 0)  as $unsum
  | ($cat | map(.amount | tonumber) | add // 0) as $catsum
  | "\n  \($type)s: \($un|length) uncategorised (CHF \($unsum|round)) vs \($cat|length) categorised (CHF \($catsum|round))\n",
    ($un
      | group_by(.destination_name)
      | map({name: .[0].destination_name, n: length,
             sum: (map(.amount | tonumber) | add)})
      | sort_by(if $order == "count" then -.n else -.sum end)
      | .[:$limit]
      | .[]
      | "  \(.sum|round|tostring|(" "*(8-length))+.)  x\(.n|tostring|.+(" "*(3-length)))  \(.name)"),
    "\n  \($un | group_by(.destination_name) | length) distinct payees still uncategorised."
' <<<"$rows"

echo "  Add the ones worth a rule to ~/.config/firefly/rules.tsv, then:"
echo "      scripts/firefly-rules.sh --apply"
echo "  One-offs: filter \"has_no_category\" in the Firefly UI and set them by hand."
