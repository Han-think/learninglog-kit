"""CLI 진입점 — learninglog 명령어 모음."""

from __future__ import annotations

import sys

# Windows 터미널 인코딩을 UTF-8 로 통일 (Git Bash / VS Code terminal 기준)
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass

from pathlib import Path

import click
from rich.console import Console

from . import __version__
from .config import load_config, find_config
from .adapters import create_adapter

console = Console()


@click.group()
@click.version_option(__version__, prog_name="learninglog")
def main() -> None:
    """learninglog-kit: 개인 학습 파이프라인 도구."""


# ─── init ─────────────────────────────────────────────────
@main.command()
@click.argument("path", default=".", type=click.Path())
def init(path: str) -> None:
    """새 LearningLog 프로젝트 폴더를 초기화합니다.

    \b
    사용 예:
        learninglog init              # 현재 폴더
        learninglog init my-learning  # 새 폴더 생성
    """
    from .init_project import init_project
    init_project(Path(path).resolve())


# ─── intake ────────────────────────────────────────────────
@main.command()
@click.option("--dry-run", is_flag=True, help="실제 등록 없이 미리보기만")
def intake(dry_run: bool) -> None:
    """00_inbox 를 스캔해 새 파일을 source_registry.csv 에 등록합니다."""
    cfg = _load_or_exit()
    from .intake import run_intake
    run_intake(cfg, dry_run=dry_run)


# ─── queue ─────────────────────────────────────────────────
@main.command()
def queue() -> None:
    """처리 대기 소스 우선순위 리포트를 출력합니다."""
    cfg = _load_or_exit()
    from .queue_report import run_queue
    run_queue(cfg)


# ─── extract ───────────────────────────────────────────────
@main.command()
@click.option("--source-id", "-s", default="", help="특정 소스만 처리")
@click.option("--skip-llm", is_flag=True, help="LLM 없이 패킷 조립만")
@click.option("--max-chars", default=1500, show_default=True,
              help="청크당 최대 문자 수. 모델 컨텍스트에 맞게 조정 (2048토큰=1500 / 4096토큰=3000)")
def extract(source_id: str, skip_llm: bool, max_chars: int) -> None:
    """소스를 LLM 으로 처리해 extract + working_note 를 생성합니다.

    \b
    사용 예:
        learninglog extract                  # 전체 처리
        learninglog extract -s SRC-001       # 특정 소스만
        learninglog extract --skip-llm       # 패킷만 조립
    """
    cfg     = _load_or_exit()
    adapter = create_adapter(cfg)

    if not skip_llm and adapter.provider_name == "none":
        console.print("[yellow]LLM provider 가 설정되지 않았습니다.[/]")
        console.print("config.yaml 에서 llm.provider 를 설정하거나 --skip-llm 옵션을 사용하세요.")
        console.print("무료 옵션: gemini, groq  |  로컬: ollama")
        console.print("[dim]문서: docs/llm-providers.md[/]")
        raise SystemExit(1)

    from .extract import run_extract
    run_extract(cfg, adapter=adapter, source_id=source_id,
                skip_llm=skip_llm, max_chars=max_chars)


# ─── publish ───────────────────────────────────────────────
@main.command()
@click.option("--source-id", "-s", default="", help="특정 소스만 발행")
def publish(source_id: str) -> None:
    """04_blog_drafts 초안을 블로그로 발행합니다 (config.yaml 의 blog 설정 사용).

    \b
    draft:false 변환 + source_id 제거 + ai_assisted 마킹 후
    blog.source_path/content/{section}/ 으로 복사.
    blog.auto_build=true 면 hugo 빌드, blog.auto_push=true 면 git push.
    """
    cfg = _load_or_exit()
    from .publish import run_publish
    run_publish(cfg, source_id=source_id)


# ─── status ────────────────────────────────────────────────
@main.command()
def status() -> None:
    """현재 파이프라인 상태를 요약합니다."""
    cfg = _load_or_exit()
    _print_status(cfg)


# ─── doctor ────────────────────────────────────────────────
@main.command()
def doctor() -> None:
    """설정과 LLM 연결 상태를 진단합니다."""
    cfg      = _load_or_exit()
    adapter  = create_adapter(cfg)
    provider = adapter.provider_name

    console.print(f"\n[bold]learninglog doctor[/] v{__version__}\n")
    console.print(f"  LLM provider : [cyan]{provider}[/]")

    if provider == "none":
        console.print("  LLM 상태     : [yellow]설정 안 됨[/] (intake/queue 는 사용 가능)")
    else:
        ok = adapter.health_check()
        state = "[green]OK[/]" if ok else "[red]연결 실패[/]"
        console.print(f"  LLM 상태     : {state}")

    config_file = find_config()
    console.print(f"  config.yaml  : [dim]{config_file}[/]")
    console.print()


# ─── 공통 헬퍼 ────────────────────────────────────────────
def _load_or_exit() -> dict:
    cfg_path = find_config()
    if cfg_path is None:
        console.print("[red]config.yaml 을 찾을 수 없습니다.[/]")
        console.print("이 폴더가 LearningLog 프로젝트인지 확인하거나 'learninglog init' 을 실행하세요.")
        raise SystemExit(1)
    return load_config(cfg_path)


def _print_status(cfg: dict) -> None:
    """간단한 현황 출력."""
    from .config import resolve_path
    import csv

    registry = resolve_path(cfg, "registry", "01_registry/source_registry.csv")
    if not registry.exists():
        console.print("[yellow]source_registry.csv 없음 — intake 를 먼저 실행하세요.[/]")
        return

    with open(registry, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    total     = len(rows)
    pending   = sum(1 for r in rows if r.get("status") in ("registered", "new"))
    working   = sum(1 for r in rows if r.get("status") == "working")
    drafted   = sum(1 for r in rows if r.get("status") == "drafted")

    console.print(f"\n  소스 전체  : [bold]{total}[/]")
    console.print(f"  대기       : [yellow]{pending}[/]")
    console.print(f"  작업 중    : [cyan]{working}[/]")
    console.print(f"  초안 완료  : [green]{drafted}[/]")
    console.print()
