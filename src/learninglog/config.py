"""config.yaml 로더 — 프로젝트 설정 관리."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import yaml


CONFIG_FILE = ".learninglog/config.yaml"


def find_config(start: Path | None = None) -> Path | None:
    """현재 폴더에서 위로 올라가며 config.yaml 탐색."""
    current = start or Path.cwd()
    for folder in [current, *current.parents]:
        candidate = folder / CONFIG_FILE
        if candidate.exists():
            return candidate
    return None


def load_config(config_path: Path | None = None) -> dict[str, Any]:
    """config.yaml 읽기. 없으면 빈 dict 반환."""
    path = config_path or find_config()
    if path is None:
        return {}
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def get(cfg: dict, *keys: str, default: Any = None) -> Any:
    """중첩 dict 안전 접근. get(cfg, 'llm', 'provider', default='none')"""
    node = cfg
    for key in keys:
        if not isinstance(node, dict):
            return default
        node = node.get(key, default)
    return node


def resolve_path(cfg: dict, key: str, fallback: str) -> Path:
    """config 의 경로 값을 절대 경로로 변환."""
    raw = get(cfg, "paths", key, default=fallback)
    p = Path(raw)
    if not p.is_absolute():
        config_file = find_config()
        root = config_file.parent.parent if config_file else Path.cwd()
        p = root / p
    return p
