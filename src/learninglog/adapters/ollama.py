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
            num_predict: 2048    # 한 번에 생성할 최대 출력 토큰 (글 잘림 방지)
    """

    def __init__(self, host: str = "http://127.0.0.1:11434", model: str = "llama3.2:3b",
                 num_ctx: int = 4096, num_predict: int = 2048):
        self.host        = host.rstrip("/")
        self.model       = model
        self.num_ctx     = num_ctx      # API 호출 시 명시 — 모델 감지 불필요
        # 출력 토큰 한도. num_ctx 보다 클 수 없음 (입력+출력이 컨텍스트 안에 들어가야 함)
        self.num_predict = max(256, min(num_predict, num_ctx - 256))

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

        한국어 LLaMA 실측 ~3토큰/자, num_predict 만큼 출력 예약, 지시문 300토큰.
        입력에 쓸 수 있는 토큰 = num_ctx - num_predict - 300.
        예) num_ctx=4096, num_predict=2048 → 약 549자
            num_ctx=8192, num_predict=2048 → 약 1762자
        """
        input_tokens = self.num_ctx - self.num_predict - 300
        chars = int(input_tokens / 3.0 * 0.9)
        return max(200, min(5000, chars))

    def generate(self, prompt: str, num_predict: int | None = None) -> str:
        payload = {
            "model":   self.model,
            "prompt":  prompt,
            "stream":  False,
            "options": {
                "num_predict": num_predict if num_predict is not None else self.num_predict,
                "num_ctx": self.num_ctx,
            },
        }
        r = httpx.post(
            f"{self.host}/api/generate",
            json=payload,
            timeout=600,
        )
        r.raise_for_status()
        return r.json()["response"]
