"""extract — LLM 으로 소스 처리 (classify → extract → working_note)."""

from __future__ import annotations

import csv
from datetime import date
from pathlib import Path
from typing import Any

from rich.console import Console

from .config import resolve_path
from .adapters.base import LLMAdapter
from .chunker import generate_chunked, DEFAULT_MAX_CHARS

console = Console()

BLOG_DRAFT_INSTRUCTION = (
    "너는 LearningLog 파이프라인의 Hugo 블로그 초안 생성 워커다.\n"
    "아래 워킹 노트를 바탕으로 Hugo 블로그 초안을 한국어로 작성해라.\n\n"
    "규칙:\n"
    "- 강의 원문 복사 금지 — 내 학습 경험과 해석 위주\n"
    "- draft: true 로 작성 (발행은 인간이 결정)\n"
    "- source_id 는 front matter 에 포함하지 말 것\n\n"
    "출력 형식:\n"
    "---\ntitle: \"\"\ndate: {date}\ndraft: true\n"
    "categories: [\"\"]\ntags: []\ndescription: \"\"\n---\n\n"
    "본문 (왜 썼나 / 배운 것 / 헷갈린 것 / 정리된 이해 / 실습 예시 / 초보자 키워드 / 다음 복습)"
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


def run_extract(
    cfg: dict[str, Any],
    adapter: LLMAdapter,
    source_id: str = "",
    skip_llm: bool = False,
    max_chars: int = DEFAULT_MAX_CHARS,
) -> None:
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
    if max_chars == DEFAULT_MAX_CHARS:
        if adapter.provider_name == "ollama":
            # Ollama: num_ctx 기반으로 계산
            from .adapters.ollama import OllamaAdapter
            if isinstance(adapter, OllamaAdapter):
                max_chars = adapter.safe_max_chars()
                console.print(f"  Ollama 컨텍스트: {adapter.num_ctx}토큰 → 청크: [cyan]{max_chars}[/] 자/파트")
        else:
            # 클라우드 API (Gemini/Groq/Claude/OpenAI): 컨텍스트 충분 → 청킹 불필요
            max_chars = 50000
            console.print(f"  클라우드 API ({adapter.provider_name}) → 청킹 없음 (최대 {max_chars}자)")

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

            draft_dir  = resolve_path(cfg, "drafts", "04_blog_drafts") / section
            draft_path = draft_dir / f"{topic}.md"

            if draft_path.exists():
                console.print("    [dim]MODE 4 draft     SKIP (이미 존재)[/]")
            else:
                draft_dir.mkdir(parents=True, exist_ok=True)
                console.print(f"    MODE 4 draft     [{adapter.provider_name}] ", end="")
                try:
                    # 입력: 워킹 노트 (원본 소스 아님)
                    wk_content = wk_path.read_text(encoding="utf-8") if wk_path.exists() else body
                    instruction = BLOG_DRAFT_INSTRUCTION.format(date=today)
                    result = generate_chunked(adapter, instruction, wk_content,
                                              max_chars=max_chars, verbose=False)
                    draft_path.write_text(result, encoding="utf-8")
                    _update_status(registry, sid, "drafted")
                    console.print("[green]OK[/]")
                    console.print(f"    [dim]→ 04_blog_drafts/{section}/{topic}.md[/]")
                except Exception as e:
                    console.print(f"[red]FAIL[/] {e}")
        else:
            console.print("    [dim]MODE 4 draft     SKIP (internal-only)[/]")

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
