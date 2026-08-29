#!/usr/bin/env python3
"""Convert UBS Switzerland e-banking CSV exports into a CSV the Firefly III
data importer can map 1:1, plus the importer config that describes it.

Why this exists: the raw UBS export is not directly importable.
  * 8 preamble lines (Kontonummer, IBAN, Von/Bis, Saldi) sit above the header.
  * The counterparty IBAN is buried in free text inside `Beschreibung3`
    ("Konto-Nr. IBAN: CH.."), not in its own column. Without extracting it,
    transfers between your own accounts import as unrelated withdrawal +
    deposit pairs instead of collapsing into a single transfer.
  * The counterparty name is the first `;`-separated subfield of a quoted
    `Beschreibung1` that also holds the street address.
  * Debit and credit are separate columns.
  * The original amount of a foreign-currency card payment only exists as
    free text ("Kartentransaktionsbetrag: -115.00 EUR").

Only the CSV export is usable. Both other formats UBS offers were checked
against real statements and rejected:
  * MT940 (and its "light" variant, which is the same file minus the SWIFT
    {1:..} envelope) carries no counterparty IBANs at all — the only IBAN in
    the file is the account's own `:25:` line — uses a proprietary compact
    `:86:` (`K70?CROSSFIT KREIS 9`) with none of the structured ?31/?32
    subfields other banks emit, has no purchase date and no FX detail, and
    silently drops transactions: 47 entries against 60 CSV rows for one
    statement, 59 against 68 for another.
  * camt.053 would be ideal (it has structured counterparty accounts on both
    debit and credit entries) but UBS does not offer it for private accounts.

Incoming transfers never carry a counterparty IBAN, so the credit side of an
internal transfer looks like an ordinary deposit from a person. UBS puts the
*same* `Transaktions-Nr.` on both sides, which makes pairing them exact rather
than a guess — see pair_transfers().

Usage:
    ubs-csv-to-firefly.py INPUT.csv [INPUT2.csv ...] [-o OUTFILE]

Convert every statement of a period in one run: pairing only sees the rows in
the batch. Rows are written to one combined CSV (default: alongside the first
input, `*-firefly.csv`) with a `<output>.json` importer config beside it.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
from collections import defaultdict
from datetime import date
from pathlib import Path

HEADER_STARTS = "Abschlussdatum"
IBAN_RE = re.compile(r"Konto-Nr\.\s*IBAN:\s*([A-Z]{2}[0-9A-Z ]{13,32}?)\s*(?:;|$)")
# The export preamble names the account the statement belongs to:
#   IBAN:;CH88 0023 0230 1518 2740 V;
OWN_IBAN_RE = re.compile(r"^IBAN:;\s*([A-Z]{2}[0-9A-Z ]{13,32}?)\s*;?\s*$", re.MULTILINE)
PREAMBLE_RE = {
    "von": re.compile(r"^Von:;\s*(\d{4}-\d{2}-\d{2})", re.MULTILINE),
    "bis": re.compile(r"^Bis:;\s*(\d{4}-\d{2}-\d{2})", re.MULTILINE),
    "opening": re.compile(r"^Anfangssaldo:;\s*([-\d.',]+)", re.MULTILINE),
    "closing": re.compile(r"^Schlusssaldo:;\s*([-\d.',]+)", re.MULTILINE),
    "count": re.compile(r"^Anzahl Transaktionen[^;]*:;\s*(\d+)", re.MULTILINE),
}
# "Kartentransaktionsbetrag: -115.00 EUR; Devisenkurs: 0.948178"
FX_RE = re.compile(r"Kartentransaktionsbetrag:\s*(-?[\d.',]+)\s*([A-Z]{3})")
# "Zahlungsgrund: Haushalt Fixkosten;" — the only human-written field UBS keeps.
REASON_RE = re.compile(r"Zahlungsgrund:\s*([^;]+)")

# Column -> Firefly III data importer role. Order is the file's column order;
# the emitted config derives `roles` from this, so the two cannot drift apart.
FIELD_ROLES = {
    "account_iban": "account-iban",
    "date": "date_transaction",
    "book_date": "date_book",
    "process_date": "date_process",
    "amount": "amount",
    "currency": "currency-code",
    "foreign_amount": "amount_foreign",
    "foreign_currency": "foreign-currency-code",
    "external_id": "external-id",
    "opposing_name": "opposing-name",
    "opposing_iban": "opposing-iban",
    "description": "description",
    "notes": "note",
}
OUT_FIELDS = list(FIELD_ROLES)

DEFAULT_ACCOUNTS_TSV = Path.home() / ".config/firefly/accounts.tsv"
DEFAULT_PAYEES_TSV = Path.home() / ".config/firefly/payees.tsv"


def clean(value: str | None) -> str:
    """Collapse the whitespace UBS sprinkles around subfields."""
    return re.sub(r"\s+", " ", (value or "").replace("\n", " ")).strip()


def subfields(value: str | None) -> list[str]:
    """UBS packs several values into one quoted field, separated by ';'."""
    return [clean(p) for p in (value or "").split(";") if clean(p)]


def norm_iban(value: str | None) -> str:
    return (value or "").replace(" ", "").upper()


def number(value: str | None) -> str:
    """UBS writes plain decimals in the file but ' as a thousands separator in
    the UI; strip it so a future export style change cannot corrupt an amount."""
    return (value or "").replace("'", "").replace(" ", "")


class Statement:
    """One UBS export: the preamble facts plus its transaction rows."""

    def __init__(self, path: Path):
        # utf-8-sig: the export carries a BOM.
        text = path.read_text(encoding="utf-8-sig", newline="")
        lines = text.splitlines(keepends=True)
        header = next(
            (i for i, line in enumerate(lines) if line.startswith(HEADER_STARTS)), None
        )
        if header is None:
            raise SystemExit(
                f"{path}: no '{HEADER_STARTS}' header row found — not a UBS export?"
            )

        preamble = "".join(lines[:header])
        self.path = path
        self.own_iban = norm_iban(
            m.group(1) if (m := OWN_IBAN_RE.search(preamble)) else ""
        )
        self.facts = {
            key: (m.group(1) if (m := rx.search(preamble)) else "")
            for key, rx in PREAMBLE_RE.items()
        }
        reader = csv.DictReader(io.StringIO("".join(lines[header:])), delimiter=";")
        # Every real row carries a Transaktions-Nr.; trailing summary and blank
        # lines do not. Booking date is NOT a usable filter — a payment that has
        # not been booked yet has none, and dropping those loses real money.
        self.rows = [row for row in reader if clean(row.get("Transaktions-Nr."))]

        # UBS splits a standing order over two rows sharing one Transaktions-Nr.:
        #   parent  Belastung=-500.00   Beschreibung1="Diverse Daueraufträge"
        #   detail  Einzelbetrag=-500.00  "<real payee>"  Konto-Nr. IBAN: CH..
        # Only the parent carries the amount, only the detail knows who was paid.
        # Index the details so convert_row can put the two back together.
        self.details: dict[str, list[dict[str, str]]] = defaultdict(list)
        for row in self.rows:
            if clean(row.get("Einzelbetrag")) and not (
                clean(row.get("Belastung")) or clean(row.get("Gutschrift"))
            ):
                self.details[clean(row["Transaktions-Nr."])].append(row)

        if not self.own_iban:
            raise SystemExit(
                f"{path}: no 'IBAN:' line in the preamble. Without it every row would\n"
                f"       fall back to the config's default_account and land in the wrong\n"
                f"       account — refusing to convert."
            )

    def check(self) -> list[str]:
        """Verify the statement against the bank's own totals.

        This is the guard that catches a parsing bug that silently drops or
        double-counts rows: if the arithmetic still closes, every row was read.
        """
        problems = []
        opening, closing = self.facts["opening"], self.facts["closing"]
        if opening and closing:
            total = sum(
                float(number(clean(r.get("Belastung")) or clean(r.get("Gutschrift"))))
                for r in self.rows
                if clean(r.get("Belastung")) or clean(r.get("Gutschrift"))
            )
            expected = float(number(opening)) + total
            if abs(expected - float(number(closing))) > 0.005:
                problems.append(
                    f"balance mismatch: {number(opening)} + {total:.2f} = {expected:.2f}, "
                    f"but Schlusssaldo is {number(closing)}"
                )
        # "Anzahl Transaktionen" counts rows that move money, so Einzelbetrag
        # detail rows are excluded — count the same way or every statement with
        # a standing order in it looks truncated.
        booked = sum(
            1
            for r in self.rows
            if clean(r.get("Belastung")) or clean(r.get("Gutschrift"))
        )
        if self.facts["count"] and int(self.facts["count"]) != booked:
            problems.append(
                f"row count mismatch: read {booked}, but the preamble says "
                f"{self.facts['count']} transactions — truncated export?"
            )
        return problems


def load_own_ibans(path: Path | None) -> tuple[dict[str, str], set[str]]:
    """(IBAN -> account name, all account names) from the accounts.tsv.

    The IBAN map lets a transfer to an account whose statement is not in this
    batch still be typed as a transfer instead of a payment to a stranger. The
    name set covers accounts whose IBAN is not known yet: Firefly resolves those
    by name (its importer returns a name match only for asset and liability
    accounts), so they still become transfers — they just cannot be matched
    against the IBAN in an outgoing row.
    """
    if not path or not path.is_file():
        return {}, set()
    known, names = {}, set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if not parts[0].strip():
            continue
        names.add(parts[0].strip())
        if len(parts) >= 3 and norm_iban(parts[2]):
            known[norm_iban(parts[2])] = parts[0].strip()
    return known, names


def load_payees(path: Path | None) -> list[tuple[re.Pattern[str], str, str, bool]]:
    """Payee normalization table: `pattern <TAB> canonical name`.

    Firefly matches expense and revenue accounts by *name* (it deliberately
    ignores IBAN matches for those types), so the name in the CSV is the only
    thing deciding which account a transaction lands in. Normalizing here is
    what stops `M ZUERICH-TOBLERPLATZ` and `M EBMATINGEN` becoming two accounts.

    Three pattern forms:
        Migros                  case-insensitive substring of the payee name
        re:^Coop-               regex against the payee name
        iban:CH31 .. 67FK N     exact match on the counterparty IBAN

    IBAN patterns are always tried before name patterns, whatever order the
    file is in. UBS names the account *holder*, not the account, so one name
    covers several destinations — "Teresa Werlberger" is her pocket-money
    account, her fund account and her savings account in the same statement.
    Only the IBAN tells them apart, so it has to win.

    Returns (pattern, canonical name, original pattern text, matches on IBAN).
    """
    if not path or not path.is_file():
        return []
    names, ibans = [], []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        pattern, canonical = parts[0].strip(), parts[1].strip()
        if pattern.startswith("iban:"):
            iban = norm_iban(pattern[5:])
            ibans.append((re.compile(f"^{re.escape(iban)}$"), canonical, pattern, True))
        elif pattern.startswith("re:"):
            names.append((re.compile(pattern[3:], re.I), canonical, pattern, False))
        else:
            names.append((re.compile(re.escape(pattern), re.I), canonical, pattern, False))
    return ibans + names


def convert_row(
    row: dict[str, str],
    own_iban: str,
    details: dict[str, list[dict[str, str]]] | None = None,
) -> dict[str, str] | None:
    debit = number(clean(row.get("Belastung")))
    credit = number(clean(row.get("Gutschrift")))
    amount = debit or credit
    if not amount:
        return None
    # UBS already signs debits negative; be defensive in case a variant does not.
    if debit and not debit.startswith("-"):
        amount = f"-{debit}"

    # A standing-order parent says only "Diverse Daueraufträge" and carries no
    # counterparty. Its single detail row has both, so borrow them; a batch with
    # several different payees cannot be attributed to one and is left alone.
    named = row
    kids = (details or {}).get(clean(row.get("Transaktions-Nr.")), [])
    if len(kids) == 1 and number(clean(kids[0].get("Einzelbetrag"))) == amount:
        named = kids[0]

    parts = subfields(named.get("Beschreibung1"))
    opposing_name = parts[0] if parts else ""

    desc3 = clean(named.get("Beschreibung3")) or clean(row.get("Beschreibung3"))
    opposing_iban = norm_iban(m.group(1)) if (m := IBAN_RE.search(desc3)) else ""

    foreign_amount = foreign_currency = ""
    if m := FX_RE.search(desc3):
        foreign_amount, foreign_currency = number(m.group(1)), m.group(2)
        # Match the sign of the booked amount: Firefly negates both together.
        if amount.startswith("-") and not foreign_amount.startswith("-"):
            foreign_amount = f"-{foreign_amount}"

    type_parts = subfields(row.get("Beschreibung2"))
    # For card payments Beschreibung2 leads with the card number; the useful
    # label ("Zahlung Debitkarte") is last.
    kind = type_parts[-1] if type_parts else ""

    return {
        "account_iban": own_iban,
        # Abschlussdatum is when the payment actually happened; Buchungsdatum is
        # up to three days later. They differ on ~70% of rows.
        "date": (
            clean(row.get("Abschlussdatum"))
            or clean(row.get("Buchungsdatum"))
            or clean(row.get("Valutadatum"))
        ),
        # Empty for a payment that has not been booked yet; the importer treats
        # an empty optional date as absent, so the row still imports.
        "book_date": clean(row.get("Buchungsdatum")),
        "process_date": clean(row.get("Valutadatum")),
        "amount": amount,
        "currency": clean(row.get("Währung")) or "CHF",
        "foreign_amount": foreign_amount,
        "foreign_currency": foreign_currency,
        "external_id": clean(row.get("Transaktions-Nr.")),
        "opposing_name": opposing_name,
        "opposing_iban": opposing_iban,
        "description": opposing_name or kind or "UBS transaction",
        "notes": " | ".join(
            dict.fromkeys(
                p
                for p in (
                    clean(row.get("Beschreibung2")),
                    clean(row.get("Beschreibung3")),
                    desc3,
                )
                if p
            )
        ),
        # Not written out; used for reporting and pairing only.
        "_reason": clean(m.group(1)) if (m := REASON_RE.search(desc3)) else "",
        "_kind": kind,
        # Set when a payee rule resolved this row onto one of your own accounts.
        "_own": "",
    }


def pair_transfers(
    converted: list[dict[str, str]], own: dict[str, str]
) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, str]]]:
    """Collapse the two sides of an internal transfer into one row.

    UBS stamps the same Transaktions-Nr. on both the debit and the credit, so
    this is an exact join rather than an amount/date guess — which matters:
    identical CHF 5.00 standing orders a week apart would defeat any fuzzy
    matcher. The debit is the side worth keeping; it is the only one carrying
    the counterparty IBAN that makes Firefly treat it as a transfer at all.

    Returns (rows to write, dropped credit sides, internal transfers kept).
    """
    by_id: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in converted:
        by_id[row["external_id"]].append(row)

    dropped, kept, transfers = [], [], []
    for row in converted:
        siblings = by_id.get(row["external_id"], [])
        is_credit = not row["amount"].startswith("-")
        if len(siblings) == 2 and is_credit:
            other = siblings[0] if siblings[1] is row else siblings[1]
            if other["amount"].startswith("-") and other["opposing_iban"] == row["account_iban"]:
                dropped.append(row)
                continue
        kept.append(row)
        if row["opposing_iban"] in own or row["_own"]:
            transfers.append(row)

    for row in transfers:
        # "Herr Manuel Werlberger u/o" says nothing; the payment reason does.
        # The name is replaced too: Firefly resolves the far side by IBAN here,
        # and leaving a holder name in the column invites it to create an
        # expense account called "Herr Manuel Werlberger u/o" alongside.
        # An account whose IBAN you do not have yet is only known by name.
        other = own.get(row["opposing_iban"]) or row["_own"]
        row["opposing_name"] = other
        direction = "to" if row["amount"].startswith("-") else "from"
        row["description"] = row["_reason"] or f"Transfer {direction} {other}"
    return kept, dropped, transfers


def importer_config(default_account: int) -> dict:
    """The config the data importer needs alongside the CSV.

    Emitted from FIELD_ROLES so the roles always describe the columns actually
    written. Replaces the config that used to be downloaded from the web UI and
    kept by hand as _fallback.json, where it could silently go stale.
    """
    return {
        "version": 3,
        "flow": "file",
        "content_type": "csv",
        "default_account": default_account,
        "delimiter": "comma",
        "headers": True,
        "date": "Y-m-d",
        "roles": [FIELD_ROLES[f] for f in OUT_FIELDS],
        "do_mapping": [False] * len(OUT_FIELDS),
        "mapping": {},
        # Both sides of an internal transfer share a Transaktions-Nr., so this
        # also stops the credit side being re-imported in a later batch.
        "duplicate_detection_method": "cell",
        "unique_column_index": OUT_FIELDS.index("external_id"),
        "unique_column_type": "external-id",
        "ignore_duplicate_lines": True,
        "ignore_duplicate_transactions": True,
        "rules": True,
        "skip_form": True,
        "add_import_tag": True,
        "conversion": False,
    }


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("inputs", nargs="+", type=Path)
    ap.add_argument("-o", "--output", type=Path)
    ap.add_argument(
        "--own-ibans",
        type=Path,
        default=DEFAULT_ACCOUNTS_TSV,
        help=f"accounts.tsv to read own IBANs from (default: {DEFAULT_ACCOUNTS_TSV})",
    )
    ap.add_argument(
        "--payees",
        type=Path,
        default=DEFAULT_PAYEES_TSV,
        help=f"payee normalization table (default: {DEFAULT_PAYEES_TSV})",
    )
    ap.add_argument(
        "--default-account",
        type=int,
        default=7,
        help="Firefly account id for rows with an unknown IBAN (default: 7)",
    )
    ap.add_argument(
        "--no-config", action="store_true", help="do not write the sidecar .json"
    )
    ap.add_argument(
        "--explain-payees",
        action="store_true",
        help="list which raw payee names each pattern absorbed (catches an "
        "over-broad rule before it renames half your statement)",
    )
    args = ap.parse_args()

    out_path = args.output or args.inputs[0].with_name(
        args.inputs[0].stem + "-firefly.csv"
    )

    statements = [Statement(p) for p in args.inputs]
    own, own_names = load_own_ibans(args.own_ibans)
    own.update({s.own_iban: s.own_iban for s in statements if s.own_iban not in own})
    payees = load_payees(args.payees)

    log = sys.stderr
    failed = False
    converted: list[dict[str, str]] = []
    seen: set[str] = set()
    duplicates = 0
    for st in statements:
        problems = st.check()
        label = own.get(st.own_iban, st.own_iban)
        period = f"{st.facts['von']}..{st.facts['bis']}"
        print(f"  {st.path.name}: {len(st.rows)} rows  {label}  {period}", file=log)
        for problem in problems:
            print(f"    ERROR: {problem}", file=log)
            failed = True

        for row in st.rows:
            out = convert_row(row, st.own_iban, st.details)
            if out is None:
                continue
            # Guard against the same statement being passed twice (overlapping
            # export ranges). Transfer pairs legitimately share an id, so only
            # skip a repeat that is not the opposite side of one already seen.
            key = (out["external_id"], out["amount"])
            if key in seen:
                duplicates += 1
                continue
            seen.add(key)
            converted.append(out)

    if failed:
        print(
            "\nrefusing to write: a statement did not reconcile against its own\n"
            "preamble totals. Fix the export or the parser before importing.",
            file=log,
        )
        return 1

    # Normalize before pairing: a name can resolve to one of your own accounts,
    # which turns the row into a transfer that pairing then has to see.
    own_by_name = {name: iban for iban, name in own.items() if name != iban}
    unmatched_payees: dict[str, int] = defaultdict(int)
    used_patterns: set[str] = set()
    absorbed: dict[str, set[str]] = defaultdict(set)
    for row in converted:
        if row["opposing_iban"] in own:
            # Already an internal transfer; it is named after the account below.
            continue
        for pattern, canonical, raw, on_iban in payees:
            if not pattern.search(row["opposing_iban"] if on_iban else row["opposing_name"]):
                continue
            # A rule pointing at one of your own accounts cannot apply to a row
            # that already names a counterparty IBAN somewhere else: the payment
            # left the bank. Renaming it would also mint an expense account
            # sharing a name with an asset account. Fall through and report it.
            if canonical in own_names and row["opposing_iban"] not in own and row["opposing_iban"]:
                continue
            if True:
                if row["description"] == row["opposing_name"]:
                    row["description"] = canonical
                absorbed[raw].add(row["opposing_name"])
                row["opposing_name"] = canonical
                used_patterns.add(raw)
                # Mapping onto one of your own account names means the money
                # moved between your accounts. Incoming rows carry no IBAN, so
                # this is the only way to recover the far side — and supplying
                # the IBAN makes Firefly book a transfer instead of inventing a
                # revenue account that shares a name with an asset account.
                # Only claim this as an internal transfer when nothing already
                # says otherwise. A row carrying a counterparty IBAN that is not
                # yours is an external payment, whatever the holder is called —
                # "Manuel und Julia Werlberger" at another bank must not become
                # a transfer to JW just because a name rule matched.
                if canonical in own_names and not row["opposing_iban"]:
                    row["_own"] = canonical
                    row["opposing_iban"] = own_by_name.get(canonical, "")
                break
        else:
            if row["opposing_name"]:
                unmatched_payees[row["opposing_name"]] += 1

    kept, dropped, transfers = pair_transfers(converted, own)
    kept.sort(key=lambda r: (r["date"], r["external_id"]))

    with out_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(
            fh, fieldnames=OUT_FIELDS, delimiter=",", extrasaction="ignore"
        )
        writer.writeheader()
        writer.writerows(kept)

    config_path = out_path.with_suffix(".json")
    if not args.no_config:
        config_path.write_text(
            json.dumps(importer_config(args.default_account), indent=2) + "\n",
            encoding="utf-8",
        )

    # --- report ------------------------------------------------------------
    fx = sum(1 for r in kept if r["foreign_amount"])
    print(f"\nwrote {out_path}", file=log)
    if not args.no_config:
        print(f"      {config_path}", file=log)
    print(
        f"  {len(kept)} transactions"
        + (f", {duplicates} duplicate rows skipped" if duplicates else "")
        + f"\n  {fx} carry a foreign-currency amount",
        file=log,
    )

    if transfers:
        print(f"\n  {len(transfers)} internal transfer(s):", file=log)
        paired_ids = {d["external_id"] for d in dropped}
        for row in transfers:
            here = own.get(row["account_iban"], "?")
            there = own.get(row["opposing_iban"]) or row["_own"]
            out = row["amount"].startswith("-")
            print(
                f"    {(here if out else there):10s} -> {(there if out else here):10s} "
                f"{row['amount'].lstrip('-'):>9s} {row['date']}  "
                f"{row['description'][:32]}"
                f"{' (paired)' if row['external_id'] in paired_ids else ''}",
                file=log,
            )
        print(
            f"    {len(dropped)} counter-row(s) dropped; the other "
            f"{len(transfers) - len(dropped)} target accounts whose statements are\n"
            f"    not in this batch (their credit sides are rejected on external-id\n"
            f"    if imported later).",
            file=log,
        )

    # Credits with no debit to explain them. If one of these is really an
    # internal transfer, its sending statement was missing from the batch and
    # it will import as a deposit from a person-named revenue account.
    suspicious = [
        r
        for r in kept
        if not r["amount"].startswith("-")
        and not r["opposing_iban"]
        and r["opposing_name"] not in own_names
        and re.search(r"Gutschrift|UEBERTRAG|Übertrag", r["_kind"], re.I)
    ]
    if suspicious:
        print(
            f"\n  WARNING: {len(suspicious)} credit(s) with no counterparty IBAN and no\n"
            f"           matching debit in this batch. If any is an internal transfer,\n"
            f"           add that account's statement to the batch and re-run:",
            file=log,
        )
        for row in suspicious:
            print(
                f"    {own.get(row['account_iban'], '?'):10s} +{row['amount']:>9s} "
                f"{row['date']}  {row['opposing_name'][:34]}",
                file=log,
            )

    if payees:
        stale = [raw for *_, raw, _ in payees if raw not in used_patterns]
        print(
            f"\n  payees.tsv: {len(used_patterns)}/{len(payees)} patterns matched"
            + (f", unused: {', '.join(stale[:8])}" if stale else ""),
            file=log,
        )
    if args.explain_payees and absorbed:
        print("\n  what each payee pattern absorbed:", file=log)
        for raw, names in sorted(absorbed.items(), key=lambda kv: -len(kv[1])):
            print(f"    {raw}  ({len(names)})", file=log)
            for name in sorted(names):
                print(f"        {name}", file=log)

    if unmatched_payees:
        top = sorted(unmatched_payees.items(), key=lambda kv: -kv[1])[:15]
        print(
            f"  {len(unmatched_payees)} payee(s) matched no pattern; most frequent:",
            file=log,
        )
        for name, count in top:
            print(f"    {count:3d}  {name}", file=log)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
