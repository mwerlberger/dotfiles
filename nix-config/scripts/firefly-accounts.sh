#!/usr/bin/env bash
# Seed Firefly III with asset accounts from a TSV file.
#
# Idempotent: an account is skipped if its IBAN or name already exists, so this
# is safe to re-run after adding lines to the TSV (Saxo, the 3a accounts, ...).
#
# The account list lives OUTSIDE this repo on purpose — the repo is public and
# IBANs are personal data. Default location:
#   ~/.config/firefly/accounts.tsv
# Format is three tab-separated columns, '#' comments and blank lines ignored:
#   name <TAB> account_role <TAB> IBAN
# account_role is one of: defaultAsset savingAsset sharedAsset ccAsset cashWalletAsset
# ccAsset rows also get credit_card_type=monthlyFull and a monthly_payment_date
# (override with FIREFLY_CC_PAYMENT_DATE=YYYY-MM-DD), which Firefly requires.
# The IBAN column may be empty (account is created without one, but then it will
# not auto-match during an import until you fill it in).
#
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/firefly-api.sh"

DATA="${FIREFLY_ACCOUNTS:-${XDG_CONFIG_HOME:-$HOME/.config}/firefly/accounts.tsv}"
CURRENCY="${FIREFLY_CURRENCY:-CHF}"
# Only used for ccAsset rows; the day of the month the card is settled.
CC_PAYMENT_DATE="${FIREFLY_CC_PAYMENT_DATE:-$(date +%Y-%m-01)}"

[ -r "$DATA" ] || die "account list not found: $DATA
       Create it (see the header of this script for the format), or point
       FIREFLY_ACCOUNTS at another file."

firefly_hello

# --- currency ---------------------------------------------------------------
# Accounts inherit the primary currency when currency_code is not honoured, and
# changing an account's currency after it holds transactions is painful. Make
# sure CHF is enabled and primary BEFORE creating anything.
cur=$(api GET "/api/v1/currencies/$CURRENCY") || die "currency $CURRENCY not found"
if [ "$(jq -r '.data.attributes.enabled' <<<"$cur")" != "true" ]; then
  echo "==> enabling $CURRENCY"
  [ "$DRY_RUN" = 1 ] || api POST "/api/v1/currencies/$CURRENCY/enable" >/dev/null
fi
if [ "$(jq -r '.data.attributes.primary' <<<"$cur")" != "true" ]; then
  echo "==> making $CURRENCY the primary currency"
  [ "$DRY_RUN" = 1 ] || api POST "/api/v1/currencies/$CURRENCY/primary" >/dev/null
fi

# --- existing accounts ------------------------------------------------------
existing=$(api GET '/api/v1/accounts?type=asset&limit=500') || die "cannot list accounts"
have_iban=$(jq -r '.data[].attributes.iban // empty' <<<"$existing" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
have_name=$(jq -r '.data[].attributes.name' <<<"$existing")

created=0 skipped=0 failed=0

# Split on \001, not on tab: bash counts tab as IFS *whitespace* and collapses
# runs of it, so a row with an empty middle column ("Wise EUR" has no IBAN)
# would silently shift every later field one to the left.
while IFS=$'\001' read -r name role iban key currency; do
  # 5th column overrides the default; a Wise EUR balance is not a CHF account.
  acct_currency=${currency:-$CURRENCY}
  # skip comments and blanks
  [ -z "${name// /}" ] && continue
  case "$name" in \#*) continue ;; esac

  niban=$(norm "${iban:-}")

  if [ -n "$niban" ] && grep -qxF "$niban" <<<"$have_iban"; then
    echo "  skip     $name (IBAN already present)"
    skipped=$((skipped + 1))
    continue
  fi
  if grep -qxF "$name" <<<"$have_name"; then
    echo "  skip     $name (name already present)"
    skipped=$((skipped + 1))
    continue
  fi

  body=$(jq -n \
    --arg name "$name" \
    --arg role "$role" \
    --arg cur "$acct_currency" \
    --arg iban "$niban" \
    --arg ccdate "$CC_PAYMENT_DATE" \
    '{
       name: $name,
       type: "asset",
       account_role: $role,
       currency_code: $cur,
       active: true,
       include_net_worth: true
     }
     + (if $iban == "" then {} else {iban: $iban} end)
     # ccAsset is the only role with extra required fields: Firefly rejects it
     # without a credit_card_type and a monthly_payment_date. "monthlyFull" is
     # the only type it accepts.
     + (if $role == "ccAsset"
        then {credit_card_type: "monthlyFull", monthly_payment_date: $ccdate}
        else {} end)')

  if [ "$DRY_RUN" = 1 ]; then
    echo "  would create  $name ($role/$acct_currency)${niban:+ $niban}"
    created=$((created + 1))
    continue
  fi

  if resp=$(api POST /api/v1/accounts "$body"); then
    echo "  created  $name ($role/$acct_currency)${niban:+ $niban}"
    created=$((created + 1))
  else
    echo "  FAILED   $name: $(jq -r '.message // .' <<<"$resp" 2>/dev/null || printf '%s' "$resp")"
    failed=$((failed + 1))
  fi
done < <(tr '\t' '\001' <"$DATA")

echo
echo "created $created, skipped $skipped, failed $failed"
[ "$failed" -eq 0 ]
