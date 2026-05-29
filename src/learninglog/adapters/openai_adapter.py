"""OpenAI 어댑터 — GPT API (유료).

설치: pip install learninglog-kit[openai]
키 발급: https://platform.openai.com/api-keys
"""

from __future__ import annotations

from .base import LLMAdapter


class OpenAIAdapter(LLMAdapter):
    """
    설정 예시 (config.yaml):
        llm:
          provider: openai
          openai:
            api_key: sk-...           # 또는 환경변수 OPENAI_API_KEY
            model: gpt-4o-mini        # 저렴한 모델
    """

    def __init__(self, api_key: str, model: str = "gpt-4o-mini"):
        try:
            from openai import OpenAI
        except ImportError:
            raise ImportError(
                "OpenAI 사용에는 추가 설치가 필요합니다: pip install learninglog-kit[openai]"
            )
        self._client = OpenAI(api_key=api_key)
        self.model   = model

    @property
    def provider_name(self) -> str:
        return "openai"

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
