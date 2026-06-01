"""intake - scan 00_inbox and register new sources safely."""

from __future__ import annotations

import csv
import hashlib
import json
import re
import shutil
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any

from rich.console import Console

from .config import resolve_path

console = Console()

REGISTRY_FIELDS = [
    "source_id",
    "source_path",
    "file_name",
    "file_path",
    "file_type",
    "source_type",
    "source_category",
    "date_added",
    "created_at",
    "status",
    "topic",
    "language",
    "public_policy",
    "hash",
    "notes",
]

LEGACY_FIELDS = [
    "source_id",
    "source_path",
    "source_type",
    "date_added",
    "status",
    "topic",
    "language",
    "public_policy",
    "notes",
]

ALLOWED_EXTENSIONS = {
    ".pdf",
    ".ipynb",
    ".md",
    ".txt",
    ".zip",
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}
SKIP_PATTERNS = re.compile(r"(_intake\.md|_INDEX\.md)$", re.IGNORECASE)


def run_intake(cfg: dict[str, Any], dry_run: bool = False) -> None:
    root = resolve_path(cfg, "inbox", "00_inbox").parent
    inbox = resolve_path(cfg, "inbox", "00_inbox")
    registry = resolve_path(cfg, "registry", "01_registry/source_registry.csv")
    reports_dir = resolve_path(cfg, "reports", "09_reports")

    if not registry.exists():
        console.print("[red]source_registry.csv 없음. learninglog init 을 먼저 실행하세요.[/]")
        return

    rows = _load_and_upgrade_registry(registry, root, dry_run=dry_run)
    known_paths = {r.get("source_path", "").strip() for r in rows if r.get("source_path")}
    known_hashes = {r.get("hash", "").strip() for r in rows if r.get("hash")}

    now = datetime.now()
    today = now.strftime("%Y-%m-%d")
    today_key = now.strftime("%Y%m%d")
    created_at = now.isoformat(timespec="seconds")
    max_seq = _max_sequence(rows, today_key)

    candidates = _collect_candidates(inbox)
    console.print(f"\n  intake scan: [cyan]{len(candidates)}[/] candidate files\n")

    new_rows: list[dict[str, str]] = []
    duplicates: list[dict[str, str]] = []
    skipped: list[dict[str, str]] = []
    errors: list[str] = []
    ext_counts: Counter[str] = Counter()
    category_counts: Counter[str] = Counter()

    for idx, fp in enumerate(candidates, 1):
        rel = _rel_path(fp, root)
        ext_counts[fp.suffix.lower() or "(none)"] += 1

        try:
            file_hash = _sha256(fp)
            classification = _classify_file(fp, inbox)
            category_counts[classification["source_category"]] += 1

            if rel in known_paths:
                skipped.append({"path": rel, "reason": "already registered path"})
                console.print(f"  [{idx}/{len(candidates)}] [dim]skipped[/] {rel} (already registered)")
                continue

            if file_hash in known_hashes:
                duplicates.append({"path": rel, "reason": "duplicate hash", "hash": file_hash[:12]})
                console.print(f"  [{idx}/{len(candidates)}] [yellow]duplicate skipped[/] {rel} hash={file_hash[:12]}")
                continue

            max_seq += 1
            src_id = f"SRC-{today_key}-{max_seq:03d}"
            notes = _build_notes(fp, classification, file_hash)
            row = {
                "source_id": src_id,
                "source_path": rel,
                "file_name": fp.name,
                "file_path": rel,
                "file_type": fp.suffix.lower().lstrip("."),
                "source_type": classification["source_type"],
                "source_category": classification["source_category"],
                "date_added": today,
                "created_at": created_at,
                "status": "registered",
                "topic": _infer_topic(fp.stem),
                "language": cfg.get("project", {}).get("language", "ko"),
                "public_policy": classification["public_policy"],
                "hash": file_hash,
                "notes": notes,
            }
            new_rows.append(row)
            known_paths.add(rel)
            known_hashes.add(file_hash)
            console.print(
                f"  [{idx}/{len(candidates)}] [green]registered[/] {src_id} "
                f"{classification['source_category']} {rel}"
            )
        except Exception as exc:
            msg = f"{rel}: {exc}"
            errors.append(msg)
            console.print(f"  [{idx}/{len(candidates)}] [red]error[/] {msg}")

    if dry_run:
        _print_summary(new_rows, duplicates, skipped, errors, ext_counts, category_counts, dry_run=True)
        return

    if new_rows:
        with open(registry, "a", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=REGISTRY_FIELDS)
            for row in new_rows:
                writer.writerow(row)

    report_path = _write_report(
        reports_dir,
        new_rows,
        duplicates,
        skipped,
        errors,
        ext_counts,
        category_counts,
        dry_run=False,
    )
    _print_summary(new_rows, duplicates, skipped, errors, ext_counts, category_counts, dry_run=False)
    console.print(f"  [dim]report:[/] {report_path}")


def _load_and_upgrade_registry(registry: Path, root: Path, dry_run: bool) -> list[dict[str, str]]:
    with open(registry, encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        rows = [dict(r) for r in reader]
        fields = list(reader.fieldnames or [])

    if fields == REGISTRY_FIELDS:
        return rows

    upgraded = [_upgrade_row(row, root) for row in rows]
    if dry_run:
        console.print("  [yellow]registry schema upgrade needed[/] (--dry-run: not writing)")
        return upgraded

    backup_dir = registry.parent.parent / "07_archive" / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = backup_dir / f"source_registry_pre_v0_5_{stamp}.csv"
    shutil.copy2(registry, backup)

    with open(registry, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=REGISTRY_FIELDS)
        writer.writeheader()
        writer.writerows(upgraded)
    console.print(f"  [cyan]registry upgraded[/] backup={backup}")
    return upgraded


def _upgrade_row(row: dict[str, str], root: Path) -> dict[str, str]:
    source_path = row.get("source_path", "").strip()
    fp = root / Path(*source_path.split("/")) if source_path else Path("")
    file_name = fp.name if source_path else ""
    file_type = fp.suffix.lower().lstrip(".") if source_path else ""
    category = row.get("source_category") or _legacy_category(row.get("source_type", ""), file_type)
    policy = row.get("public_policy") or _policy_for_category(category)
    file_hash = row.get("hash", "")
    if not file_hash and fp.exists() and fp.is_file():
        file_hash = _sha256(fp)
    return {
        "source_id": row.get("source_id", ""),
        "source_path": source_path,
        "file_name": row.get("file_name") or file_name,
        "file_path": row.get("file_path") or source_path,
        "file_type": row.get("file_type") or file_type,
        "source_type": row.get("source_type") or category,
        "source_category": category,
        "date_added": row.get("date_added", ""),
        "created_at": row.get("created_at") or row.get("date_added", ""),
        "status": row.get("status", ""),
        "topic": row.get("topic", ""),
        "language": row.get("language", "ko"),
        "public_policy": policy,
        "hash": file_hash,
        "notes": row.get("notes", ""),
    }


def _collect_candidates(inbox: Path) -> list[Path]:
    if not inbox.exists():
        return []
    files = []
    for fp in inbox.rglob("*"):
        if not fp.is_file():
            continue
        if fp.suffix.lower() not in ALLOWED_EXTENSIONS:
            continue
        if SKIP_PATTERNS.search(fp.name):
            continue
        files.append(fp)
    return sorted(files, key=lambda p: _rel_path(p, inbox))


def _classify_file(fp: Path, inbox: Path) -> dict[str, str]:
    ext = fp.suffix.lower()
    name = fp.name
    parent = fp.parent.name.lower()

    if ext == ".pdf":
        if name.startswith("[강의자료]") or name.startswith("[수업자료]") or parent == "lectures":
            return _class("lecture", "lecture_pdf", "internal-only")
        return _class("document", "pdf_source", "internal-only")
    if ext == ".ipynb":
        return _class("practice", "practice_notebook", "private")
    if ext == ".zip":
        return _class("archive", "archive_zip", "internal-only")
    if ext in IMAGE_EXTENSIONS:
        return _class("image", "screenshot", "internal-only")
    if ext in (".md", ".txt"):
        if re.match(r"^PN[_-]", name, re.IGNORECASE) or parent == "personal_notes":
            return _class("personal_note", "personal_note", "partial-public")
        if re.match(r"^SRC-\d{8}-\d{3}", name, re.IGNORECASE):
            return _class("intake_note", "intake_note", "partial-public")
        if parent == "chat_exports":
            return _class("chat_export", "chat_export", "partial-public")
        if parent == "web_notes":
            return _class("web_note", "web_note", "partial-public")
        if parent == "lectures":
            return _class("lecture", "lecture_markdown", "internal-only")
        return _class("markdown", "source_markdown", "partial-public")
    return _class("unknown", "unknown", "internal-only")


def _class(source_type: str, source_category: str, public_policy: str) -> dict[str, str]:
    return {
        "source_type": source_type,
        "source_category": source_category,
        "public_policy": public_policy,
    }


def _build_notes(fp: Path, classification: dict[str, str], file_hash: str) -> str:
    parts = [
        f"auto-registered; category={classification['source_category']}",
        f"sha256={file_hash}",
    ]
    if fp.suffix.lower() == ".ipynb":
        meta = _ipynb_metadata(fp)
        parts.append(
            "ipynb:"
            f"code_cells={meta['code_cells']};"
            f"markdown_cells={meta['markdown_cells']};"
            f"headings={'; '.join(meta['headings'][:5]) or 'none'};"
            f"tags={', '.join(meta['tags']) or 'none'}"
        )
    return " | ".join(parts)


def _ipynb_metadata(fp: Path) -> dict[str, Any]:
    meta = {"code_cells": 0, "markdown_cells": 0, "headings": [], "tags": []}
    try:
        data = json.loads(fp.read_text(encoding="utf-8"))
        headings: list[str] = []
        tags: set[str] = set()
        for cell in data.get("cells", []):
            cell_type = cell.get("cell_type")
            source = "".join(cell.get("source", []))
            if cell_type == "code":
                meta["code_cells"] += 1
                for token in ("python", "loop", "list", "function", "pandas", "colab"):
                    if token in source.lower():
                        tags.add(token)
            elif cell_type == "markdown":
                meta["markdown_cells"] += 1
                for line in source.splitlines():
                    if line.lstrip().startswith("#"):
                        headings.append(line.lstrip("# ").strip())
        meta["headings"] = headings
        meta["tags"] = sorted(tags)
    except Exception as exc:
        meta["headings"] = [f"metadata read failed: {exc}"]
    return meta


def _write_report(
    reports_dir: Path,
    new_rows: list[dict[str, str]],
    duplicates: list[dict[str, str]],
    skipped: list[dict[str, str]],
    errors: list[str],
    ext_counts: Counter[str],
    category_counts: Counter[str],
    dry_run: bool,
) -> Path:
    reports_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    path = reports_dir / f"RUN_{stamp}_intake_report.md"
    path.write_text(
        _render_report(new_rows, duplicates, skipped, errors, ext_counts, category_counts, dry_run),
        encoding="utf-8",
    )
    return path


def _render_report(
    new_rows: list[dict[str, str]],
    duplicates: list[dict[str, str]],
    skipped: list[dict[str, str]],
    errors: list[str],
    ext_counts: Counter[str],
    category_counts: Counter[str],
    dry_run: bool,
) -> str:
    lines = [
        "# LearningLog Intake Report",
        "",
        f"- Mode: {'dry-run' if dry_run else 'write'}",
        f"- New files registered: {len(new_rows)}",
        f"- Duplicate files skipped: {len(duplicates)}",
        f"- Already registered skipped: {len(skipped)}",
        f"- Errors: {len(errors)}",
        "",
        "## Extension Counts",
        "",
    ]
    lines += [f"- `{k}`: {v}" for k, v in sorted(ext_counts.items())] or ["- none"]
    lines += ["", "## Category Counts", ""]
    lines += [f"- `{k}`: {v}" for k, v in sorted(category_counts.items())] or ["- none"]
    lines += ["", "## Registered Sources", ""]
    lines += [
        f"- `{r['source_id']}` `{r['source_category']}` `{r['public_policy']}` {r['source_path']}"
        for r in new_rows
    ] or ["- none"]
    lines += ["", "## Duplicates", ""]
    lines += [f"- `{d['hash']}` {d['path']}" for d in duplicates] or ["- none"]
    lines += ["", "## Errors", ""]
    lines += [f"- {e}" for e in errors] or ["- none"]
    lines.append("")
    return "\n".join(lines)


def _print_summary(
    new_rows: list[dict[str, str]],
    duplicates: list[dict[str, str]],
    skipped: list[dict[str, str]],
    errors: list[str],
    ext_counts: Counter[str],
    category_counts: Counter[str],
    dry_run: bool,
) -> None:
    console.print("\n  [bold]intake summary[/]")
    console.print(f"  mode: {'dry-run' if dry_run else 'write'}")
    console.print(f"  new={len(new_rows)} duplicate={len(duplicates)} skipped={len(skipped)} errors={len(errors)}")
    console.print("  extensions: " + (", ".join(f"{k}:{v}" for k, v in sorted(ext_counts.items())) or "none"))
    console.print("  categories: " + (", ".join(f"{k}:{v}" for k, v in sorted(category_counts.items())) or "none"))


def _max_sequence(rows: list[dict[str, str]], today_key: str) -> int:
    prefix = f"SRC-{today_key}-"
    max_seq = 0
    for row in rows:
        sid = row.get("source_id", "")
        if sid.startswith(prefix):
            try:
                max_seq = max(max_seq, int(sid.split("-")[-1]))
            except ValueError:
                pass
    return max_seq


def _legacy_category(source_type: str, file_type: str) -> str:
    if source_type == "personal_note":
        return "personal_note"
    if source_type == "chat_export":
        return "chat_export"
    if source_type == "web_note":
        return "web_note"
    if source_type == "screenshot":
        return "screenshot"
    if source_type == "lecture" and file_type == "pdf":
        return "lecture_pdf"
    return source_type or "unknown"


def _policy_for_category(category: str) -> str:
    if category in ("personal_note", "chat_export", "web_note", "intake_note", "source_markdown"):
        return "partial-public"
    if category == "practice_notebook":
        return "private"
    return "internal-only"


def _infer_topic(stem: str) -> str:
    s = re.sub(r"PN_|SRC-\d{8}-\d+", "", stem, flags=re.IGNORECASE)
    s = re.sub(r"\d{4}-\d{2}-\d{2}|\d{8}", "", s)
    s = re.sub(r"[\[\](){}\s_]+", "-", s).strip("-").lower()
    s = re.sub(r"-{2,}", "-", s)
    return s if len(s) >= 3 else "unclassified"


def _sha256(fp: Path) -> str:
    h = hashlib.sha256()
    with fp.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def _rel_path(fp: Path, root: Path) -> str:
    try:
        return fp.relative_to(root).as_posix()
    except ValueError:
        return fp.as_posix()
