#!/usr/bin/env bash
# Set each asset account's opening balance from its earliest UBS export.
#
#   firefly-opening-balances.sh [--force] FILE.csv [FILE2.csv ...]
#
# Every UBS export names the balance the statement starts from:
#   IBAN:;CH88 0023 0230 1518 2740 V;
#   Von:;2026-05-02;
#   Anfangssaldo:;5905.71;
# so the number never has to be typed by hand. For each IBAN the EARLIEST
# statement wins, and its Anfangssaldo is written to the matching asset account
# dated the day before `Von` — before that account's first transaction, which is
# what keeps the running balance right.
#
# Firefly rewrites the existing initial-balance transaction rather than adding a
# second one, so re-running with --force after extending history backwards is
# the supported way to correct it.
#
# By default an account that already carries a non-zero opening balance is left
# alone; --force overwrites. DRY_RUN=1 shows what would change.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/firefly-api.sh"

FORCE=0
FILES=()
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h | --help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    -*) die "unknown option: $arg" ;;
    *) FILES+=("$arg") ;;
  esac
done
[ ${#FILES[@]} -gt 0 ] || die "no UBS exports given
       usage: $(basename "$0") [--force] FILE.csv [FILE2.csv ...]"

firefly_hello

# --- earliest statement per IBAN ---------------------------------------------
# Collect "IBAN<TAB>Von<TAB>Anfangssaldo" per file, then keep the lowest Von for
# each IBAN. ISO dates sort lexically, so `sort` alone does the picking.
declare -A EARLIEST
for f in "${FILES[@]}"; do
  [ -r "$f" ] || die "cannot read $f"
  iban=$(norm "$(ubs_field "$f" 'IBAN')")
  von=$(ubs_field "$f" 'Von')
  opening=$(ubs_field "$f" 'Anfangssaldo')
  if [ -z "$iban" ] || [ -z "$von" ] || [ -z "$opening" ]; then
    echo "  skip     $(basename "$f") (no IBAN/Von/Anfangssaldo in the preamble)"
    continue
  fi
  prev=${EARLIEST[$iban]:-}
  if [ -z "$prev" ] || [[ "$von" < "${prev%%$'\t'*}" ]]; then
    EARLIEST[$iban]="$von"$'\t'"$opening"$'\t'"$(basename "$f")"
  fi
done

accounts=$(api GET '/api/v1/accounts?type=asset&limit=500') || die "cannot list accounts"

set=0 skipped=0 failed=0
for iban in "${!EARLIEST[@]}"; do
  IFS=$'\t' read -r von opening src <<<"${EARLIEST[$iban]}"

  acct=$(jq -r --arg i "$iban" \
    '.data[] | select((.attributes.iban // "" | ascii_upcase | gsub("\\s";"")) == $i)
     | "\(.id)\t\(.attributes.name)\t\(.attributes.opening_balance // "0")\t\(.attributes.opening_balance_date // "")"' \
    <<<"$accounts")
  if [ -z "$acct" ]; then
    echo "  MISSING  no asset account with IBAN $iban (from $src)"
    failed=$((failed + 1))
    continue
  fi
  IFS=$'\t' read -r id name current curdate <<<"$acct"

  # The day before the statement period starts.
  obdate=$(date -u -d "$von - 1 day" +%F)

  if [ "$FORCE" != 1 ] && awk -v v="${current:-0}" 'BEGIN{exit !(v+0 != 0)}'; then
    echo "  skip     $name already has $current @ ${curdate%%T*} (use --force)"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$current" = "$opening" ] && [ "${curdate%%T*}" = "$obdate" ]; then
    echo "  ok       $name $opening @ $obdate (unchanged)"
    skipped=$((skipped + 1))
    continue
  fi

  body=$(jq -n --arg ob "$opening" --arg d "$obdate" \
    '{opening_balance: $ob, opening_balance_date: $d}')

  if [ "$DRY_RUN" = 1 ]; then
    echo "  would set $name $opening @ $obdate (was ${current:-none} @ ${curdate%%T*}) [$src]"
    set=$((set + 1))
    continue
  fi

  if resp=$(api PUT "/api/v1/accounts/$id" "$body"); then
    echo "  set      $name $opening @ $obdate (was ${current:-none} @ ${curdate%%T*}) [$src]"
    set=$((set + 1))
  else
    echo "  FAILED   $name: $(jq -r '.message // .' <<<"$resp" 2>/dev/null || printf '%s' "$resp")"
    failed=$((failed + 1))
  fi
done

echo
echo "set $set, skipped $skipped, failed $failed"
if [ "$set" -eq 0 ] && [ "$skipped" -eq 0 ]; then
  echo
  echo "  NO BALANCES SET — no export carried an IBAN, Von and Anfangssaldo." >&2
  echo "  A custom date range omits the balances; export a defined statement" >&2
  echo "  period instead." >&2
  exit 2
fi
[ "$failed" -eq 0 ]
