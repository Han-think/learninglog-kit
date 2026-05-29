"""intake — 00_inbox 스캔 후 source_registry.csv 에 등록."""

from __future__ import annotations

import csv
import hashlib
import re
from datetime import date
from pathlib import Path
from typing import Any

from rich.console import Console

from .config import resolve_path

console = Console()

SUBFOLDERS = {
    "lectures":      ("lecture",       "internal-only"),
    "personal_notes": ("personal_note", "partial-public"),
    "chat_exports":  ("chat_export",   "partial-public"),
    "web_notes":     ("web_note",      "partial-public"),
    "screenshots":   ("screenshot",    "internal-only"),
}

ALLOWED_EXTENSIONS = {".pdf", ".md", ".txt", ".png", ".jpg", ".jpeg", ".webp"}
SKIP_PATTERNS      = re.compile(r"(_intake\.md|_INDEX\.md)$", re.IGNORECASE)


def run_intake(cfg: dict[str, Any], dry_run: bool = False) -> None:
    root     = resolve_path(cfg, "inbox", "00_inbox").parent
    inbox    = resolve_path(cfg, "inbox", "00_inbox")
    registry = resolve_path(cfg, "registry", "01_registry/source_registry.csv")

    if not registry.exists():
        console.print("[red]source_registry.csv 없음. learninglog init 을 먼저 실행하세요.[/]")
        return

    # 기존 등록 경로 로드
    registered: set[str] = set()
    with open(registry, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            registered.add(row["source_path"].strip())

    today     = date.today().strftime("%Y-%m-%d")
    today_key = date.today().strftime("%Y%m%d")

    # 오늘 날짜 최대 NNN 탐색
    max_seq = 0
    prefix  = f"SRC-{today_key}-"
    with open(registry, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            sid = row.get("source_id", "")
            if sid.startswith(prefix):
                try:
                    seq = int(sid.split("-")[-1])
                    max_seq = max(max_seq, seq)
                except ValueError:
                    pass

    new_rows: list[dict] = []

    for subfolder, (src_type, policy) in SUBFOLDERS.items():
        folder = inbox / subfolder
        if not folder.exists():
            continue

        files = sorted(folder.iterdir())
        console.print(f"  [dim][폴더][/] {subfolder}/  →  파일 {len([f for f in files if f.is_file()])} 개")

        for fp in files:
            if not fp.is_file():
                continue
            if fp.suffix.lower() not in ALLOWED_EXTENSIONS:
                continue
            if SKIP_PATTERNS.search(fp.name):
                console.print(f"  [dim][SKIP][/]  {fp.name}  (제외 패턴)")
                continue

            rel = fp.relative_to(root).as_posix()
            if rel in registered:
                console.print(f"  [dim][SKIP][/]  {rel}  (이미 등록됨)")
                continue

            max_seq += 1
            src_id  = f"SRC-{today_key}-{max_seq:03d}"
            topic   = _infer_topic(fp.stem)
            sha256  = _sha256_short(fp)

            row = {
                "source_id":    src_id,
                "source_path":  rel,
                "source_type":  src_type,
                "date_added":   today,
                "status":       "registered",
                "topic":        topic,
                "language":     cfg.get("project", {}).get("language", "ko"),
                "public_policy": policy,
                "notes":        f"auto-registered from {subfolder} sha256:{sha256}",
            }
            new_rows.append(row)
            console.print(f"  [green][NEW][/]   {src_id}  {rel}")

    if not new_rows:
        console.print("\n  신규 등록 없음 (모두 이미 등록됨)")
        return

    if dry_run:
        console.print(f"\n  [yellow]--dry-run:[/] 실제 등록 건너뜀. {len(new_rows)} 개 감지됨.")
        return

    # CSV 추가
    fieldnames = ["source_id","source_path","source_type","date_added",
                  "status","topic","language","public_policy","notes"]
    with open(registry, "a", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        for row in new_rows:
            writer.writerow(row)

    console.print(f"\n  [bold green]신규 등록: {len(new_rows)} 개[/]")


def _infer_topic(stem: str) -> str:
    s = re.sub(r"PN_|SRC-\d{8}-\d+", "", stem)
    s = re.sub(r"\d{4}-\d{2}-\d{2}|\d{8}", "", s)
    s = re.sub(r"[\[\]()_\s]+", "-", s).strip("-").lower()
    return s if len(s) >= 3 else "unclassified"


def _sha256_short(fp: Path) -> str:
    try:
        h = hashlib.sha256(fp.read_bytes()).hexdigest()
        return h[:8].upper()
    except Exception:
        return "00000000"
