# Firefly III — importing UBS statements

Personal finance on `sagittarius`. Firefly III and its data importer run behind Caddy with
Tailscale auth; see `hosts/nixos/sagittarius/services/firefly-iii.nix`.

UBS Switzerland has no self-service open-banking API — Swiss banks sit behind SIX bLink,
which needs a business contract — so everything here is built around **file import**.

## Quick reference

```bash
cd ~/dotfiles/nix-config
D=/data/lake/documents/firefly-import

# 0. drop every account's export for the period into $D/inbox/

scripts/firefly-opening-balances.sh --force $D/inbox/*.csv   # anchor the balances
firefly-import --convert-only                                # READ THE REPORT
firefly-import                                               # convert + import
scripts/firefly-verify.sh $D/archive/*.csv                   # prove it is complete
scripts/firefly-rules.sh --apply                             # categories (after edits)
```

Order matters only in one place: `firefly-import` moves raw exports from `inbox/` to
`archive/`, so run `firefly-opening-balances.sh` against `inbox/` *before* the first
`firefly-import`, or against `archive/` afterwards.

**Import every account for the whole period in one batch.** Incoming transfers carry no
counterparty IBAN, and the only thing linking the two sides of an internal transfer is a
shared `Transaktions-Nr.` that the converter can see only if both statements are in the
same run. Import account-by-account and the credit sides land as deposits from revenue
accounts named after whoever holds the account.

## Exporting from UBS

UBS E-Banking → Konten → Bewegungen → Export → **CSV**.

Export a **defined statement period**, not a custom date range. A custom range returns a
file with `Anfangssaldo`, `Schlusssaldo` and the whole `Saldo` column empty, which costs you
opening balances, the end-to-end verification, and the converter's reconciliation check —
i.e. every guarantee that the import is complete.

CSV is the only usable format. Both alternatives were checked against real statements:

- **MT940** (and its `-light` variant, the same file minus the SWIFT envelope) carries no
  counterparty IBANs at all — the only IBAN in the file is your own `:25:` line — has no
  purchase dates, no FX detail, and silently drops transactions: 47 entries against 60 CSV
  rows on one statement, 59 against 68 on another.
- **camt.053** would be ideal (structured counterparty accounts on both debits and credits)
  but UBS does not offer it for private accounts.

## Configuration lives outside this repo

This repo is public, so the tables holding IBANs and a record of where you shop are kept in
`~/.config/firefly/`. All are tab-separated, `#` comments and blank lines ignored.

| File | Format | Purpose |
|---|---|---|
| `accounts.tsv` | `name <TAB> role <TAB> IBAN` | your asset accounts. `role` is one of `defaultAsset` `savingAsset` `sharedAsset` `ccAsset` `cashWalletAsset`; IBAN may be empty |
| `payees.tsv` | `pattern <TAB> canonical name` | normalizes counterparty names — decides which **account** a transaction lands in |
| `rules.tsv` | `category <TAB> keyword\|keyword` | decides which **category** it gets |

Adding or renaming a category touches `rules.tsv` only. You'd edit `payees.tsv` only when a
merchant's UBS spelling needs cleaning up so a keyword can match it.

### payees.tsv

Three pattern forms:

```
Migros                   case-insensitive substring of the payee name
re:^Coop-                regex against the payee name
iban:CH00 0000 0000 0    exact match on the counterparty IBAN
```

IBAN patterns always run first, whatever order the file is in. UBS names the account
**holder**, never the account, so one person's name can be three different destinations in a
single statement — their pocket-money account, their fund account, their savings account.
Only the IBAN separates them.

Investment depots (VZ, Saxo, brokers, children's fund accounts) are deliberately **not** in
`accounts.tsv`. What sits in them is a securities position, not cash, so a Firefly balance
would be wrong by however much the market moved. They are matched by `iban:` here, which
makes them expense accounts — targets you send money to — and a category on the outgoing
payment keeps the saving visible without pretending to know what it is worth. The IBAN is
essential: UBS writes the account *holder* in `Beschreibung1`, so one name can be the VZ
depot, a Saxo account and a person's own account all at once.

If a canonical name matches one of your own accounts in `accounts.tsv`, the converter fills
in that account's IBAN and the row becomes a **transfer**. This is the only way to recover
the far side of an incoming transfer, which carries no IBAN of its own. It deliberately does
not apply to a row that already names a foreign IBAN — that money left the bank.

Watch for over-broad patterns. Trailing whitespace is stripped, so a regex must never end in
a literal space: `re:^(M|Migros) ` silently becomes `^(M|Migros)` and swallows every payee
starting with M. To audit:

```bash
python3 scripts/ubs-csv-to-firefly.py $D/inbox/*.csv -o /tmp/x.csv --explain-payees
```

which prints exactly which raw names each pattern absorbed.

### rules.tsv

Each line becomes one Firefly rule whose triggers are OR'd (`description_contains`) with a
single `set_category` action. **Line order is evaluation order**, and rules do not stop
processing — when a payee matches two rules the last one wins. Put broad categories first
and specific ones below.

Rules match the *description*, which for a normal payment is the canonical name from
`payees.tsv`. Normalize there first, then match one clean name here.

Don't use a payment processor as a keyword. `SumUp` fronts restaurants, hairdressers and
market stalls alike; match the merchant behind it instead.

## The scripts

All of them talk to Firefly over a loopback-only Caddy vhost on `127.0.0.1:8461` that
bypasses `tailscale_auth`, authenticating with the API token in
`/run/agenix/firefly-iii-importer-token`. They therefore only work while running on
`sagittarius` itself. Shared client: `scripts/lib/firefly-api.sh`. Most honour `DRY_RUN=1`.

### `firefly-import` (on `$PATH`, defined in the nix module)

Converts every CSV in `inbox/` in a **single** pass into one importable CSV plus its
importer config, runs `importer:auto-import` over it, and archives what it processed.
`--convert-only` stops before importing; `--dry-run` shows what would happen.

The converter is baked into the nix store, so **editing
`scripts/ubs-csv-to-firefly.py` requires `nixos-rebuild switch`** before this wrapper sees
the change.

### `scripts/ubs-csv-to-firefly.py`

The interesting one. Turns raw UBS exports into a CSV the importer maps 1:1, and emits the
importer config beside it — built from the column list it just wrote, so the roles can never
drift from the file they describe. What it handles that a plain column mapping cannot:

- **Statement integrity.** Checks `Anfangssaldo + Σ = Schlusssaldo` and the row count against
  `Anzahl Transaktionen`, and refuses to write on a mismatch. This is the guard that catches a
  parsing bug that silently drops or double-counts rows.
- **Internal transfers.** Pairs the two sides on their shared `Transaktions-Nr.` — an exact
  join, not a heuristic, which matters because identical standing orders a week apart would
  defeat any fuzzy matcher. Keeps the debit side; it is the only one carrying the
  counterparty IBAN, and its `Zahlungsgrund` is a far better description than the account
  holder's name.
- **Counterparty IBAN** extracted from the free text in `Beschreibung3`.
- **Foreign-currency card payments.** `Kartentransaktionsbetrag: -50.00 EUR` becomes Firefly's
  foreign amount. The booked CHF stays authoritative — it includes the card fee, so the rate
  Firefly implies differs slightly from the exact `Devisenkurs`, which stays in the note.
- **Standing orders.** UBS splits these over two rows sharing one `Transaktions-Nr.`: the
  parent has the amount and the useless name "Diverse Daueraufträge", the detail has the real
  payee and IBAN. They get merged.
- **Unbooked transactions.** Rows are kept on `Transaktions-Nr.`, not `Buchungsdatum` — a
  payment that has not been booked yet has no booking date, and dropping it loses real money.
- **Dates.** `Abschlussdatum` (when you actually paid) is the transaction date, not
  `Buchungsdatum` — they differ on about 70% of rows, so card spend lands in the month it
  happened.

Read its report before importing. It lists transfers found, credits it could not explain, and
payees that matched no pattern.

### `scripts/firefly-accounts.sh`

Creates the asset accounts from `accounts.tsv`. Idempotent — skips an account whose IBAN or
name already exists. Also makes sure CHF is enabled and primary *before* creating anything,
since changing an account's currency after it holds transactions is painful.

### `scripts/firefly-opening-balances.sh`

Reads `Anfangssaldo` and `Von` from each export's preamble and writes the balance to the
matching account, dated the day before the period starts. Earliest statement per IBAN wins.
`--force` overwrites an existing balance, which is what you want after extending history
backwards. Nothing is typed by hand.

### `scripts/firefly-verify.sh`

The end-to-end proof. For each raw export, compares Firefly's balance on the statement's
`Bis` date against its `Schlusssaldo`. If every account matches, the import is complete,
correctly signed and not double-counted. Exits non-zero on any mismatch.

### `scripts/firefly-rules.sh [--apply]`

Syncs `rules.tsv` into a Firefly rule group. `--apply` also fires the group over transactions
already imported — otherwise edits only affect the next import.

Every generated rule is stamped with a marker in its description, and the script only ever
updates or prunes rules carrying it. **Rules you write in the Firefly UI are never touched**,
in this group or any other. Both kinds fire during import. So you can work either way: edit
`rules.tsv` for something version-controlled and reproducible, or work in the UI for speed —
just don't hand-edit a *generated* rule, it will be overwritten.

### `scripts/firefly-undo-import.sh`

```bash
scripts/firefly-undo-import.sh                  # list import tags
scripts/firefly-undo-import.sh "<tag>"          # roll that import back
scripts/firefly-undo-import.sh --purge-deleted  # unblock a re-import after a UI delete
```

Every import is tagged, so a rollback is exact — which is what makes it safe to try an import,
look at it, and redo it.

This is more than a loop of DELETE calls. Firefly *soft*-deletes transactions and its
external-id duplicate check counts soft-deleted ones:

```
There is already a (deleted) transaction with external_id X, so this transaction
will be skipped.
```

so an API-only delete makes that data **unimportable forever**. Firefly 6.6.3 ships no purge
command, so the script finishes the job in SQL — the same thing Firefly's own "purge deleted
records" admin function does. Use `--purge-deleted` on its own to recover from deletions made
in the UI.

## Gotchas

- **Renaming an account is safe if it has an IBAN**, because IBAN is the key everywhere:
  transfers, opening balances, verification. An account *without* an IBAN is known only by
  name, which must then agree across Firefly, `accounts.tsv` and `payees.tsv` — rename it in
  one place only and the next import creates a second account under the old name.
- **A payee rule cannot rename an account Firefly already created with that IBAN.** Firefly
  matches expense accounts on IBAN too, so the old name sticks. Rename it once in the UI; the
  rule keeps it right from then on.
- **Renaming a category** goes through `rules.tsv` plus a re-run, not the UI — otherwise the
  rule just recreates the old one.
- **Firefly matches expense and revenue accounts by name only**, ignoring IBAN for those
  types. That is why `payees.tsv` is load-bearing rather than cosmetic.

## Bootstrap from nothing

1. Deploy. `secrets/firefly-iii-app-key.age` holds the generated key.
2. Open the Firefly vhost — the Tailscale login auto-creates the first user as owner.
3. Options → Profile → OAuth → create a Personal Access Token, then
   `agenix -e secrets/firefly-iii-importer-token.age` and redeploy.
4. Write `~/.config/firefly/accounts.tsv`, run `scripts/firefly-accounts.sh`.
5. Follow the quick reference above.
