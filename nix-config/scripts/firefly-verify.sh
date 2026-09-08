#!/usr/bin/env bash
# Prove an import is complete: compare Firefly's balance to the bank's own.
#
#   firefly-verify.sh FILE.csv [FILE2.csv ...]
#
# Every UBS export states the balance the account ended the period on:
#   Bis:;2026-05-31;
#   Schlusssaldo:;7157.17;
# If Firefly's balance for that account on that date matches, then every
# transaction in the statement arrived, with the right sign, and nothing was
# imported twice. That is the whole point of this script — it is the end-to-end
# check that the reconciliation inside the converter cannot make, because the
# converter never talks to Firefly.
#
# Exits non-zero if any account disagrees.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/firefly-api.sh"

[ $# -gt 0 ] || die "no UBS exports given
       usage: $(basename "$0") FILE.csv [FILE2.csv ...]"

firefly_hello

accounts=$(api GET '/api/v1/accounts?type=asset&limit=500') || die "cannot list accounts"

printf '\n  %-12s %-12s %14s %14s   %s\n' ACCOUNT AS-OF FIREFLY STATEMENT ''
ok=0 bad=0
for f in "$@"; do
  [ -r "$f" ] || die "cannot read $f"
  iban=$(norm "$(ubs_field "$f" 'IBAN')")
  bis=$(ubs_field "$f" 'Bis')
  closing=$(ubs_field "$f" 'Schlusssaldo')
  [ -n "$iban" ] && [ -n "$bis" ] && [ -n "$closing" ] || {
    echo "  skip     $(basename "$f") (incomplete preamble)"
    continue
  }

  id=$(jq -r --arg i "$iban" \
    '.data[] | select((.attributes.iban // "" | ascii_upcase | gsub("\\s";"")) == $i) | .id' \
    <<<"$accounts")
  name=$(jq -r --arg i "$iban" \
    '.data[] | select((.attributes.iban // "" | ascii_upcase | gsub("\\s";"")) == $i) | .attributes.name' \
    <<<"$accounts")
  if [ -z "$id" ]; then
    printf '  %-12s %-12s %14s %14s   NO ACCOUNT WITH IBAN %s\n' "?" "$bis" "-" "$closing" "$iban"
    bad=$((bad + 1))
    continue
  fi

  # `date` makes Firefly report the balance as of the end of that day.
  actual=$(api GET "/api/v1/accounts/$id?date=$bis" | jq -r '.data.attributes.current_balance')
  if awk -v a="$actual" -v b="$closing" 'BEGIN{exit !(((a-b)<0.005)&&((b-a)<0.005))}'; then
    printf '  %-12s %-12s %14s %14s   OK\n' "$name" "$bis" "$actual" "$closing"
    ok=$((ok + 1))
  else
    diff=$(awk -v a="$actual" -v b="$closing" 'BEGIN{printf "%+.2f", a-b}')
    printf '  %-12s %-12s %14s %14s   MISMATCH %s\n' "$name" "$bis" "$actual" "$closing" "$diff"
    bad=$((bad + 1))
  fi
done

echo
echo "$ok matching, $bad mismatched"
# A run that checked nothing must not look like a pass. This happens when the
# exports came from a custom date range: UBS leaves Anfangssaldo/Schlusssaldo
# empty there, so every file is skipped and there is nothing to compare against.
if [ "$ok" -eq 0 ] && [ "$bad" -eq 0 ]; then
  echo
  echo "  NOTHING VERIFIED — every file was skipped. Re-export from UBS as a" >&2
  echo "  defined statement period so it carries Schlusssaldo." >&2
  exit 2
fi
[ "$bad" -eq 0 ]
