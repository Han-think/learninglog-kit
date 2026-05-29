"""queue — 처리 대기 소스 우선순위 리포트."""

from __future__ import annotations

import csv
from typing import Any

from rich.console import Console
from rich.table import Table

from .config import resolve_path

console = Console()

PRIORITY = {"personal_note": 1, "chat_export": 2, "web_note": 3,
            "lecture": 4, "screenshot": 5}
ACTION   = {
    "personal_note": "extract + working_note 생성 가능",
    "chat_export":   "personal_notes 분리 후 처리",
    "web_note":      "내 해석 추가 필요",
    "lecture":       "internal-only — 개인 해석 노트 먼저",
    "screenshot":    "수동 검토 필요",
}


def run_queue(cfg: dict[str, Any]) -> None:
    registry = resolve_path(cfg, "registry", "01_registry/source_registry.csv")
    if not registry.exists():
        console.print("[red]source_registry.csv 없음.[/]")
        return

    with open(registry, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    pending = [r for r in rows if r.get("status") in ("registered", "new")]
    if not pending:
        console.print("[green]처리 대기 소스 없음.[/]")
        return

    # 정렬
    pending.sort(key=lambda r: (
        PRIORITY.get(r.get("source_type", ""), 99) * 10 +
        {"partial-public": 1, "public": 2, "internal-only": 3}.get(r.get("public_policy", ""), 4)
    ))

    table = Table(title=f"처리 대기 소스 ({len(pending)} 개)", show_lines=False)
    table.add_column("순위", style="dim", width=4)
    table.add_column("source_id",    style="cyan")
    table.add_column("type",         style="white")
    table.add_column("topic",        style="white")
    table.add_column("policy",       style="yellow")
    table.add_column("권장 행동",    style="green")

    for i, r in enumerate(pending[:15], 1):
        action = ACTION.get(r.get("source_type", ""), "수동 검토")
        table.add_row(
            str(i),
            r.get("source_id", ""),
            r.get("source_type", ""),
            r.get("topic", "")[:30],
            r.get("public_policy", ""),
            action,
        )

    console.print()
    console.print(table)
    console.print()
