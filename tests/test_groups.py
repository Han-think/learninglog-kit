from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from learninglog.groups import (
    parse_index_notes,
    find_index_files,
    assemble_group_body,
    build_group,
    pick_section,
    GroupNote,
)

PM_INDEX = """---
title: PM index
public_policy: internal-only
---

# 오후 Index

## included notes

1. `PN_2026-06-01_07_python_methods.md`
   - 메서드
   - public_policy: partial-public
   - target_section: learning

2. `PN_2026-06-01_08_python_function.md`
   - 함수
   - public_policy: partial-public
   - target_section: learning

3. `PN_2026-06-01_09_pandas_read_csv.md`
   - pandas
   - public_policy: partial-public

4. `PN_2026-06-01_10_distribution_thinking.md`
   - 배포 점검
   - public_policy: private

5. `CHECKPOINT_2026-06-01_PM.md`
   - 체크포인트

## processing guidance

- `07`, `08`, `09`는 블로그 후보. `10`은 공개 안 함.
"""

AM_INDEX = """# 오전 Index

## 생성된 personal notes

1. `PN_2026-06-01_01_github.md`
   - github
2. `PN_2026-06-01_02_colab.md`
   - colab
3. `PN_2026-06-01_03_for_loop.md`
4. `PN_2026-06-01_04_fstring.md`
5. `PN_2026-06-01_05_while.md`
6. `PN_2026-06-01_06_idea.md`

## 체크포인트
- [x] 완료
"""


class GroupParseTests(unittest.TestCase):
    def test_pm_excludes_private_and_checkpoint(self) -> None:
        notes = parse_index_notes(PM_INDEX)
        nums = [n.number for n in notes]
        self.assertEqual(nums, [7, 8, 9])  # 10(private), CHECKPOINT 제외
        for n in notes:
            self.assertEqual(n.public_policy, "partial-public")

    def test_section_terminates_at_next_h2(self) -> None:
        # '## processing guidance'의 07~10 본문 언급이 명단에 섞이면 안 됨
        notes = parse_index_notes(PM_INDEX)
        filenames = [n.filename for n in notes]
        self.assertTrue(all(f.endswith(".md") for f in filenames))
        self.assertEqual(len(notes), 3)

    def test_am_no_policy_defaults_partial_public(self) -> None:
        notes = parse_index_notes(AM_INDEX)
        self.assertEqual([n.number for n in notes], [1, 2, 3, 4, 5, 6])
        for n in notes:
            self.assertEqual(n.public_policy, "partial-public")

    def test_number_extraction_and_sort(self) -> None:
        scrambled = """## notes
`PN_2026-06-01_03_c.md`
`PN_2026-06-01_01_a.md`
`PN_2026-06-01_02_b.md`
"""
        notes = parse_index_notes(scrambled)
        self.assertEqual([n.number for n in notes], [1, 2, 3])

    def test_pick_section_majority_and_fallback(self) -> None:
        notes = [
            GroupNote(1, "a.md", target_section="learning"),
            GroupNote(2, "b.md", target_section="learning"),
            GroupNote(3, "c.md", target_section="projects"),
        ]
        self.assertEqual(pick_section(notes), "learning")
        tie = [
            GroupNote(1, "a.md", target_section="learning"),
            GroupNote(2, "b.md", target_section="projects"),
        ]
        self.assertEqual(pick_section(tie), "learning")  # 동률 → learning


class GroupFileTests(unittest.TestCase):
    def test_find_index_files_filters(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            nd = Path(td)
            (nd / "PN_2026-06-01_AM_INDEX.md").write_text("## notes\n", encoding="utf-8")
            (nd / "PN_2026-06-01_PM_INDEX.md").write_text("## notes\n", encoding="utf-8")
            (nd / "PN_2026-06-02_AM_INDEX.md").write_text("## notes\n", encoding="utf-8")
            (nd / "PN_2026-06-01_01_x.md").write_text("x", encoding="utf-8")  # 노트는 매칭 안 됨

            all_idx = find_index_files(nd)
            self.assertEqual(len(all_idx), 3)
            only_0601 = find_index_files(nd, date="2026-06-01")
            self.assertEqual(len(only_0601), 2)
            only_pm = find_index_files(nd, date="2026-06-01", period="PM")
            self.assertEqual(len(only_pm), 1)
            self.assertEqual(only_pm[0][1], "PM")

    def test_assemble_strips_front_matter_and_combines(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            nd = Path(td)
            idx = nd / "PN_2026-06-01_AM_INDEX.md"
            idx.write_text(
                "## notes\n`PN_2026-06-01_01_a.md`\n`PN_2026-06-01_02_b.md`\n",
                encoding="utf-8",
            )
            (nd / "PN_2026-06-01_01_a.md").write_text(
                '---\ntitle: "A"\n---\n\n첫 노트 본문', encoding="utf-8")
            (nd / "PN_2026-06-01_02_b.md").write_text(
                '---\ntitle: "B"\n---\n\n둘째 노트 본문', encoding="utf-8")

            group = build_group(idx)
            body, used = assemble_group_body(group, nd)
            self.assertEqual(len(used), 2)
            self.assertIn("첫 노트 본문", body)
            self.assertIn("둘째 노트 본문", body)
            self.assertNotIn("title:", body)   # frontmatter 제거
            self.assertNotIn("---", body)

    def test_assemble_skips_missing_files(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            nd = Path(td)
            idx = nd / "PN_2026-06-01_AM_INDEX.md"
            idx.write_text(
                "## notes\n`PN_2026-06-01_01_a.md`\n`PN_2026-06-01_99_missing.md`\n",
                encoding="utf-8",
            )
            (nd / "PN_2026-06-01_01_a.md").write_text("본문만", encoding="utf-8")
            group = build_group(idx)
            body, used = assemble_group_body(group, nd)
            self.assertEqual(used, ["PN_2026-06-01_01_a.md"])  # 없는 파일 안전 skip
            self.assertIn("본문만", body)


if __name__ == "__main__":
    unittest.main()
