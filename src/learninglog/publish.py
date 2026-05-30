"""publish — 04_blog_drafts 의 초안을 블로그로 발행.

config.yaml 의 blog 설정을 따른다:
    blog:
      platform: hugo | jekyll | none
      source_path: ../blog-source      # 블로그 소스 폴더
      content_subdir: content          # content 하위 폴더명 (hugo=content, jekyll=_posts 등)
      auto_build: true                 # hugo 빌드 실행
      auto_push: false                 # git add/commit/push 실행

안전장치:
  - draft: true → false 변환
  - source_id front matter 제거 (내부 추적용, 공개 금지)
  - ai_assisted: true 마킹 추가
  - auto_push 기본 false (명시적으로 켜야 푸시)
"""

from __future__ import annotations

import csv
import shutil
import subprocess
from datetime import date
from pathlib import Path
from typing import Any

from rich.console import Console

from .config import resolve_path, get

console = Console()


def run_publish(cfg: dict[str, Any], source_id: str = "", yes: bool = False) -> None:
    drafts_dir  = resolve_path(cfg, "drafts", "04_blog_drafts")
    registry    = resolve_path(cfg, "registry", "01_registry/source_registry.csv")
    today       = date.today().strftime("%Y-%m-%d")

    blog        = cfg.get("blog", {})
    platform    = blog.get("platform", "none")
    source_path = blog.get("source_path", "")
    content_sub = blog.get("content_subdir", "content")
    auto_build  = blog.get("auto_build", True)
    auto_push   = blog.get("auto_push", False)

    if platform == "none" or not source_path:
        console.print("[yellow]blog 설정이 없습니다.[/]")
        console.print("config.yaml 의 blog.platform 과 blog.source_path 를 설정하세요.")
        console.print("[dim]docs/llm-providers.md 및 README 참고[/]")
        return

    blog_root = Path(source_path)
    if not blog_root.is_absolute():
        from .config import find_config
        cf = find_config()
        root = cf.parent.parent if cf else Path.cwd()
        blog_root = (root / source_path).resolve()

    if not blog_root.exists():
        console.print(f"[red]블로그 소스 폴더 없음: {blog_root}[/]")
        return

    # 발행 대상 수집
    if source_id:
        drafts = [p for p in drafts_dir.rglob("*.md")
                  if _read_source_id(p) == source_id]
    else:
        drafts = sorted(drafts_dir.rglob("*.md"))

    if not drafts:
        console.print("[yellow]발행할 초안이 없습니다. extract 를 먼저 실행하세요.[/]")
        return

    console.print(f"\n  발행 대상: [cyan]{len(drafts)}[/] 개  →  [cyan]{blog_root}[/]\n")

    published = 0
    for draft in drafts:
        section = draft.parent.name  # 04_blog_drafts/{section}/file.md
        dest_dir = blog_root / content_sub / section
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / draft.name

        raw = draft.read_text(encoding="utf-8")
        processed, sid = _process_front_matter(raw)
        dest.write_text(processed, encoding="utf-8")
        console.print(f"  [green]복사[/] {section}/{draft.name}")

        if sid:
            _update_status(registry, sid, "published")
        published += 1

    if published == 0:
        return

    # Hugo 빌드
    if auto_build and platform == "hugo":
        console.print("\n  Hugo 빌드 중...", end=" ")
        try:
            r = subprocess.run(["hugo", "--logLevel", "warn"],
                               cwd=blog_root, capture_output=True, text=True, timeout=120)
            if r.returncode == 0:
                console.print("[green]OK[/]")
            else:
                console.print(f"[red]실패[/]\n  {r.stderr[:200]}")
        except FileNotFoundError:
            console.print("[yellow]hugo 명령 없음 — 빌드 건너뜀[/]")
        except Exception as e:
            console.print(f"[red]오류[/] {e}")

    # git push
    if auto_push:
        console.print("  git push 중...", end=" ")
        try:
            subprocess.run(["git", "add", "-A"], cwd=blog_root, check=True, capture_output=True)
            subprocess.run(["git", "commit", "-m", f"LearningLog publish: {published} posts ({today})"],
                          cwd=blog_root, capture_output=True)
            subprocess.run(["git", "push"], cwd=blog_root, check=True, capture_output=True)
            console.print("[green]OK[/]")
        except Exception as e:
            console.print(f"[yellow]git push 건너뜀/실패: {e}[/]")
            console.print("  [dim]수동으로 블로그 폴더에서 git push 하세요.[/]")
    else:
        console.print("\n  [dim]auto_push=false — git push 안 함. 블로그 폴더에서 직접 푸시하세요.[/]")

    console.print(f"\n  [bold green]발행 완료: {published} 개[/]\n")


def _read_source_id(path: Path) -> str:
    try:
        for line in path.read_text(encoding="utf-8").splitlines()[:15]:
            if line.startswith("source_id:"):
                return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return ""


def _process_front_matter(content: str, model: str = "local-llm") -> tuple[str, str]:
    """draft→false, source_id 제거, ai_assisted 마킹. (처리된내용, source_id) 반환."""
    if not content.startswith("---"):
        return content, ""

    lines = content.split("\n")
    fm_end = -1
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            fm_end = i
            break
    if fm_end == -1:
        return content, ""

    fm, body = [], lines[fm_end + 1:]
    sid = ""
    has_ai = False
    for ln in lines[1:fm_end]:
        if ln.startswith("draft:"):
            fm.append("draft: false")
        elif ln.startswith("source_id:"):
            sid = ln.split(":", 1)[1].strip()
            # 제거 (공개 금지)
        else:
            if ln.startswith("ai_assisted:"):
                has_ai = True
            fm.append(ln)
    if not has_ai:
        fm.append("ai_assisted: true")

    result = "---\n" + "\n".join(fm) + "\n---\n" + "\n".join(body)
    return result, sid


def _update_status(registry: Path, source_id: str, new_status: str) -> None:
    if not registry.exists():
        return
    with open(registry, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        return
    for row in rows:
        if row.get("source_id") == source_id:
            row["status"] = new_status
    with open(registry, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
