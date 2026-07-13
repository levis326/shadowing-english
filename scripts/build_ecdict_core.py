#!/usr/bin/env python3
"""Build a small, high-frequency ECDICT asset for offline word lookup."""

import csv
import json
import re
import sys
from pathlib import Path

LIMIT = 80000
WORD = re.compile(r"^[A-Za-z]+(?:['-][A-Za-z]+)?$")


def rank(row: dict[str, str]) -> int:
    values = []
    for key in ("frq", "bnc"):
        try:
            value = int(row.get(key, "0"))
            if value > 0:
                values.append(value)
        except ValueError:
            pass
    return min(values) if values else 10**9


def main(source: Path, destination: Path) -> None:
    with source.open(encoding="utf-8", newline="") as handle:
        rows = [
            row
            for row in csv.DictReader(handle)
            if WORD.fullmatch(row.get("word", ""))
            and row.get("translation", "").strip()
            and rank(row) < 10**9
        ]
    rows.sort(key=rank)
    entries: dict[str, list[str]] = {}
    for row in rows:
        if len(entries) >= LIMIT:
            break
        word = row["word"].lower()
        entries.setdefault(
            word,
            [
                row["translation"].strip(),
                row.get("phonetic", "").strip(),
                row.get("pos", "").strip(),
            ],
        )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps({"version": 1, "entries": entries}, ensure_ascii=False),
        encoding="utf-8",
    )
    print(f"wrote {len(entries)} entries to {destination}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
