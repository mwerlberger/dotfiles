#!/usr/bin/env bash
# Roll back one import by its tag.
#
#   firefly-undo-import.sh                  # list import tags with their sizes
#   firefly-undo-import.sh TAG              # delete every transaction carrying TAG
#   firefly-undo-import.sh --purge-deleted  # only purge soft-deleted rows
#
# Use --purge-deleted to unblock a re-import after transactions were removed
# some other way — through the Firefly UI, or by an older version of this script
# that did not purge. Without it those rows keep rejecting their own external_id.
#
# The importer config sets `add_import_tag: true`, so each run stamps its
# transactions with a tag naming that run. Deleting by tag is therefore an exact
# undo, which is what makes it safe to import a couple of accounts as a smoke
# test and then redo the whole thing properly: internal transfers only resolve
# when the sending account's statement is in the same batch, so a partial import
# leaves credits sitting as deposits from person-named revenue accounts.
#
# The tag itself is removed too, so a re-import gets a clean one.
#
# One wrinkle makes this more than a loop over DELETE calls: Firefly soft-deletes
# transactions, and its external-id duplicate check counts soft-deleted ones —
#   "There is already a (deleted) transaction with external_id X, so this
#    transaction will be skipped."
# so an API-only delete silently makes that data UNIMPORTABLE FOREVER. Firefly
# 6.6.3 ships no purge command, so this script finishes the job in SQL. That is
# what Firefly's own "purge deleted records" admin function does, and every
# dependent table cascades from transaction_journals.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/firefly-api.sh"

DB="${FIREFLY_DB:-firefly-iii}"

# Hard-delete what Firefly only marked as deleted. Everything else cascades from
# transaction_journals, so one statement does the work; the second clears the
# transaction groups those journals leave behind.
#
# Emptiness of a group MUST be tested through transaction_journals. The obvious
# `group_journals` pivot is legacy and sits empty in Firefly 6, so a NOT EXISTS
# against it matches every group — and since transaction_journals.transaction_
# group_id cascades, deleting those groups deletes the entire ledger. Ask how
# this comment came to be written.
purge_deleted() {
  local n
  n=$(sudo -u postgres psql -d "$DB" -tAc \
    "SELECT count(*) FROM transaction_journals WHERE deleted_at IS NOT NULL") ||
    die "cannot reach database $DB"
  if [ "$n" -eq 0 ]; then
    echo "  no soft-deleted journals to purge"
    return 0
  fi
  sudo -u postgres psql -d "$DB" -v ON_ERROR_STOP=1 -q \
    -c "DELETE FROM transaction_journals WHERE deleted_at IS NOT NULL" \
    -c "DELETE FROM transaction_groups tg
         WHERE NOT EXISTS (SELECT 1 FROM transaction_journals tj
                            WHERE tj.transaction_group_id = tg.id)" ||
    die "could not purge soft-deleted journals from $DB"
  echo "  purged $n soft-deleted journal(s) — re-import is possible again"
}

firefly_hello

if [ "${1:-}" = "--purge-deleted" ]; then
  purge_deleted
  exit 0
fi

if [ $# -eq 0 ]; then
  echo
  echo "  import tags:"
  api GET '/api/v1/tags?limit=200' |
    jq -r '.data[] | "    \(.attributes.tag)"' | sort
  echo
  echo "  re-run with a tag to delete its transactions."
  exit 0
fi

TAG=$1

# The tag endpoint paginates; collect every page before deleting anything, so a
# partial read cannot turn into a partial delete.
ids=$(
  page=1
  while :; do
    resp=$(api GET "/api/v1/tags/$(jq -rn --arg t "$TAG" '$t|@uri')/transactions?limit=100&page=$page") ||
      die "no such tag: $TAG"
    jq -r '.data[].id' <<<"$resp"
    total=$(jq -r '.meta.pagination.total_pages // 1' <<<"$resp")
    [ "$page" -ge "$total" ] && break
    page=$((page + 1))
  done
)

count=$(printf '%s' "$ids" | grep -c . || true)
if [ "$count" -eq 0 ]; then
  echo "  tag '$TAG' has no transactions"
  exit 0
fi

echo "  tag '$TAG' has $count transaction(s)"
if [ "$DRY_RUN" = 1 ]; then
  echo "  DRY_RUN=1, nothing deleted"
  exit 0
fi

read -rp "  delete all $count? type 'yes' to confirm: " reply
[ "$reply" = "yes" ] || die "aborted"

deleted=0 failed=0
for id in $ids; do
  if api DELETE "/api/v1/transactions/$id" >/dev/null; then
    deleted=$((deleted + 1))
  else
    echo "  FAILED to delete transaction $id"
    failed=$((failed + 1))
  fi
done

# Drop the now-empty tag so the next import does not accumulate stale ones.
tag_id=$(api GET '/api/v1/tags?limit=200' | jq -r --arg t "$TAG" \
  '.data[] | select(.attributes.tag == $t) | .id')
[ -n "$tag_id" ] && api DELETE "/api/v1/tags/$tag_id" >/dev/null || true

purge_deleted

echo
echo "deleted $deleted, failed $failed"
[ "$failed" -eq 0 ]
