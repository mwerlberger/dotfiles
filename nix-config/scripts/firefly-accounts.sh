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
# The IBAN column may be empty (account is created without one, but then it will
# not auto-match during a camt.053 import until you fill it in).
#
# Talks to the loopback Caddy vhost, which bypasses tailscale_auth; auth is the
# API token, so this only works while running on sagittarius itself.
set -euo pipefail

API="${FIREFLY_API:-http://127.0.0.1:8461}"
DATA="${FIREFLY_ACCOUNTS:-${XDG_CONFIG_HOME:-$HOME/.config}/firefly/accounts.tsv}"
CURRENCY="${FIREFLY_CURRENCY:-CHF}"
TOKEN_FILE="${FIREFLY_TOKEN_FILE:-/run/agenix/firefly-iii-importer-token}"
DRY_RUN="${DRY_RUN:-0}"

die() {
  echo "error: $*" >&2
  exit 1
}

[ -r "$DATA" ] || die "account list not found: $DATA
       Create it (see the header of this script for the format), or point
       FIREFLY_ACCOUNTS at another file."

TOKEN="${FIREFLY_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  TOKEN=$(sudo cat "$TOKEN_FILE") || die "cannot read token from $TOKEN_FILE"
fi

# api METHOD PATH [json-body] -> prints body, returns non-zero on HTTP >= 300
api() {
  local method=$1 path=$2 body=${3:-} out code
  local -a args=(
    -sS -X "$method" -w '\n%{http_code}'
    -H 'Accept: application/json'
    -H "Authorization: Bearer $TOKEN"
  )
  [ -n "$body" ] && args+=(-H 'Content-Type: application/json' -d "$body")
  out=$(curl "${args[@]}" "$API$path")
  code=${out##*$'\n'}
  printf '%s' "${out%$'\n'*}"
  [ "$code" -lt 300 ]
}

# Normalise an IBAN for comparison: strip whitespace, uppercase.
norm() { printf '%s' "$1" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'; }

echo "==> Firefly III at $API"
about=$(api GET /api/v1/about) || die "API unreachable or token rejected"
echo "    version $(jq -r '.data.version' <<<"$about"), db $(jq -r '.data.driver' <<<"$about")"

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

while IFS=$'\t' read -r name role iban; do
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
    --arg cur "$CURRENCY" \
    --arg iban "$niban" \
    '{
       name: $name,
       type: "asset",
       account_role: $role,
       currency_code: $cur,
       active: true,
       include_net_worth: true
     }
     + (if $iban == "" then {} else {iban: $iban} end)')

  if [ "$DRY_RUN" = 1 ]; then
    echo "  would create  $name ($role)${niban:+ $niban}"
    created=$((created + 1))
    continue
  fi

  if resp=$(api POST /api/v1/accounts "$body"); then
    echo "  created  $name ($role)${niban:+ $niban}"
    created=$((created + 1))
  else
    echo "  FAILED   $name: $(jq -r '.message // .' <<<"$resp" 2>/dev/null || printf '%s' "$resp")"
    failed=$((failed + 1))
  fi
done <"$DATA"

echo
echo "created $created, skipped $skipped, failed $failed"
[ "$failed" -eq 0 ]
