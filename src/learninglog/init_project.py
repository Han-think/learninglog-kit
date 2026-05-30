"""learninglog init — 새 프로젝트 폴더 구조 생성."""

from __future__ import annotations

import shutil
from pathlib import Path

from rich.console import Console
from rich.tree import Tree

console = Console()

FOLDERS = [
    "00_inbox/lectures",
    "00_inbox/personal_notes",
    "00_inbox/chat_exports",
    "00_inbox/web_notes",
    "00_inbox/screenshots",
    "01_registry",
    "02_extracted/concept_extracts",
    "02_extracted/lecture_summaries",
    "03_working_notes/daily_logs",
    "03_working_notes/concept_notes",
    "04_blog_drafts/learning",
    "04_blog_drafts/practice",
    "04_blog_drafts/projects",
    "04_blog_drafts/goals",
    "05_ready_to_publish",
    "06_published",
    "07_archive/backups",
    "08_templates",
    "09_reports",
    ".learninglog",
]

REGISTRY_HEADER = (
    "source_id,source_path,source_type,date_added,status,"
    "topic,language,public_policy,notes\n"
)

CONFIG_TEMPLATE_PATH = Path(__file__).parent.parent.parent / "templates" / "config.yaml"


def init_project(target: Path) -> None:
    """target 폴더에 LearningLog 구조 생성."""

    if not target.exists():
        target.mkdir(parents=True)
        console.print(f"[green]폴더 생성:[/] {target}")

    # 디렉토리 생성
    for folder in FOLDERS:
        d = target / folder
        d.mkdir(parents=True, exist_ok=True)

    # source_registry.csv 헤더 생성
    registry = target / "01_registry" / "source_registry.csv"
    if not registry.exists():
        registry.write_text(REGISTRY_HEADER, encoding="utf-8")

    # config.yaml 복사
    config_dest = target / ".learninglog" / "config.yaml"
    if not config_dest.exists():
        if CONFIG_TEMPLATE_PATH.exists():
            shutil.copy(CONFIG_TEMPLATE_PATH, config_dest)
        else:
            config_dest.write_text(_default_config(), encoding="utf-8")

    # 결과 트리 출력
    tree = Tree(f"[bold cyan]{target.name}/[/]")
    for folder in ["00_inbox", "01_registry", "02_extracted",
                   "03_working_notes", "04_blog_drafts", ".learninglog"]:
        tree.add(f"[dim]{folder}/[/]")
    tree.add("[dim]...[/]")
    console.print(tree)

    console.print()
    console.print("[bold green]폴더 구조 생성 완료![/]")
    console.print(f"  설정 파일: [cyan]{config_dest}[/]")
    console.print()

    # 대화형 설정 마법사 실행
    from .setup_wizard import run_wizard
    run_wizard(config_dest)


def _default_config() -> str:
    return """\
# learninglog-kit 설정 파일
# 자세한 내용: https://github.com/your-repo/learninglog-kit/docs/llm-providers.md

project:
  name: "My Learning Log"
  language: "ko"          # 기본 언어

paths:
  inbox:   "00_inbox"
  registry: "01_registry/source_registry.csv"
  extracted: "02_extracted"
  working:   "03_working_notes"
  drafts:    "04_blog_drafts"
  reports:   "09_reports"

# ─── LLM 설정 ─────────────────────────────────────────
# provider: ollama | gemini | groq | claude | openai | none
#
# 무료 옵션:
#   gemini — Google AI Studio (구글 계정으로 무료 발급)
#   groq   — Groq Console (무료 가입, 초고속)
#   ollama — 로컬 실행 (완전 무료, 프라이버시)
#
# 유료 옵션:
#   claude — Anthropic API
#   openai — OpenAI API
# ────────────────────────────────────────────────────────
llm:
  provider: "none"         # 아래 중 하나로 변경하세요

  ollama:
    host:  "http://127.0.0.1:11434"
    model: "llama3.2:3b"

  gemini:
    api_key: ""            # 또는 환경변수 GEMINI_API_KEY
    model:   "gemini-1.5-flash"

  groq:
    api_key: ""            # 또는 환경변수 GROQ_API_KEY
    model:   "llama-3.1-8b-instant"

  claude:
    api_key: ""            # 또는 환경변수 ANTHROPIC_API_KEY
    model:   "claude-haiku-4-5"

  openai:
    api_key: ""            # 또는 환경변수 OPENAI_API_KEY
    model:   "gpt-4o-mini"

# ─── 블로그 연동 (선택) ──────────────────────────────────
blog:
  platform: "none"         # hugo | jekyll | none
  source_path: "../blog-source"
  auto_push: false         # true 로 바꾸면 승인 후 자동 git push
"""
