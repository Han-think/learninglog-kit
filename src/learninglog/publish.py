"""publish — 04_blog_drafts 의 초안을 블로그로 발행.

config.yaml 의 blog 설정을 따른다:
    blog:
      platform: hugo | jekyll | none
      source_path: ../blog-source      # 블로그 소스 폴더
      content_subdir: content          # content 하위 폴더명 (hugo=content, jekyll=_posts 등)
      auto_build: true                 # hugo 빌드 실행
      auto_push: false                 # UI/CLI 에서 별도 git push 버튼 노출

안전장치:
  - draft: true → false 변환
  - source_id front matter 제거 (내부 추적용, 공개 금지)
  - ai_assisted: true 마킹 추가
  - git push 는 publish 와 분리 (명시 버튼/명령으로만 실행)
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
from .chunker import remove_extra_hugo_front_matter

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
        if sid and not _source_is_publishable(registry, sid):
            console.print(f"  [yellow]SKIP[/] {section}/{draft.name} (source policy blocks publish)")
            continue
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
                               cwd=blog_root, capture_output=True, text=True, timeout=120,
                               encoding="utf-8", errors="replace")
            if r.returncode == 0:
                console.print("[green]OK[/]")
            else:
                console.print(f"[red]실패[/]\n  {r.stderr[:200]}")
        except FileNotFoundError:
            console.print("[yellow]hugo 명령 없음 — 빌드 건너뜀[/]")
        except Exception as e:
            console.print(f"[red]오류[/] {e}")

    console.print("\n  [dim]git push 는 자동 실행하지 않습니다. UI 의 GitHub push 버튼 또는 learninglog push 를 사용하세요.[/]")

    console.print(f"\n  [bold green]발행 완료: {published} 개[/]\n")


def run_push(cfg: dict[str, Any]) -> None:
    """Explicit semi-automatic git add/commit/push for the configured blog repo."""
    blog = cfg.get("blog", {})
    source_path = blog.get("source_path", "")
    if not source_path:
        console.print("[yellow]blog.source_path 설정이 없습니다.[/]")
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
    if not (blog_root / ".git").exists():
        console.print(f"[red]Git 저장소가 아닙니다: {blog_root}[/]")
        return

    today = date.today().strftime("%Y-%m-%d")
    console.print(f"  git push 대상: [cyan]{blog_root}[/]")
    try:
        subprocess.run(["git", "add", "-A"], cwd=blog_root, check=True, capture_output=True, text=True)
        commit = subprocess.run(
            ["git", "commit", "-m", f"LearningLog publish ({today})"],
            cwd=blog_root,
            capture_output=True,
            text=True,
        )
        if commit.returncode != 0 and "nothing to commit" not in (commit.stdout + commit.stderr).lower():
            raise RuntimeError((commit.stderr or commit.stdout).strip())
        subprocess.run(["git", "push"], cwd=blog_root, check=True, capture_output=True, text=True)
        console.print("  [green]git push OK[/]")
    except Exception as e:
        console.print(f"  [red]git push 실패:[/] {e}")


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
    content = remove_extra_hugo_front_matter(content)
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

    # 본문에 LLM 이 실수로 남긴 내부 추적 메타 줄 제거 (공개 금지)
    # source_id / note_date / model / mode 와, 그 메타를 감싼 꼬리 '---' 구분선까지 정리
    INTERNAL_KEYS = ("source_id:", "note_date:", "model:", "mode:")
    clean_body = []
    for ln in body:
        s = ln.strip()
        if s.startswith("source_id:"):
            if not sid and "SRC-" in s:
                sid = s.split(":", 1)[1].strip()
            continue
        if any(s.startswith(k) for k in INTERNAL_KEYS):
            continue
        clean_body.append(ln)

    # 메타 제거 후 꼬리에 남은 빈 '---' 구분선/공백 줄 정리
    while clean_body and clean_body[-1].strip() in ("", "---"):
        clean_body.pop()

    result = "---\n" + "\n".join(fm) + "\n---\n" + "\n".join(clean_body) + "\n"
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


def _source_is_publishable(registry: Path, source_id: str) -> bool:
    if not registry.exists():
        return True
    with open(registry, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get("source_id") == source_id:
                return row.get("public_policy") in ("public", "partial-public")
    return True
