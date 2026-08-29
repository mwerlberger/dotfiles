# Shared Firefly III API client for the scripts in this directory.
# Source it, do not execute it:
#     . "$(dirname "$0")/lib/firefly-api.sh"
#
# Talks to the loopback Caddy vhost, which bypasses tailscale_auth; auth is the
# API token, so this only works while running on sagittarius itself.

API="${FIREFLY_API:-http://127.0.0.1:8461}"
TOKEN_FILE="${FIREFLY_TOKEN_FILE:-/run/agenix/firefly-iii-importer-token}"
DRY_RUN="${DRY_RUN:-0}"

die() {
  echo "error: $*" >&2
  exit 1
}

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

# Fail early and with a useful message rather than on the first real call.
firefly_hello() {
  local about
  echo "==> Firefly III at $API"
  about=$(api GET /api/v1/about) || die "API unreachable or token rejected"
  echo "    version $(jq -r '.data.version' <<<"$about"), db $(jq -r '.data.driver' <<<"$about")"
}

# Normalise an IBAN for comparison: strip whitespace, uppercase.
norm() { printf '%s' "$1" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'; }

# Read one preamble field out of a raw UBS CSV export.
#   ubs_field FILE 'Anfangssaldo'  ->  5905.71
# Thousands separators are stripped: the file uses plain decimals but the
# e-banking UI shows 5'905.71, and a format change must not corrupt an amount.
ubs_field() {
  # sed strips a leading UTF-8 BOM, then the label; tr drops the ' thousands
  # separator, stray spaces (IBANs are printed grouped) and the CRLF.
  head -12 "$1" | sed -e '1s/^\xef\xbb\xbf//' -n -e "s/^$2:;[[:space:]]*\([^;]*\).*/\1/p" |
    head -1 | tr -d "' " | tr -d '\r'
}
