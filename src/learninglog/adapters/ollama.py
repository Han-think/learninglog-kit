"""Ollama 어댑터 — 로컬 모델 (무료, 프라이버시)."""

from __future__ import annotations

import httpx

from .base import LLMAdapter


class OllamaAdapter(LLMAdapter):
    """
    설정 예시 (config.yaml):
        llm:
          provider: ollama
          ollama:
            host: http://127.0.0.1:11434
            model: llama3.2:3b
            num_ctx: 4096        # Ollama 실행 컨텍스트 (GPU VRAM 여유에 맞게 조정)
    """

    def __init__(self, host: str = "http://127.0.0.1:11434", model: str = "llama3.2:3b",
                 num_ctx: int = 4096):
        self.host    = host.rstrip("/")
        self.model   = model
        self.num_ctx = num_ctx  # API 호출 시 명시 — 모델 감지 불필요

    @property
    def provider_name(self) -> str:
        return "ollama"

    def health_check(self) -> bool:
        try:
            r = httpx.get(f"{self.host}/", timeout=3)
            return r.status_code == 200
        except Exception:
            return False

    def safe_max_chars(self) -> int:
        """num_ctx 기반 안전 청크 문자 수 계산.

        한국어 LLaMA 실측 ~3토큰/자, num_predict=512 출력 예약, 지시문 300토큰.
        num_ctx=4096 → 985자  /  num_ctx=2048 → 371자
        """
        chars = int((self.num_ctx - 512 - 300) / 3.0 * 0.9)
        return max(200, min(5000, chars))

    def generate(self, prompt: str, num_predict: int = 512) -> str:
        payload = {
            "model":   self.model,
            "prompt":  prompt,
            "stream":  False,
            "options": {"num_predict": num_predict, "num_ctx": self.num_ctx},
        }
        r = httpx.post(
            f"{self.host}/api/generate",
            json=payload,
            timeout=600,
        )
        r.raise_for_status()
        return r.json()["response"]
