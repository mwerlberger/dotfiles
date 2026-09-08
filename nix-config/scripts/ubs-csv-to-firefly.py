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
import hashlib
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
    # Fallback for accounts with no IBAN (a Wise currency balance, say). The
    # importer prefers the IBAN when both are present.
    "account_name": "account-name",
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
    # Only the credit-card export supplies this (its `Branche` column). Bank
    # rows leave it empty and are categorised by the Firefly rules instead.
    "category": "category-name",
}
OUT_FIELDS = list(FIELD_ROLES)

DEFAULT_ACCOUNTS_TSV = Path.home() / ".config/firefly/accounts.tsv"
DEFAULT_PAYEES_TSV = Path.home() / ".config/firefly/payees.tsv"
DEFAULT_BRANCHEN_TSV = Path.home() / ".config/firefly/branchen.tsv"


def is_zero(amount: str) -> bool:
    """Firefly rejects a zero amount ("Der Wert muss grösser als Null sein").

    UBS emits them: a "Saldo Dienstleistungspreisabschluss" row for a month with
    no fee is a statement line, not a transaction. Emitting them turns a clean
    import into a non-zero exit and hides real failures.
    """
    try:
        return abs(float(amount)) < 0.005
    except ValueError:
        return False


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

    def convert(self) -> list[dict[str, str]]:
        rows = (convert_row(r, self.own_iban, self.details) for r in self.rows)
        return [r for r in rows if r is not None]

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


CARD_HEADER_STARTS = "Kontonummer;Kartennummer"
CARD_TOTALS = "Total Kartenbuchungen"
# Buchungstext is fixed-width for card purchases — merchant 0..24, town 25..37,
# ISO country 38..40:
#   "SITIBONDO S.A.S.         LAIGUEGLIA   ITA"
# Splitting on runs of spaces looks tempting and is wrong: "LEDER  SCHUH AG" and
# "UBER   *EATS" contain their own runs. Account-level rows ("2002 LSV-ZAHLUNG",
# "1.75% ZUSCHLAG CHF IM AUSLAND") are short and have no country, so the country
# code is what tells the two layouts apart.
CARD_MERCHANT_END = 25
CARD_COUNTRY = slice(38, 41)


def card_payee(text: str | None) -> str:
    """Merchant name out of a fixed-width Buchungstext."""
    padded = (text or "").replace("\n", " ")
    country = padded[CARD_COUNTRY].strip()
    if len(padded) >= 41 and len(country) == 3 and country.isalpha():
        return clean(padded[:CARD_MERCHANT_END])
    return clean(padded)


def iso_date(value: str) -> str:
    """DD.MM.YYYY -> YYYY-MM-DD. The card export uses the Swiss format."""
    value = clean(value)
    m = re.match(r"^(\d{2})\.(\d{2})\.(\d{4})$", value)
    return f"{m.group(3)}-{m.group(2)}-{m.group(1)}" if m else value


class CardStatement:
    """A UBS credit-card export.

    Shares no columns with the bank export and, awkwardly, carries no
    transaction number — see synthetic_id() — so it gets its own reader that
    emits the same OUT_FIELDS as the bank one. Everything downstream (payee
    normalisation, pairing, the sidecar, the report) then works unchanged.
    """

    def __init__(self, path: Path, cards: dict[str, str], branchen: dict[str, str]):
        # ISO-8859-1, and the first line is a spreadsheet hint ("sep=;").
        lines = path.read_text(encoding="latin-1", newline="").splitlines(keepends=True)
        header = next(
            (i for i, l in enumerate(lines) if l.startswith(CARD_HEADER_STARTS)), None
        )
        if header is None:
            raise SystemExit(f"{path}: no '{CARD_HEADER_STARTS}' header row found.")

        self.path = path
        self.branchen = branchen
        reader = csv.DictReader(io.StringIO("".join(lines[header:])), delimiter=";")
        all_rows = list(reader)
        self.rows = [r for r in all_rows if clean(r.get("Einkaufsdatum"))]

        # The trailing "Total Kartenbuchungen" line is this format's equivalent
        # of Anfangssaldo/Schlusssaldo: the only way to prove nothing was lost.
        self.totals: tuple[str, str] | None = None
        for r in all_rows:
            if CARD_TOTALS in " ".join(clean(v) for v in r.values() if v):
                self.totals = (clean(r.get("Belastung")), clean(r.get("Gutschrift")))

        account = re.sub(r"\s+", "", clean(self.rows[0]["Kontonummer"])).casefold() if self.rows else ""
        record = cards.get(account)
        self.own_iban = record["iban"] if record else ""
        self.own_name = record["name"] if record else ""
        if not record:
            raise SystemExit(
                f"{path}: card account '{clean(self.rows[0]['Kontonummer']) if self.rows else '?'}'\n"
                f"       is not in the 4th column of accounts.tsv. Without it every row\n"
                f"       would fall back to default_account and land in the wrong\n"
                f"       account — refusing to convert."
            )

        dates = sorted(iso_date(r.get("Einkaufsdatum")) for r in self.rows)
        # Same shape as the bank reader's preamble facts, so the report and the
        # opening-balance logic do not need to know which format they are on.
        self.facts = {
            "von": dates[0] if dates else "",
            "bis": dates[-1] if dates else "",
            "opening": "", "closing": "", "count": "",
        }

        # Settlements: the card being paid off. The bank statement already books
        # these as a transfer INTO the card account, so importing them again
        # credits the card twice. They have no Kartennummer because they belong
        # to the account, not to a card.
        self.settlements = [
            r
            for r in self.rows
            if not clean(r.get("Kartennummer")) and clean(r.get("Gutschrift"))
        ]

    def check(self) -> list[str]:
        problems = []
        if self.totals:
            for label, idx, col in (("debit", 0, "Belastung"), ("credit", 1, "Gutschrift")):
                stated = self.totals[idx]
                if not stated:
                    continue
                got = sum(float(number(clean(r[col]))) for r in self.rows if clean(r[col]))
                if abs(got - float(number(stated))) > 0.005:
                    problems.append(
                        f"{label} total mismatch: rows add to {got:.2f}, but "
                        f"'{CARD_TOTALS}' says {number(stated)}"
                    )
        return problems

    def synthetic_id(self, row: dict[str, str], seen: dict[str, int]) -> str:
        """A stable id for a file that ships none.

        Firefly de-duplicates on external-id, so without this a re-import would
        double every charge. Hashing the row's own values keeps it deterministic
        across exports; the occurrence counter keeps two identical charges on one
        day distinct.
        """
        key = "|".join(
            clean(row.get(f))
            for f in (
                "Kontonummer", "Kartennummer", "Einkaufsdatum", "Buchung",
                "Buchungstext", "Betrag", "Originalwährung", "Belastung", "Gutschrift",
            )
        )
        seen[key] = seen.get(key, 0) + 1
        digest = hashlib.sha1(f"{key}#{seen[key]}".encode()).hexdigest()[:20]
        return f"ubscc-{digest}"

    def convert(self) -> list[dict[str, str]]:
        out, seen = [], {}
        for row in self.rows:
            if row in self.settlements:
                continue
            debit, credit = number(clean(row.get("Belastung"))), number(clean(row.get("Gutschrift")))
            if not (debit or credit):
                continue
            amount = f"-{debit}" if debit else credit
            if is_zero(amount):
                continue

            payee = card_payee(row.get("Buchungstext"))
            raw_payee = clean(row.get("Buchungstext"))

            foreign_amount = foreign_currency = ""
            original, currency = clean(row.get("Originalwährung")), clean(row.get("Währung"))
            if original and currency and original != currency:
                foreign_amount = number(clean(row.get("Betrag")))
                if amount.startswith("-") and not foreign_amount.startswith("-"):
                    foreign_amount = f"-{foreign_amount}"
                foreign_currency = original

            branche = clean(row.get("Branche"))
            notes = " | ".join(
                p for p in (
                    raw_payee,
                    f"Branche: {branche}" if branche else "",
                    f"Kurs: {clean(row.get('Kurs'))}" if clean(row.get("Kurs")) else "",
                    f"Karte: {clean(row.get('Kartennummer'))}" if clean(row.get("Kartennummer")) else "",
                ) if p
            )
            out.append({
                "account_iban": self.own_iban,
                "account_name": self.own_name,
                "date": iso_date(row.get("Einkaufsdatum")),
                "book_date": iso_date(row.get("Buchung")),
                "process_date": "",
                "amount": amount,
                "currency": currency or "CHF",
                "foreign_amount": foreign_amount,
                "foreign_currency": foreign_currency,
                "external_id": self.synthetic_id(row, seen),
                "opposing_name": payee,
                "opposing_iban": "",
                "description": payee,
                "category": self.branchen.get(branche.casefold(), ""),
                "notes": notes,
                "_reason": "",
                "_kind": branche,
                "_own": "",
                "_branche": branche,
            })
        return out


SWISSCARD_HEADER = "Transaction date,Description,Merchant"
WISE_HEADER = "ID,Status,Richtung"


class SwisscardStatement:
    """A Swisscard credit-card export.

    The tidiest of the three: `Merchant` is already a clean name and
    `Merchant Category` a usable category, so almost nothing has to be salvaged
    from free text. `Amount` is signed — debits positive, credits negative — so
    `Debit/Credit` only confirms what the sign already says.
    """

    def __init__(self, path: Path, cards: dict[str, dict[str, str]], branchen: dict[str, str]):
        with path.open(encoding="utf-8-sig", newline="") as fh:
            self.rows = [r for r in csv.DictReader(fh) if clean(r.get("Transaction date"))]
        self.path = path

        card = re.sub(r"\s+", "", clean(self.rows[0]["Card number"])).casefold() if self.rows else ""
        record = cards.get(card)
        if not record:
            raise SystemExit(
                f"{path}: card '{clean(self.rows[0]['Card number']) if self.rows else '?'}' is not\n"
                f"       in the 4th column of accounts.tsv — refusing to guess which account\n"
                f"       this statement belongs to."
            )
        self.own_iban, self.own_name = record["iban"], record["name"]
        self.branchen = branchen

        # Paying the card off. The bank statement books these as a transfer into
        # the card, so importing them again credits the card twice. A refund is
        # also a credit, so the sign alone is not enough to tell them apart —
        # a settlement has no merchant and is categorised "Payment".
        self.settlements = [
            r
            for r in self.rows
            if not clean(r.get("Merchant")) and clean(r.get("Merchant Category")) == "Payment"
        ]
        dates = sorted(iso_date(r.get("Transaction date")) for r in self.rows)
        self.facts = {"von": dates[0] if dates else "", "bis": dates[-1] if dates else "",
                      "opening": "", "closing": "", "count": ""}

    def check(self) -> list[str]:
        return []

    def convert(self) -> list[dict[str, str]]:
        out, seen = [], {}
        for row in self.rows:
            if row in self.settlements:
                continue
            signed = number(clean(row.get("Amount")))
            if not signed or is_zero(signed):
                continue
            # A debit is money out, so Firefly's sign is the opposite of theirs.
            amount = signed[1:] if signed.startswith("-") else f"-{signed}"

            foreign_amount = foreign_currency = ""
            fc, fa = clean(row.get("Foreign Currency")), number(clean(row.get("Amount in foreign currency")))
            if fc and fa:
                foreign_currency = fc
                foreign_amount = f"-{fa}" if amount.startswith("-") else fa

            payee = clean(row.get("Merchant")) or clean(row.get("Description"))
            category = clean(row.get("Merchant Category"))
            key = "|".join(clean(row.get(f)) for f in (
                "Transaction date", "Description", "Card number", "Amount",
                "Foreign Currency", "Amount in foreign currency"))
            seen[key] = seen.get(key, 0) + 1
            out.append({
                "account_iban": self.own_iban,
                "account_name": self.own_name,
                "date": iso_date(row.get("Transaction date")),
                "book_date": "",
                "process_date": "",
                "amount": amount,
                "currency": clean(row.get("Currency")) or "CHF",
                "foreign_amount": foreign_amount,
                "foreign_currency": foreign_currency,
                "external_id": "swc-" + hashlib.sha1(f"{key}#{seen[key]}".encode()).hexdigest()[:20],
                "opposing_name": payee,
                "opposing_iban": "",
                "description": payee,
                "category": self.branchen.get(category.casefold(), ""),
                "notes": " | ".join(p for p in (
                    clean(row.get("Description")),
                    f"Kategorie: {category}" if category else "",
                    clean(row.get("Registered Category")),
                ) if p),
                "_reason": "", "_kind": category, "_own": "", "_branche": category,
            })
        return out


class WiseStatement:
    """A Wise export.

    Two things make it unlike the card exports. It has a real unique `ID`, so no
    hash is needed. And Wise holds a balance per currency: `Ausgangswährung`
    says which one a payment came out of, so one file feeds several Firefly
    accounts, matched through `wise:<CUR>` keys in accounts.tsv.

    Fees sit in their own column and are NOT included in
    `Ausgangsbetrag (nach Gebühren)` — that figure is exactly
    `Zielbetrag / Wechselkurs`. The amount that actually left the balance is the
    two added together.
    """

    def __init__(self, path: Path, cards: dict[str, dict[str, str]], branchen: dict[str, str]):
        with path.open(encoding="utf-8-sig", newline="") as fh:
            self.rows = [r for r in csv.DictReader(fh) if clean(r.get("ID"))]
        self.path = path
        self.cards = cards
        self.branchen = branchen

        currencies = {clean(r.get("Ausgangswährung")).upper() for r in self.rows}
        missing = [c for c in sorted(currencies) if c and f"wise:{c}".casefold() not in cards]
        if missing:
            raise SystemExit(
                f"{path}: no account for Wise balance(s) {', '.join(missing)}.\n"
                f"       Add a row to accounts.tsv whose 4th column is 'wise:{missing[0]}'\n"
                f"       and whose 5th is the currency."
            )

        # Topping the balance up from a bank account: the bank side books it.
        self.settlements = [r for r in self.rows if clean(r.get("Richtung")).upper() == "IN"]
        dates = sorted(clean(r.get("Abgeschlossen am"))[:10] for r in self.rows)
        self.facts = {"von": dates[0] if dates else "", "bis": dates[-1] if dates else "",
                      "opening": "", "closing": "", "count": ""}
        self.own_iban = ""
        self.own_name = "Wise"

    def check(self) -> list[str]:
        return []

    def convert(self) -> list[dict[str, str]]:
        out = []
        for row in self.rows:
            if row in self.settlements:
                continue
            source = clean(row.get("Ausgangswährung")).upper()
            account = self.cards[f"wise:{source}".casefold()]
            amount_src = number(clean(row.get("Ausgangsbetrag (nach Gebühren)")))
            fee = number(clean(row.get("Betrag der Ausgangsgebühr")))
            # The fee is only part of this amount when it was taken in the same
            # currency the money left in.
            if fee and clean(row.get("Währung der Ausgangsgebühr")).upper() == source:
                amount_src = f"{float(amount_src) + float(fee):.2f}"
            if is_zero(amount_src):
                continue

            target_cur = clean(row.get("Zielwährung")).upper()
            target_amt = number(clean(row.get("Zielbetrag (nach Gebühren)")))
            payee = clean(row.get("Name des Empfängers"))
            neutral = clean(row.get("Richtung")).upper() == "NEUTRAL"

            row_out = {
                "account_iban": account["iban"],
                "account_name": account["name"],
                "date": clean(row.get("Abgeschlossen am"))[:10]
                or clean(row.get("Erstellt am"))[:10],
                "book_date": "",
                "process_date": "",
                "amount": f"-{amount_src}",
                "currency": source or "CHF",
                "foreign_amount": f"-{target_amt}" if target_cur != source and target_amt else "",
                "foreign_currency": target_cur if target_cur != source else "",
                "external_id": clean(row.get("ID")),
                "opposing_name": payee,
                "opposing_iban": "",
                "description": payee,
                "category": self.branchen.get(clean(row.get("Kategorie")).casefold(), ""),
                "notes": " | ".join(p for p in (
                    f"Wise {clean(row.get('Richtung'))} {clean(row.get('Status'))}",
                    f"Kategorie: {clean(row.get('Kategorie'))}" if clean(row.get("Kategorie")) else "",
                    f"Kurs: {clean(row.get('Wechselkurs'))}" if clean(row.get("Wechselkurs")) else "",
                    f"Gebühr: {fee} {clean(row.get('Währung der Ausgangsgebühr'))}" if fee else "",
                ) if p),
                "_reason": "", "_kind": clean(row.get("Kategorie")), "_own": "",
                "_branche": clean(row.get("Kategorie")),
            }
            if neutral:
                # Moving your own money between Wise balances: a transfer, and
                # the far side is the account for the target currency.
                target = self.cards.get(f"wise:{target_cur}".casefold())
                if target:
                    row_out["opposing_name"] = target["name"]
                    row_out["opposing_iban"] = target["iban"]
                    row_out["_own"] = target["name"]
                    row_out["description"] = f"Wise {source} to {target_cur}"
                    row_out["category"] = ""
            out.append(row_out)
        return out


def read_statement(path: Path, cards: dict[str, dict[str, str]], branchen: dict[str, str]):
    """Bank export or credit-card export? They share nothing but a `.csv`."""
    head = path.read_bytes()[:400].decode("latin-1", "replace").lstrip("\ufeff")
    if head.startswith("sep=") or CARD_HEADER_STARTS in head:
        return CardStatement(path, cards, branchen)
    if head.startswith(SWISSCARD_HEADER):
        return SwisscardStatement(path, cards, branchen)
    if head.startswith(WISE_HEADER):
        return WiseStatement(path, cards, branchen)
    return Statement(path)


def load_branchen(path: Path | None) -> dict[str, str]:
    """UBS merchant category -> your Firefly category.

    Card payee strings are close to useless ("PAYPAL *SONOFATAILO  71994155"),
    but the Branche column is clean. Rules still run afterwards and win when a
    payee matches, so this only fills the gap.
    """
    if not path or not path.is_file():
        return {}
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 2 and parts[0].strip() and parts[1].strip():
            out[parts[0].strip().casefold()] = parts[1].strip()
    return out


def load_accounts(path: Path | None) -> list[dict[str, str]]:
    """accounts.tsv as records.

        name <TAB> role <TAB> IBAN [<TAB> source key [<TAB> currency]]

    The source key is how a statement that names no IBAN finds its account: a
    credit card's own account or card number, or a token like `wise:EUR` for an
    export that identifies nothing at all.
    """
    if not path or not path.is_file():
        return []
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = (line.split("\t") + ["", "", "", ""])[:5]
        if not parts[0].strip():
            continue
        out.append({
            "name": parts[0].strip(),
            "role": parts[1].strip(),
            "iban": norm_iban(parts[2]),
            "key": re.sub(r"\s+", "", parts[3]).casefold(),
            "currency": parts[4].strip().upper() or "CHF",
        })
    return out


def load_cards(path: Path | None) -> dict[str, dict[str, str]]:
    """Source key -> the account record it names."""
    return {a["key"]: a for a in load_accounts(path) if a["key"]}


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


def load_payees(path: Path | None) -> list[tuple[re.Pattern[str], str, str, str]]:
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

    A fourth form, `kind:Bancomat`, matches the transaction KIND (Beschreibung2)
    instead of the payee — see below.

    Returns (pattern, canonical name, original pattern text, what it matches on:
    "iban" | "kind" | "name"). IBAN and kind patterns are evaluated first.
    """
    if not path or not path.is_file():
        return []
    names, ibans, kinds = [], [], []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        pattern, canonical = parts[0].strip(), parts[1].strip()
        if pattern.startswith("iban:"):
            iban = norm_iban(pattern[5:])
            ibans.append((re.compile(f"^{re.escape(iban)}$"), canonical, pattern, "iban"))
        elif pattern.startswith("kind:"):
            # Matches UBS's Beschreibung2 ("Bezug UBS Bancomat"), not the payee.
            # Cash withdrawals need this: the payee is whichever machine you
            # used, so a name rule breaks at the next unfamiliar one.
            kinds.append(
                (re.compile(re.escape(pattern[5:].strip()), re.I), canonical, pattern, "kind")
            )
        elif pattern.startswith("re:"):
            names.append((re.compile(pattern[3:], re.I), canonical, pattern, "name"))
        else:
            names.append((re.compile(re.escape(pattern), re.I), canonical, pattern, "name"))
    return ibans + kinds + names


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
    if is_zero(amount):
        return None

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
        "account_name": "",
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
        "category": "",
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
        if (row["opposing_iban"] and row["opposing_iban"] in own) or row["_own"]:
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
        "--branchen",
        type=Path,
        default=DEFAULT_BRANCHEN_TSV,
        help=f"credit-card merchant-category map (default: {DEFAULT_BRANCHEN_TSV})",
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

    cards = load_cards(args.own_ibans)
    accounts = load_accounts(args.own_ibans)
    branchen = load_branchen(args.branchen)
    statements = [read_statement(p, cards, branchen) for p in args.inputs]
    own, own_names = load_own_ibans(args.own_ibans)
    # An empty own_iban must never enter this map: a statement that spans several
    # accounts (Wise) has none, and "" would then match every row whose
    # counterparty IBAN is blank — which is most of them.
    own.update({
        s.own_iban: s.own_iban
        for s in statements
        if s.own_iban and s.own_iban not in own
    })
    payees = load_payees(args.payees)

    log = sys.stderr
    failed = False
    converted: list[dict[str, str]] = []
    seen: set[str] = set()
    duplicates = 0
    for st in statements:
        problems = st.check()
        label = own.get(st.own_iban) or getattr(st, "own_name", "") or st.own_iban
        period = f"{st.facts['von']}..{st.facts['bis']}"
        print(f"  {st.path.name}: {len(st.rows)} rows  {label}  {period}", file=log)
        for problem in problems:
            print(f"    ERROR: {problem}", file=log)
            failed = True

        for out in st.convert():
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
        if row["opposing_iban"] and row["opposing_iban"] in own:
            # Already an internal transfer; it is named after the account below.
            continue
        for pattern, canonical, raw, against in payees:
            field = {"iban": "opposing_iban", "kind": "_kind"}.get(against, "opposing_name")
            if not pattern.search(row[field]):
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

    # Every card reader exposes .settlements; report them all, not just one
    # vendor's, or a missing bank statement stays invisible.
    dropped_settlements = [
        (st, r) for st in statements for r in getattr(st, "settlements", [])
    ]
    if dropped_settlements:
        def settled(row):
            for field in ("Gutschrift", "Amount", "Ausgangsbetrag (nach Gebühren)"):
                if clean(row.get(field)):
                    return abs(float(number(clean(row[field]))))
            return 0.0

        def settled_label(row):
            for field in ("Buchungstext", "Description", "Name des Empfängers"):
                if clean(row.get(field)):
                    return clean(row[field])
            return "?"

        def settled_date(row):
            for field in ("Einkaufsdatum", "Transaction date"):
                if clean(row.get(field)):
                    return iso_date(row[field])
            return clean(row.get("Abgeschlossen am"))[:10]

        total = sum(settled(r) for _, r in dropped_settlements)
        print(
            f"\n  {len(dropped_settlements)} card settlement(s) dropped, CHF {total:.2f} — "
            f"the bank statement\n    already books these as a transfer into the card "
            f"account. If a period's bank\n    statement is missing from this batch, its "
            f"payment is missing too:",
            file=log,
        )
        for st, r in dropped_settlements:
            label = own.get(st.own_iban) or getattr(st, "own_name", "?")
            print(
                f"    {label:16s} +{settled(r):>9.2f} {settled_date(r)}  {settled_label(r)[:44]}",
                file=log,
            )

    # Unmapped Branche values: the card's only good categorisation signal.
    unmapped = defaultdict(int)
    for st in statements:
        if isinstance(st, CardStatement):
            for row in st.convert():
                if row["_branche"] and not row["category"]:
                    unmapped[row["_branche"]] += 1
    if unmapped:
        print(f"\n  {len(unmapped)} Branche value(s) not in branchen.tsv:", file=log)
        for name, count in sorted(unmapped.items(), key=lambda kv: -kv[1]):
            print(f"    {count:3d}  {name}", file=log)

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
