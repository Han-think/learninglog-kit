"""Groq 어댑터 — 초고속 무료 티어.

설치: pip install learninglog-kit[groq]
키 발급: https://console.groq.com (무료 가입)
"""

from __future__ import annotations

from .base import LLMAdapter


class GroqAdapter(LLMAdapter):
    """
    설정 예시 (config.yaml):
        llm:
          provider: groq
          groq:
            api_key: gsk_...          # 또는 환경변수 GROQ_API_KEY
            model: llama-3.1-8b-instant
    """

    def __init__(self, api_key: str, model: str = "llama-3.1-8b-instant"):
        try:
            from groq import Groq
        except ImportError:
            raise ImportError(
                "Groq 사용에는 추가 설치가 필요합니다: pip install learninglog-kit[groq]"
            )
        self._client = Groq(api_key=api_key)
        self.model   = model

    @property
    def provider_name(self) -> str:
        return "groq"

    def health_check(self) -> bool:
        try:
            self._client.models.list()
            return True
        except Exception:
            return False

    def generate(self, prompt: str) -> str:
        completion = self._client.chat.completions.create(
            model=self.model,
            messages=[{"role": "user", "content": prompt}],
        )
        return completion.choices[0].message.content
