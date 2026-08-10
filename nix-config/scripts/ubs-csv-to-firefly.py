#!/usr/bin/env python3
"""Convert a UBS Switzerland e-banking CSV export into a CSV the Firefly III
data importer can map 1:1.

Why this exists: the raw UBS export is not directly importable.
  * 9 preamble lines (Kontonummer, IBAN, Von/Bis, Saldi) sit above the header.
  * The counterparty IBAN is buried in free text inside `Beschreibung3`
    ("Konto-Nr. IBAN: CH.."), not in its own column. Without extracting it,
    transfers between your own accounts import as unrelated withdrawal +
    deposit pairs instead of collapsing into a single transfer.
  * The counterparty name is the first `;`-separated subfield of a quoted
    `Beschreibung1` that also holds the street address.
  * Debit and credit are separate columns.

MT940 was evaluated as an alternative and rejected: it carries no counterparty
IBANs at all and truncates merchant names to ~22 characters.

Usage:
    ubs-csv-to-firefly.py INPUT.csv [INPUT2.csv ...] [-o OUTFILE]

Writes one combined CSV (default: alongside the first input, `*-firefly.csv`).
Output columns are stable, so the mapping saved in the importer keeps working:

    date, value_date, amount, currency, external_id,
    opposing_name, opposing_iban, description, notes
"""

from __future__ import annotations

import argparse
import csv
import io
import re
import sys
from pathlib import Path

HEADER_STARTS = "Abschlussdatum"
IBAN_RE = re.compile(r"Konto-Nr\.\s*IBAN:\s*([A-Z]{2}[0-9A-Z ]{13,32}?)\s*(?:;|$)")
OUT_FIELDS = [
    "date",
    "value_date",
    "amount",
    "currency",
    "external_id",
    "opposing_name",
    "opposing_iban",
    "description",
    "notes",
]


def clean(value: str | None) -> str:
    """Collapse the whitespace UBS sprinkles around subfields."""
    return re.sub(r"\s+", " ", (value or "").replace("\n", " ")).strip()


def subfields(value: str | None) -> list[str]:
    """UBS packs several values into one quoted field, separated by ';'."""
    return [clean(p) for p in (value or "").split(";") if clean(p)]


def read_ubs(path: Path) -> list[dict[str, str]]:
    # utf-8-sig: the export carries a BOM.
    text = path.read_text(encoding="utf-8-sig", newline="")
    lines = text.splitlines(keepends=True)
    header = next(
        (i for i, line in enumerate(lines) if line.startswith(HEADER_STARTS)), None
    )
    if header is None:
        raise SystemExit(f"{path}: no '{HEADER_STARTS}' header row found — not a UBS export?")
    reader = csv.DictReader(io.StringIO("".join(lines[header:])), delimiter=";")
    # Trailing summary/blank lines have no booking date.
    return [row for row in reader if clean(row.get("Buchungsdatum"))]


def convert_row(row: dict[str, str]) -> dict[str, str] | None:
    debit = clean(row.get("Belastung"))
    credit = clean(row.get("Gutschrift"))
    amount = debit or credit
    if not amount:
        return None
    # UBS already signs debits negative; be defensive in case a variant does not.
    if debit and not debit.startswith("-"):
        amount = f"-{debit}"

    parts = subfields(row.get("Beschreibung1"))
    opposing_name = parts[0] if parts else ""

    desc3 = clean(row.get("Beschreibung3"))
    match = IBAN_RE.search(desc3)
    opposing_iban = match.group(1).replace(" ", "").upper() if match else ""

    type_parts = subfields(row.get("Beschreibung2"))
    # For card payments Beschreibung2 leads with the card number; the useful
    # label ("Zahlung Debitkarte") is last.
    kind = type_parts[-1] if type_parts else ""

    description = opposing_name or kind or "UBS transaction"
    notes = " | ".join(p for p in (clean(row.get("Beschreibung2")), desc3) if p)

    return {
        "date": clean(row.get("Buchungsdatum")),
        "value_date": clean(row.get("Valutadatum")),
        "amount": amount,
        "currency": clean(row.get("Währung")) or "CHF",
        "external_id": clean(row.get("Transaktions-Nr.")),
        "opposing_name": opposing_name,
        "opposing_iban": opposing_iban,
        "description": description,
        "notes": notes,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", type=Path)
    ap.add_argument("-o", "--output", type=Path)
    args = ap.parse_args()

    out_path = args.output or args.inputs[0].with_name(
        args.inputs[0].stem + "-firefly.csv"
    )

    converted: list[dict[str, str]] = []
    seen: set[str] = set()
    duplicates = 0
    for path in args.inputs:
        rows = read_ubs(path)
        kept = 0
        for row in rows:
            out = convert_row(row)
            if out is None:
                continue
            # Transaktions-Nr. is unique per transaction; guard against the same
            # statement being passed twice (overlapping export ranges).
            key = out["external_id"]
            if key and key in seen:
                duplicates += 1
                continue
            seen.add(key)
            converted.append(out)
            kept += 1
        print(f"  {path.name}: {kept} transactions", file=sys.stderr)

    converted.sort(key=lambda r: (r["date"], r["external_id"]))

    with out_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=OUT_FIELDS, delimiter=",")
        writer.writeheader()
        writer.writerows(converted)

    with_iban = sum(1 for r in converted if r["opposing_iban"])
    missing_id = sum(1 for r in converted if not r["external_id"])
    print(
        f"\nwrote {out_path}\n"
        f"  {len(converted)} transactions"
        + (f", {duplicates} duplicate ids skipped" if duplicates else "")
        + f"\n  {with_iban} carry a counterparty IBAN (these can become transfers)",
        file=sys.stderr,
    )
    if missing_id:
        print(
            f"  WARNING: {missing_id} rows have no Transaktions-Nr.; duplicate\n"
            f"           detection on external_id will not protect those.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
