"""clean — 생성물/설정/API키 정리 (안전 삭제).

원칙:
  - 00_inbox (사용자 원본 노트)는 기본적으로 절대 삭제하지 않음
  - 삭제 전 항상 확인 (--yes 로 생략 가능)
  - API 키는 ~/.bashrc 에서 해당 줄만 제거
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path

from rich.console import Console
from rich.prompt import Confirm

from .config import find_config

console = Console()

# 생성물 폴더 (사용자 원본 00_inbox 제외)
OUTPUT_DIRS = [
    "02_extracted",
    "03_working_notes",
    "04_blog_drafts",
    "05_ready_to_publish",
    "06_published",
    "09_reports",
]

API_KEY_VARS = ["GEMINI_API_KEY", "GROQ_API_KEY", "ANTHROPIC_API_KEY", "OPENAI_API_KEY"]


def run_clean(project_dir: Path, outputs: bool, config: bool,
              registry: bool, api_key: bool, yes: bool) -> None:
    cf = find_config(project_dir)
    root = cf.parent.parent if cf else project_dir

    # 아무 옵션 없으면 기본 = outputs
    if not (outputs or config or registry or api_key):
        outputs = True

    console.print(f"\n  대상 폴더: [cyan]{root}[/]")
    console.print("  [yellow]00_inbox (원본 노트)는 삭제하지 않습니다.[/]\n")

    plan = []
    if outputs:  plan.append("생성물 (02~06, 09_reports)")
    if registry: plan.append("01_registry (상태 장부)")
    if config:   plan.append(".learninglog/config.yaml")
    if api_key:  plan.append("~/.bashrc 의 API 키 줄")

    console.print("  삭제할 항목:")
    for p in plan:
        console.print(f"    • {p}")
    console.print()

    if not yes and not Confirm.ask("  정말 삭제할까요?", default=False):
        console.print("  취소됨.")
        return

    removed = 0

    if outputs:
        for d in OUTPUT_DIRS:
            target = root / d
            if target.exists():
                shutil.rmtree(target, ignore_errors=True)
                console.print(f"  [red]삭제[/] {d}/")
                removed += 1

    if registry:
        reg = root / "01_registry"
        if reg.exists():
            shutil.rmtree(reg, ignore_errors=True)
            console.print("  [red]삭제[/] 01_registry/")
            removed += 1

    if config:
        cfgdir = root / ".learninglog"
        if cfgdir.exists():
            shutil.rmtree(cfgdir, ignore_errors=True)
            console.print("  [red]삭제[/] .learninglog/")
            removed += 1

    if api_key:
        _clean_bashrc()

    console.print(f"\n  [bold]정리 완료[/] ({removed} 항목)")
    console.print("  [dim]패키지 자체 제거: pip uninstall learninglog-kit[/]")
    console.print("  [dim]원본 노트(00_inbox)는 그대로 보존됨[/]\n")


def _clean_bashrc() -> None:
    bashrc = Path.home() / ".bashrc"
    if not bashrc.exists():
        console.print("  [dim]~/.bashrc 없음 — API 키 정리 건너뜀[/]")
        return
    try:
        lines = bashrc.read_text(encoding="utf-8").splitlines(keepends=True)
        pattern = re.compile(r'^\s*export\s+(' + "|".join(API_KEY_VARS) + r')=')
        kept = [ln for ln in lines if not pattern.match(ln)]
        if len(kept) != len(lines):
            bashrc.write_text("".join(kept), encoding="utf-8")
            console.print(f"  [red]제거[/] ~/.bashrc 의 API 키 {len(lines) - len(kept)} 줄")
            console.print("  [dim]적용: 새 터미널을 열거나 source ~/.bashrc[/]")
        else:
            console.print("  [dim]~/.bashrc 에 제거할 API 키 없음[/]")
    except Exception as e:
        console.print(f"  [yellow]~/.bashrc 정리 실패: {e}[/]")
