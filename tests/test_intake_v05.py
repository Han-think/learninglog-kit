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
from learninglog.chunker import (
    remove_extra_hugo_front_matter,
    split_into_halves,
    merge_chunk_drafts,
)


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
    def test_removes_repeated_hugo_front_matter_blocks(self) -> None:
        raw = """---
title: "First"
date: 2026-06-01
draft: true
categories: ["learning"]
tags: []
description: "first"
---

Body 1

---

---
title: "Second"
date: 2026-06-01
draft: true
categories: ["learning"]
tags: []
description: "second"
---

Body 2
"""

        cleaned = remove_extra_hugo_front_matter(raw)

        self.assertIn('title: "First"', cleaned)
        self.assertNotIn('title: "Second"', cleaned)
        self.assertIn("Body 1", cleaned)
        self.assertIn("Body 2", cleaned)

    def test_strips_internal_meta_lines_from_body(self) -> None:
        raw = """---
title: "Keep me"
date: 2026-06-01
draft: false
---

본문 내용입니다.

---
source_id: SRC-20260530-001
note_date: 2026-05-30
model: huihui_ai/exaone3.5-abliterated:7.8b
mode: working_note
---
"""

        cleaned = remove_extra_hugo_front_matter(raw)

        # 맨 위 frontmatter와 본문은 보존
        self.assertIn('title: "Keep me"', cleaned)
        self.assertIn("본문 내용입니다.", cleaned)
        # 내부 메타는 전부 제거
        self.assertNotIn("source_id:", cleaned)
        self.assertNotIn("note_date:", cleaned)
        self.assertNotIn("model:", cleaned)
        self.assertNotIn("huihui", cleaned)
        self.assertNotIn("mode:", cleaned)

    def test_split_short_note_returns_single(self) -> None:
        self.assertEqual(len(split_into_halves("짧은 글", min_chars=1200)), 1)

    def test_split_long_note_two_no_loss(self) -> None:
        para = "가" * 800
        text = "\n\n".join([para] * 4)
        halves = split_into_halves(text)
        self.assertEqual(len(halves), 2)
        # 내용 손실 없음 (글자 수 보존)
        self.assertEqual((halves[0] + halves[1]).count("가"), text.count("가"))
        for h in halves:
            self.assertTrue(h.strip())

    def test_split_single_long_paragraph_falls_back(self) -> None:
        # 단락 경계가 없으면 강제로 자르지 않고 1편
        self.assertEqual(len(split_into_halves("가" * 5000)), 1)

    def test_split_explicit_afternoon_marker(self) -> None:
        text = "## 오전 공부\n" + ("내용 " * 200) + "\n\n## 오후 공부\n" + ("내용 " * 200)
        halves = split_into_halves(text)
        self.assertEqual(len(halves), 2)
        self.assertIn("오후", halves[1])

    def test_ollama_num_predict_config_and_clamp(self) -> None:
        from learninglog.adapters.ollama import OllamaAdapter
        # 설정값 반영 + num_ctx 기반 출력 토큰 예약으로 청크 크기 계산
        a = OllamaAdapter(num_ctx=8192, num_predict=2048)
        self.assertEqual(a.num_predict, 2048)
        self.assertGreater(a.safe_max_chars(), 1000)
        # num_predict 가 num_ctx 를 넘으면 안전하게 clamp
        b = OllamaAdapter(num_ctx=4096, num_predict=9999)
        self.assertLessEqual(b.num_predict, 4096 - 256)

    def test_merge_chunk_drafts_single_top_heading(self) -> None:
        p1 = '---\ntitle: "A"\ndraft: true\n---\n\n## 반복문 이해\n\n### 왜 썼나\n내용1'
        p2 = '---\ntitle: "B"\ndraft: true\n---\n\n## 반복문 또 다른 글\n\n### 배운 것\n내용2'
        p3 = "## 누적 변수\n\n### 정리\n내용3"
        merged = merge_chunk_drafts([p1, p2, p3])
        # 최상위 ## 는 정확히 1개 (### 는 제외하고 카운트)
        top = [ln for ln in merged.splitlines()
               if ln.lstrip().startswith("## ") and not ln.lstrip().startswith("### ")]
        self.assertEqual(len(top), 1)
        # 강등된 제목은 ### 로 남고 내용 보존
        self.assertIn("### 반복문 또 다른 글", merged)
        self.assertIn("### 누적 변수", merged)
        for c in ("내용1", "내용2", "내용3"):
            self.assertIn(c, merged)
        # 2번째 청크의 중복 front matter(title B)는 제거
        self.assertNotIn('title: "B"', merged)

    def test_merge_chunk_drafts_single_passthrough(self) -> None:
        one = "## 제목\n\n내용"
        self.assertEqual(merge_chunk_drafts([one]), one)

    def test_ollama_factory_reads_num_predict(self) -> None:
        from learninglog.adapters.factory import create_adapter
        cfg = {"llm": {"provider": "ollama",
                       "ollama": {"num_ctx": 8192, "num_predict": 2048}}}
        a = create_adapter(cfg)
        self.assertEqual(a.num_predict, 2048)
        self.assertEqual(a.num_ctx, 8192)

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
