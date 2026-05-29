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
    """

    def __init__(self, host: str = "http://127.0.0.1:11434", model: str = "llama3.2:3b"):
        self.host  = host.rstrip("/")
        self.model = model

    @property
    def provider_name(self) -> str:
        return "ollama"

    def health_check(self) -> bool:
        try:
            r = httpx.get(f"{self.host}/", timeout=3)
            return r.status_code == 200
        except Exception:
            return False

    def generate(self, prompt: str) -> str:
        payload = {"model": self.model, "prompt": prompt, "stream": False}
        r = httpx.post(
            f"{self.host}/api/generate",
            json=payload,
            timeout=300,
        )
        r.raise_for_status()
        return r.json()["response"]
