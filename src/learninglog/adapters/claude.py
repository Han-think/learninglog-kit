"""Claude 어댑터 — Anthropic API (유료).

설치: pip install learninglog-kit[claude]
키 발급: https://console.anthropic.com
"""

from __future__ import annotations

from .base import LLMAdapter


class ClaudeAdapter(LLMAdapter):
    """
    설정 예시 (config.yaml):
        llm:
          provider: claude
          claude:
            api_key: sk-ant-...       # 또는 환경변수 ANTHROPIC_API_KEY
            model: claude-haiku-4-5   # 가장 저렴한 모델
    """

    def __init__(self, api_key: str, model: str = "claude-haiku-4-5"):
        try:
            import anthropic
        except ImportError:
            raise ImportError(
                "Claude 사용에는 추가 설치가 필요합니다: pip install learninglog-kit[claude]"
            )
        self._client = anthropic.Anthropic(api_key=api_key)
        self.model   = model

    @property
    def provider_name(self) -> str:
        return "claude"

    def health_check(self) -> bool:
        try:
            self._client.models.list()
            return True
        except Exception:
            return False

    def generate(self, prompt: str) -> str:
        message = self._client.messages.create(
            model=self.model,
            max_tokens=4096,
            messages=[{"role": "user", "content": prompt}],
        )
        return message.content[0].text
