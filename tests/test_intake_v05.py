from __future__ import annotations

import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from learninglog.init_project import REGISTRY_HEADER
from learninglog.intake import REGISTRY_FIELDS, run_intake


def _cfg(root: Path) -> dict:
    return {
        "project": {"language": "ko"},
        "paths": {
            "inbox": str(root / "00_inbox"),
            "registry": str(root / "01_registry" / "source_registry.csv"),
            "reports": str(root / "09_reports"),
        },
    }


def _init_minimal(root: Path) -> None:
    (root / "00_inbox" / "lectures").mkdir(parents=True)
    (root / "00_inbox" / "personal_notes").mkdir(parents=True)
    (root / "01_registry").mkdir()
    (root / "09_reports").mkdir()
    (root / "01_registry" / "source_registry.csv").write_text(REGISTRY_HEADER, encoding="utf-8")


class IntakeV05Tests(unittest.TestCase):
    def test_registers_pdf_ipynb_md_and_skips_duplicate_hash(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp_path = Path(td)
            _init_minimal(tmp_path)
            pdf = tmp_path / "00_inbox" / "lectures" / "[강의자료] loop.pdf"
            pdf.write_bytes(b"same pdf bytes")
            duplicate_pdf = tmp_path / "00_inbox" / "lectures" / "[수업자료] loop-copy.pdf"
            duplicate_pdf.write_bytes(b"same pdf bytes")
            note = tmp_path / "00_inbox" / "personal_notes" / "PN_2026-06-01_loop.md"
            note.write_text("# loop\n\nmy note", encoding="utf-8")
            notebook = tmp_path / "00_inbox" / "lectures" / "2_practice.ipynb"
            notebook.write_text(
                json.dumps(
                    {
                        "cells": [
                            {"cell_type": "markdown", "source": ["# Loop Practice\n"]},
                            {"cell_type": "code", "source": ["for x in [1, 2]:\n    print(x)\n"]},
                        ]
                    }
                ),
                encoding="utf-8",
            )

            run_intake(_cfg(tmp_path))

            with open(tmp_path / "01_registry" / "source_registry.csv", encoding="utf-8") as f:
                rows = list(csv.DictReader(f))

            self.assertEqual(list(rows[0].keys()), REGISTRY_FIELDS)
            self.assertEqual(len(rows), 3)
            by_name = {r["file_name"]: r for r in rows}
            self.assertEqual(by_name["[강의자료] loop.pdf"]["source_category"], "lecture_pdf")
            self.assertEqual(by_name["[강의자료] loop.pdf"]["public_policy"], "internal-only")
            self.assertEqual(by_name["PN_2026-06-01_loop.md"]["public_policy"], "partial-public")
            self.assertEqual(by_name["2_practice.ipynb"]["source_category"], "practice_notebook")
            self.assertEqual(by_name["2_practice.ipynb"]["public_policy"], "private")
            self.assertIn("code_cells=1", by_name["2_practice.ipynb"]["notes"])

            reports = list((tmp_path / "09_reports").glob("RUN_*_intake_report.md"))
            self.assertEqual(len(reports), 1)
            report = reports[0].read_text(encoding="utf-8")
            self.assertIn("Duplicate files skipped: 1", report)

    def test_upgrades_legacy_registry_with_backup(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp_path = Path(td)
            _init_minimal(tmp_path)
            legacy = (
                "source_id,source_path,source_type,date_added,status,topic,language,public_policy,notes\n"
                "SRC-20260531-001,00_inbox/personal_notes/old.md,personal_note,2026-05-31,registered,old,ko,partial-public,legacy\n"
            )
            (tmp_path / "01_registry" / "source_registry.csv").write_text(legacy, encoding="utf-8")
            (tmp_path / "00_inbox" / "personal_notes" / "old.md").write_text("old", encoding="utf-8")

            run_intake(_cfg(tmp_path))

            with open(tmp_path / "01_registry" / "source_registry.csv", encoding="utf-8") as f:
                rows = list(csv.DictReader(f))

            self.assertEqual(list(rows[0].keys()), REGISTRY_FIELDS)
            self.assertEqual(rows[0]["source_category"], "personal_note")
            backups = list((tmp_path / "07_archive" / "backups").glob("source_registry_pre_v0_5_*.csv"))
            self.assertEqual(len(backups), 1)


if __name__ == "__main__":
    unittest.main()
