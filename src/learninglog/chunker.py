"""텍스트 청킹 + 청크별 LLM 처리 + 병합 유틸리티.

컨텍스트 한계가 있는 모델(2048 토큰 등)에서
긴 소스를 분할 처리한 뒤 하나로 합친다.
"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .adapters.base import LLMAdapter


# 기본값: 한국어 기준 2048 토큰 모델에서 안전한 문자 수
# 한국어 ~1.5토큰/자, 지시문 ~300토큰 → 남은 토큰 ~1748 → ~1165자
# 여유 있게 1500자 기본값
DEFAULT_MAX_CHARS = 1500


def split_into_chunks(text: str, max_chars: int = DEFAULT_MAX_CHARS) -> list[str]:
    """빈 줄 기준으로 단락 분리 후 max_chars 이하로 청킹."""
    paragraphs = re.split(r"\n\s*\n", text)
    chunks: list[str] = []
    current = ""

    for para in paragraphs:
        para = para.strip()
        if not para:
            continue

        candidate = (current + "\n\n" + para).strip() if current else para

        if len(candidate) > max_chars and current:
            chunks.append(current.strip())
            current = para
        else:
            current = candidate

    if current.strip():
        chunks.append(current.strip())

    # 단락 자체가 max_chars 초과하는 경우 강제 분할
    result: list[str] = []
    for chunk in chunks:
        if len(chunk) <= max_chars:
            result.append(chunk)
        else:
            pos = 0
            while pos < len(chunk):
                result.append(chunk[pos : pos + max_chars])
                pos += max_chars

    return result if result else [text]


def generate_chunked(
    adapter: "LLMAdapter",
    instruction: str,
    body: str,
    max_chars: int = DEFAULT_MAX_CHARS,
    verbose: bool = True,
) -> str:
    """
    body 가 max_chars 이하이면 바로 처리.
    초과하면 청크 분할 → 각 청크 처리 → 병합 패스.

    Args:
        adapter:     LLM 어댑터
        instruction: 고정 지시문 (프롬프트 템플릿, body 제외)
        body:        처리할 소스 본문
        max_chars:   청크당 최대 문자 수
        verbose:     진행 상황 출력 여부
    """
    # 짧으면 바로 처리
    if len(body) <= max_chars:
        return adapter.generate(instruction + "\n---\n" + body)

    chunks = split_into_chunks(body, max_chars)

    if verbose:
        print(f"      청킹: {len(chunks)} 파트 분할 (각 ~{max_chars}자)")

    partials: list[str] = []
    for i, chunk in enumerate(chunks, 1):
        chunk_instruction = instruction + f"\n(파트 {i}/{len(chunks)} — 이 부분만 처리)"
        if verbose:
            print(f"      파트 {i}/{len(chunks)} ... ", end="", flush=True)
        partial = adapter.generate(chunk_instruction + "\n---\n" + chunk)
        partials.append(partial)
        if verbose:
            print("OK")

    # 청크가 1개였다면 그대로 반환
    if len(partials) == 1:
        return partials[0]

    # 병합 — LLM 재호출 없이 직접 연결 (merge pass도 토큰 한계에 걸리므로)
    if verbose:
        print("      결과 연결 중 ... ", end="", flush=True)

    merged = "\n\n---\n\n".join(partials)

    if verbose:
        print("OK")

    return merged
