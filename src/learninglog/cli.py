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


# ─── ui ────────────────────────────────────────────────────
@main.command()
@click.option("--port", default=8765, show_default=True, help="웹 UI 포트")
@click.option("--no-browser", is_flag=True, help="브라우저 자동 열기 안 함")
def ui(port: int, no_browser: bool) -> None:
    """브라우저 설정/실행 UI 를 엽니다 (설치·API키·실행을 버튼으로).

    \b
    pip install "learninglog-kit[web]" 필요.
    learninglog ui  →  http://127.0.0.1:8765
    """
    from .webui import run_ui
    if no_browser:
        import learninglog.webui as w
        w.webbrowser = type("X", (), {"open": staticmethod(lambda *a: None)})()
    run_ui(port=port)


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


# ─── push ──────────────────────────────────────────────────
@main.command()
def push() -> None:
    """설정된 블로그 Git 저장소에 변경사항을 명시적으로 push 합니다."""
    cfg = _load_or_exit()
    from .publish import run_push
    run_push(cfg)


# ─── clean ─────────────────────────────────────────────────
@main.command()
@click.option("--outputs", is_flag=True, help="생성물(02~06, 09_reports) 삭제")
@click.option("--registry", is_flag=True, help="01_registry 상태장부 삭제")
@click.option("--config", "config_", is_flag=True, help=".learninglog/config.yaml 삭제")
@click.option("--api-key", is_flag=True, help="~/.bashrc 의 API 키 줄 제거")
@click.option("--all", "all_", is_flag=True, help="위 전부 (00_inbox 원본은 제외)")
@click.option("--yes", "-y", is_flag=True, help="확인 없이 삭제")
def clean(outputs: bool, registry: bool, config_: bool, api_key: bool, all_: bool, yes: bool) -> None:
    """생성물·설정·API키를 정리합니다. (00_inbox 원본 노트는 보존)

    \b
    learninglog clean              # 생성물만 (기본)
    learninglog clean --config     # 설정도 삭제
    learninglog clean --all -y      # 전부 삭제 (확인 생략)
    """
    from pathlib import Path
    from .clean import run_clean
    if all_:
        outputs = registry = config_ = api_key = True
    run_clean(Path.cwd(), outputs=outputs, config=config_,
              registry=registry, api_key=api_key, yes=yes)


# ─── uninstall ─────────────────────────────────────────────
@main.command()
@click.option("--keep-package", is_flag=True, help="데이터만 제거하고 pip 패키지는 유지")
@click.option("--yes", "-y", is_flag=True, help="확인 없이 진행")
def uninstall(keep_package: bool, yes: bool) -> None:
    """프로그램과 생성 데이터를 모두 제거합니다 (install 의 반대).

    \b
    - 생성물 + 설정 + API키 정리 (clean --all 과 동일)
    - 이어서 pip uninstall learninglog-kit 실행
    - 00_inbox 원본 노트는 보존
    """
    import subprocess, sys
    from pathlib import Path
    from .clean import run_clean

    console.print("\n[bold]learninglog uninstall[/] — 프로그램 + 데이터 제거")
    run_clean(Path.cwd(), outputs=True, config=True,
              registry=True, api_key=True, yes=yes)

    if keep_package:
        console.print("  [dim]--keep-package: pip 패키지는 유지합니다.[/]")
        return

    console.print()
    if not yes:
        from rich.prompt import Confirm
        if not Confirm.ask("  pip 패키지(learninglog-kit)도 제거할까요?", default=False):
            console.print("  패키지는 유지합니다. 직접 제거: pip uninstall learninglog-kit")
            return

    console.print("  pip uninstall 실행 중...")
    try:
        subprocess.run([sys.executable, "-m", "pip", "uninstall", "-y", "learninglog-kit"],
                       check=False)
        console.print("  [green]제거 완료. 그동안 이용해주셔서 감사합니다![/]")
    except Exception as e:
        console.print(f"  [yellow]자동 제거 실패: {e}[/]")
        console.print("  수동 제거: pip uninstall learninglog-kit")


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
    _print_environment_checks(cfg)
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


def _print_environment_checks(cfg: dict) -> None:
    import shutil
    import subprocess
    from pathlib import Path

    def mark(ok: bool) -> str:
        return "[green]OK[/]" if ok else "[yellow]확인 필요[/]"

    # 누락 항목별 해결 안내를 모아 뒤에 한 번에 출력
    fixes: list[str] = []

    console.print("\n  [bold]환경 체크[/]")
    console.print(f"  Python       : [green]OK[/] ({sys.version.split()[0]})")

    # Hugo — 블로그 빌드(publish)에 필요
    hugo = shutil.which("hugo")
    console.print(f"  Hugo         : {mark(bool(hugo))}" + (f" ({hugo})" if hugo else ""))
    if not hugo:
        fixes.append(
            "Hugo 미설치 (publish 단계 필요) — extended 버전 설치:\n"
            "      https://gohugo.io/installation/\n"
            "      Windows: winget install Hugo.Hugo.Extended"
        )

    # Git — 블로그 발행/푸시에 필요
    git = shutil.which("git")
    console.print(f"  Git          : {mark(bool(git))}" + (f" ({git})" if git else ""))
    if not git:
        fixes.append(
            "Git 미설치 (블로그 발행 필요) — 설치:\n"
            "      https://git-scm.com/downloads"
        )

    blog = cfg.get("blog", {})
    source_path = blog.get("source_path", "")
    blog_root = Path(source_path) if source_path else Path("")
    if source_path and not blog_root.is_absolute():
        cf = find_config()
        root = cf.parent.parent if cf else Path.cwd()
        blog_root = (root / source_path).resolve()

    blog_ok = bool(source_path and blog_root.exists())
    console.print(f"  Blog path    : {mark(blog_ok)}" + (f" ({blog_root})" if source_path else ""))
    if not blog_ok:
        if not source_path:
            fixes.append(
                "블로그 경로 미설정 — config.yaml 의 blog.source_path 에 Hugo 블로그 폴더 경로를 적으세요.\n"
                "      블로그가 없다면 publish 없이 extract(노트 정리)까지만 써도 됩니다."
            )
        else:
            fixes.append(
                f"블로그 폴더를 찾을 수 없음: {blog_root}\n"
                "      config.yaml 의 blog.source_path 를 실제 Hugo 사이트 폴더로 고치세요."
            )

    git_repo_ok = bool(source_path and (blog_root / ".git").exists())
    console.print(f"  Git repo     : {mark(git_repo_ok)}")
    if source_path and blog_root.exists() and not git_repo_ok:
        fixes.append(
            f"블로그 폴더가 Git 저장소가 아님 — GitHub Pages 발행하려면 초기화:\n"
            f"      cd \"{blog_root}\" && git init && git remote add origin <저장소URL>"
        )

    if git_repo_ok and git:
        try:
            remote = subprocess.run(
                ["git", "remote", "get-url", "origin"],
                cwd=blog_root,
                capture_output=True,
                text=True,
                timeout=5,
            )
            ok = remote.returncode == 0 and bool(remote.stdout.strip())
            console.print(f"  Git origin   : {mark(ok)}" + (f" ({remote.stdout.strip()})" if ok else ""))
            if not ok:
                fixes.append(
                    f"Git 원격(origin) 미설정 — 발행 대상 지정:\n"
                    f"      cd \"{blog_root}\" && git remote add origin <저장소URL>"
                )
        except Exception:
            console.print(f"  Git origin   : {mark(False)}")

    if fixes:
        console.print("\n  [bold yellow]해결 안내[/]")
        for f in fixes:
            console.print(f"  • {f}")
