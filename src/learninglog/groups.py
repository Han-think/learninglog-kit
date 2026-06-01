"""groups — 오전/오후 INDEX 기준으로 여러 노트를 묶어 통합 글 1편 만들기.

LearningLog 워크플로우:
  personal_notes/ 에 하루 노트가 주제별로 나뉘어 있고
  PN_{date}_AM_INDEX.md / _PM_INDEX.md 가 그 그룹의 명단을 제공한다.

이 모듈은 INDEX 를 파싱해 "공개 가능한 노트만" 번호순으로 모아 하나의
본문으로 합친다 (LLM 호출 없음 — 순수 텍스트 처리).

공개 금지 규칙:
  - CHECKPOINT_*.md  : 파일명 prefix 로 무조건 제외
  - public_policy private / internal-only : 제외
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from .chunker import _strip_leading_front_matter

# 명단 섹션 헤더 (AM/PM INDEX 가 서로 다른 헤더를 씀)
_NOTE_SECTION_RE = re.compile(
    r"^##\s+(included notes|생성된 personal notes|notes|노트\s*목록)\b", re.IGNORECASE
)
_ANY_H2_RE = re.compile(r"^##\s+\S")
_NOTE_LINE_RE = re.compile(r"`([^`]+\.md)`")
_POLICY_RE = re.compile(r"public_policy\s*[:=]\s*([a-z\-]+)", re.IGNORECASE)
_SECTION_RE = re.compile(r"target_section\s*[:=]\s*([a-z]+)", re.IGNORECASE)
_NUM_RE = re.compile(r"^PN_\d{4}-\d{2}-\d{2}_(\d+)_", re.IGNORECASE)
_INDEX_NAME_RE = re.compile(r"^PN_(\d{4}-\d{2}-\d{2})_(AM|PM)_INDEX\.md$", re.IGNORECASE)

EXCLUDE_PREFIXES = ("CHECKPOINT",)
EXCLUDE_POLICIES = ("private", "internal-only")
VALID_SECTIONS = ("learning", "goals", "practice", "projects")


@dataclass
class GroupNote:
    number: int
    filename: str
    public_policy: str = "partial-public"
    target_section: str = "learning"
    policy_from_index: bool = False


@dataclass
class NoteGroup:
    date: str
    period: str               # "AM" | "PM"
    index_path: Path
    notes: list[GroupNote] = field(default_factory=list)


def _note_number(filename: str) -> int:
    m = _NUM_RE.match(filename)
    return int(m.group(1)) if m else 999


def parse_index_notes(index_text: str) -> list[GroupNote]:
    """INDEX 본문에서 공개 대상 노트 목록을 추출 (번호순 정렬).

    명단 섹션에 진입한 뒤 다른 '## ' 헤더를 만나면 종료한다
    (PM 의 '## processing guidance' 가 노트 번호를 언급해 섞이는 것을 방지).
    """
    lines = index_text.splitlines()
    in_section = False
    notes: list[GroupNote] = []
    current: GroupNote | None = None

    def _flush(note: GroupNote | None) -> None:
        if note is None:
            return
        name = note.filename
        if any(name.upper().startswith(p) for p in EXCLUDE_PREFIXES):
            return
        if note.public_policy.lower() in EXCLUDE_POLICIES:
            return
        notes.append(note)

    for line in lines:
        if not in_section:
            if _NOTE_SECTION_RE.match(line):
                in_section = True
            continue

        # 명단 섹션 종료: 다른 ## 헤더
        if _ANY_H2_RE.match(line) and not _NOTE_SECTION_RE.match(line):
            break

        m = _NOTE_LINE_RE.search(line)
        if m:
            _flush(current)
            fn = m.group(1).strip()
            current = GroupNote(number=_note_number(fn), filename=fn)
            continue

        if current is not None:
            pm = _POLICY_RE.search(line)
            if pm:
                current.public_policy = pm.group(1).lower()
                current.policy_from_index = True
            sm = _SECTION_RE.search(line)
            if sm and sm.group(1).lower() in VALID_SECTIONS:
                current.target_section = sm.group(1).lower()

    _flush(current)
    notes.sort(key=lambda n: n.number)
    return notes


def find_index_files(
    notes_dir: Path, date: str = "", period: str = ""
) -> list[tuple[str, str, Path]]:
    """personal_notes 에서 AM/PM INDEX 파일들을 찾는다.

    INDEX 는 intake 의 SKIP_PATTERNS 로 registry 에 안 들어오므로
    파일시스템을 직접 glob 한다. 반환: [(date, period, path)] (날짜·시간대순).
    """
    found: list[tuple[str, str, Path]] = []
    if not notes_dir.exists():
        return found
    for p in sorted(notes_dir.glob("PN_*_INDEX.md")):
        m = _INDEX_NAME_RE.match(p.name)
        if not m:
            continue
        d, per = m.group(1), m.group(2).upper()
        if date and d != date:
            continue
        if period and per != period.upper():
            continue
        found.append((d, per, p))
    found.sort(key=lambda t: (t[0], t[1]))
    return found


def build_group(index_path: Path) -> NoteGroup:
    """INDEX 파일 하나를 NoteGroup 으로 파싱."""
    m = _INDEX_NAME_RE.match(index_path.name)
    date = m.group(1) if m else ""
    period = m.group(2).upper() if m else ""
    text = index_path.read_text(encoding="utf-8")
    return NoteGroup(
        date=date, period=period, index_path=index_path,
        notes=parse_index_notes(text),
    )


def assemble_group_body(group: NoteGroup, notes_dir: Path) -> tuple[str, list[str]]:
    """그룹의 노트들을 번호순으로 읽어 frontmatter 제거 후 하나로 합친다.

    반환: (합친 본문, 실제 사용된 파일명 리스트).
    파일이 없으면 안전하게 건너뛴다 (registry/INDEX 불일치 대응).
    """
    parts: list[str] = []
    used: list[str] = []
    for note in group.notes:
        path = notes_dir / note.filename
        if not path.exists():
            continue
        body = _strip_leading_front_matter(path.read_text(encoding="utf-8")).strip()
        if body:
            parts.append(body)
            used.append(note.filename)
    return ("\n\n".join(parts).strip(), used)


def pick_section(notes: list[GroupNote]) -> str:
    """노트들의 target_section 다수결. 동률/없으면 learning."""
    counts: dict[str, int] = {}
    for n in notes:
        sec = n.target_section if n.target_section in VALID_SECTIONS else "learning"
        counts[sec] = counts.get(sec, 0) + 1
    if not counts:
        return "learning"
    top = max(counts.values())
    winners = [s for s, c in counts.items() if c == top]
    return "learning" if len(winners) > 1 else winners[0]
