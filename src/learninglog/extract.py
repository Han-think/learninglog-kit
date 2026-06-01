"""extract — LLM 으로 소스 처리 (classify → extract → working_note)."""

from __future__ import annotations

import csv
from datetime import date
from pathlib import Path
from typing import Any

from rich.console import Console

from .config import resolve_path
from .adapters.base import LLMAdapter
from .chunker import (
    generate_chunked,
    remove_extra_hugo_front_matter,
    split_into_halves,
    DEFAULT_MAX_CHARS,
)

console = Console()

BLOG_DRAFT_INSTRUCTION = (
    "너는 LearningLog 파이프라인의 Hugo 블로그 초안 생성 워커다.\n"
    "아래 워킹 노트를 바탕으로 Hugo 블로그 초안을 한국어로 한 편 작성해라.\n\n"
    "규칙:\n"
    "- 강의 원문 복사 금지 — 내 학습 경험과 해석 위주\n"
    "- draft: true 로 작성 (발행은 인간이 결정)\n"
    "- source_id 등 내부 메타는 절대 본문/front matter 에 포함 금지\n\n"
    "본문 구조 규칙 (반드시 지킬 것):\n"
    "- 최상위 큰제목 '## ' 은 글 전체에 정확히 1개 (이 글의 주제)\n"
    "- 세부 섹션은 모두 '### ' 로 작성\n"
    "- 같은 '### 섹션 제목' 을 두 번 이상 반복하지 말 것\n"
    "- '## ' 를 여러 개 평면적으로 나열하지 말 것\n\n"
    "출력 형식:\n"
    "---\ntitle: \"\"\ndate: {date}\ndraft: true\n"
    "categories: [\"\"]\ntags: []\ndescription: \"\"\nai_assisted: true\n---\n\n"
    "## (글 전체 주제를 담은 큰제목 1개)\n\n"
    "(주제를 소개하는 도입 문단)\n\n"
    "### 왜 썼나\n### 배운 것\n### 헷갈린 것\n### 정리된 이해\n"
    "### 실습 예시\n### 초보자 키워드 (의미+검색어)\n### 다음 복습"
)

PROMPTS = {
    "classify": (
        "너는 학습 노트 분류 워커다.\n"
        "아래 노트를 읽고 다음 JSON 형식으로만 출력해라. 다른 텍스트 없이 JSON만.\n"
        '{{"source_type":"","topic":"","language":"","public_policy":"",'
        '"target_section":"learning|practice|projects|goals","tags":[]}}\n---\n{body}'
    ),
    "extract": (
        "너는 학습 노트 사실 추출 워커다.\n"
        "핵심 사실만 추출해라. 개인 해석은 포함하지 마라. 한국어로.\n"
        "출력:\n# Extracted Summary\n## 핵심 개념\n## 명령어 / 코드\n## 기억할 사실\n---\n{body}"
    ),
    "working_note": (
        "너는 학습 워킹 노트 생성 워커다.\n"
        "아래 노트를 바탕으로 한국어 워킹 노트를 작성해라.\n"
        "초보자 시점, 학습자의 혼란을 중심으로.\n"
        "포함: 무엇이 헷갈렸나 / 정리된 이해 / 실습 예시 / "
        "초보자 키워드(의미+검색어) / 내 프로젝트 연결 / 다음 복습 주제\n---\n{body}"
    ),
}


def _resolve_max_chars(adapter: LLMAdapter, max_chars: int) -> int:
    """청크 크기 결정 (단일/그룹 모드 공유). 기본값이면 provider 기준 자동 계산."""
    if max_chars != DEFAULT_MAX_CHARS:
        return max_chars
    if adapter.provider_name == "ollama":
        from .adapters.ollama import OllamaAdapter
        if isinstance(adapter, OllamaAdapter):
            mc = adapter.safe_max_chars()
            console.print(f"  Ollama 컨텍스트: {adapter.num_ctx}토큰 → 청크: [cyan]{mc}[/] 자/파트")
            return mc
        return max_chars
    # 클라우드 API (Gemini/Groq/Claude/OpenAI): 컨텍스트 충분 → 청킹 불필요
    console.print(f"  클라우드 API ({adapter.provider_name}) → 청킹 없음 (최대 50000자)")
    return 50000


def run_extract(
    cfg: dict[str, Any],
    adapter: LLMAdapter,
    source_id: str = "",
    skip_llm: bool = False,
    max_chars: int = DEFAULT_MAX_CHARS,
    group: bool = False,
    date_filter: str = "",
    period: str = "",
) -> None:
    # 그룹 모드: 오전/오후 INDEX 기준으로 묶어 통합 글 1편
    if group:
        run_group_extract(cfg, adapter, skip_llm=skip_llm, max_chars=max_chars,
                           date_filter=date_filter, period=period)
        return

    root       = resolve_path(cfg, "registry", "01_registry/source_registry.csv").parent.parent
    registry   = resolve_path(cfg, "registry", "01_registry/source_registry.csv")
    inbox      = resolve_path(cfg, "inbox", "00_inbox")
    extracted  = resolve_path(cfg, "extracted", "02_extracted") / "concept_extracts"
    working    = resolve_path(cfg, "working", "03_working_notes") / "daily_logs"
    today      = date.today().strftime("%Y-%m-%d")

    extracted.mkdir(parents=True, exist_ok=True)
    working.mkdir(parents=True, exist_ok=True)

    # 대상 소스 선택
    with open(registry, encoding="utf-8") as f:
        all_rows = list(csv.DictReader(f))

    if source_id:
        targets = [r for r in all_rows if r["source_id"] == source_id]
    else:
        targets = [
            r for r in all_rows
            if r.get("status") in ("registered", "new")
            and r.get("source_type") == "personal_note"
            and r.get("public_policy") in ("public", "partial-public")
        ]

    if not targets:
        console.print("[yellow]처리할 소스 없음.[/]")
        return

    # 청크 크기 결정
    max_chars = _resolve_max_chars(adapter, max_chars)

    console.print(f"\n  대상: [cyan]{len(targets)}[/] 개  |  LLM: [cyan]{adapter.provider_name}[/]\n")

    for row in targets:
        sid   = row["source_id"]
        topic = row["topic"]
        src   = root / row["source_path"].replace("/", "\\")

        console.print(f"  [magenta][{sid}][/] {topic}")

        if not src.exists() or src.suffix.lower() not in (".md", ".txt"):
            console.print("    [dim]SKIP — 파일 없음 또는 텍스트 아님[/]")
            continue

        body = src.read_text(encoding="utf-8")

        if skip_llm:
            console.print("    [dim]--skip-llm: LLM 건너뜀[/]")
            continue

        # extract
        ext_path = extracted / f"{sid}_{topic}_extract.md"
        if ext_path.exists():
            console.print("    [dim]MODE 2 extract  SKIP (이미 존재)[/]")
        else:
            console.print(f"    MODE 2 extract   [{adapter.provider_name}] ", end="")
            try:
                instruction = PROMPTS["extract"].replace("\n---\n{body}", "")
                result = generate_chunked(adapter, instruction, body,
                                          max_chars=max_chars, verbose=False)
                fm = f"---\nsource_id: {sid}\nextract_date: {today}\nmodel: {adapter.provider_name}\n---\n\n"
                ext_path.write_text(fm + result, encoding="utf-8")
                _update_status(registry, sid, "extracted")
                console.print("[green]OK[/]")
            except Exception as e:
                console.print(f"[red]FAIL[/] {e}")
                continue

        # working_note
        wk_path = working / f"{today}_{topic}.md"
        if wk_path.exists():
            console.print("    [dim]MODE 3 working   SKIP (이미 존재)[/]")
        else:
            console.print(f"    MODE 3 working   [{adapter.provider_name}] ", end="")
            try:
                instruction = PROMPTS["working_note"].replace("\n---\n{body}", "")
                result = generate_chunked(adapter, instruction, body,
                                          max_chars=max_chars, verbose=False)
                fm = f"---\nsource_id: {sid}\nnote_date: {today}\nmodel: {adapter.provider_name}\n---\n\n"
                wk_path.write_text(fm + result, encoding="utf-8")
                _update_status(registry, sid, "working")
                console.print("[green]OK[/]")
            except Exception as e:
                console.print(f"[red]FAIL[/] {e}")

        # blog_draft — partial-public / public 만
        if row.get("public_policy") in ("public", "partial-public"):
            # classify 결과에서 section 파싱
            section = "learning"
            classify_path = Path(cfg.get("paths", {}).get("reports", "09_reports")) / f"llm_prep/classify_{sid}.json"
            if classify_path.exists():
                try:
                    import json
                    cdata = json.loads(classify_path.read_text(encoding="utf-8"))
                    section = cdata.get("target_section", "learning")
                except Exception:
                    pass
            # section 검증 — 정해진 4개만 허용
            if section not in ("learning", "goals", "practice", "projects"):
                section = "learning"

            draft_dir = resolve_path(cfg, "drafts", "04_blog_drafts") / section
            draft_dir.mkdir(parents=True, exist_ok=True)

            # 입력: 워킹 노트 (원본 소스 아님)
            wk_content  = wk_path.read_text(encoding="utf-8") if wk_path.exists() else body
            instruction = BLOG_DRAFT_INSTRUCTION.format(date=today)

            # 하루치를 오전/오후 2편으로 분할 (짧으면 1편)
            halves = split_into_halves(wk_content)
            if len(halves) == 1:
                # 하위호환: 기존 단일 파일명
                outputs = [(draft_dir / f"{topic}.md", halves[0], "")]
            else:
                outputs = [
                    (draft_dir / f"{topic}-01.md", halves[0],
                     "\n(이 글은 하루 학습의 '오전' 부분이다. 오전 내용만 한 편으로 작성)"),
                    (draft_dir / f"{topic}-02.md", halves[1],
                     "\n(이 글은 하루 학습의 '오후' 부분이다. 오후 내용만 한 편으로 작성)"),
                ]

            made_any = False
            for out_path, content, part_hint in outputs:
                if out_path.exists():
                    console.print(f"    [dim]MODE 4 draft     SKIP (존재): {out_path.name}[/]")
                    continue
                console.print(f"    MODE 4 draft     [{adapter.provider_name}] {out_path.name} ", end="")
                try:
                    result = generate_chunked(adapter, instruction + part_hint, content,
                                              max_chars=max_chars, verbose=False)
                    result = remove_extra_hugo_front_matter(result)
                    out_path.write_text(result, encoding="utf-8")
                    console.print("[green]OK[/]")
                    made_any = True
                except Exception as e:
                    console.print(f"[red]FAIL[/] {e}")

            if made_any:
                _update_status(registry, sid, "drafted")
        else:
            console.print("    [dim]MODE 4 draft     SKIP (internal-only)[/]")

    console.print()


def run_group_extract(
    cfg: dict[str, Any],
    adapter: LLMAdapter,
    *,
    skip_llm: bool = False,
    max_chars: int = DEFAULT_MAX_CHARS,
    date_filter: str = "",
    period: str = "",
) -> None:
    """오전/오후 INDEX 기준으로 여러 노트를 묶어 통합 블로그 글 1편 생성."""
    from .groups import (
        find_index_files, build_group, assemble_group_body, pick_section,
    )

    root      = resolve_path(cfg, "registry", "01_registry/source_registry.csv").parent.parent
    registry  = resolve_path(cfg, "registry", "01_registry/source_registry.csv")
    inbox     = resolve_path(cfg, "inbox", "00_inbox")
    notes_dir = inbox / "personal_notes"
    drafts    = resolve_path(cfg, "drafts", "04_blog_drafts")

    indexes = find_index_files(notes_dir, date=date_filter, period=period)
    if not indexes:
        console.print("[yellow]처리할 INDEX(AM/PM) 파일 없음.[/]")
        return

    # registry 보강 lookup (policy/status) — 파일명 기준
    reg_by_file: dict[str, dict[str, str]] = {}
    if registry.exists():
        with open(registry, encoding="utf-8") as f:
            for row in csv.DictReader(f):
                fn = Path(row.get("source_path", "")).name
                if fn:
                    reg_by_file[fn] = row

    max_chars = _resolve_max_chars(adapter, max_chars)
    console.print(f"\n  그룹 대상: [cyan]{len(indexes)}[/] 개 INDEX  |  LLM: [cyan]{adapter.provider_name}[/]\n")

    PROTECTED = ("published", "archived")

    for d, per, index_path in indexes:
        console.print(f"  [magenta][{d} {per}][/] {index_path.name}")
        group = build_group(index_path)

        # registry fallback: INDEX 에 policy 없던 노트는 registry 값으로 보강 후 재필터
        kept = []
        for note in group.notes:
            if not note.policy_from_index and note.filename in reg_by_file:
                note.public_policy = reg_by_file[note.filename].get(
                    "public_policy", note.public_policy)
            if note.public_policy.lower() in ("private", "internal-only"):
                continue
            kept.append(note)
        group.notes = kept

        if not group.notes:
            console.print("    [dim]SKIP — 공개 가능한 노트 없음[/]")
            continue

        body, used = assemble_group_body(group, notes_dir)
        if not body:
            console.print("    [dim]SKIP — 합칠 본문 없음[/]")
            continue

        console.print(f"    노트 {len(used)}개 합침 ({', '.join(str(n.number) for n in group.notes)})")
        if skip_llm:
            console.print("    [dim]--skip-llm: LLM 건너뜀[/]")
            continue

        section   = pick_section(group.notes)
        draft_dir = drafts / section
        draft_dir.mkdir(parents=True, exist_ok=True)
        out_path  = draft_dir / f"{d}-{per.lower()}.md"

        if out_path.exists():
            console.print(f"    [dim]SKIP (존재): {out_path.name}[/]")
            continue

        period_kr   = "오전" if per == "AM" else "오후"
        part_hint   = f"\n(이 글은 {d} {period_kr} 학습 전체를 아우르는 통합 정리 글이다. 한 편으로 작성)"
        instruction = BLOG_DRAFT_INSTRUCTION.format(date=d)

        console.print(f"    GROUP draft  [{adapter.provider_name}] {out_path.name} ", end="")
        try:
            result = generate_chunked(adapter, instruction + part_hint, body,
                                      max_chars=max_chars, verbose=False)
            result = remove_extra_hugo_front_matter(result)
            out_path.write_text(result, encoding="utf-8")
            console.print("[green]OK[/]")
            console.print(f"    [dim]→ 04_blog_drafts/{section}/{out_path.name}[/]")

            # status 역행 방지: published/archived 보호, 그 외만 drafted
            for note in group.notes:
                row = reg_by_file.get(note.filename)
                if row and row.get("status") not in PROTECTED:
                    _update_status(registry, row["source_id"], "drafted")
        except Exception as e:
            console.print(f"[red]FAIL[/] {e}")

    console.print()


def _update_status(registry: Path, source_id: str, new_status: str) -> None:
    with open(registry, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    for row in rows:
        if row["source_id"] == source_id:
            row["status"] = new_status
    fieldnames = rows[0].keys() if rows else []
    with open(registry, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
