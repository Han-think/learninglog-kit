"""Gemini 어댑터 — Google AI Studio 무료 티어.

설치: pip install learninglog-kit[gemini]
키 발급: https://aistudio.google.com/app/apikey (구글 계정만 있으면 무료)
"""

from __future__ import annotations

from .base import LLMAdapter


class GeminiAdapter(LLMAdapter):
    """
    설정 예시 (config.yaml):
        llm:
          provider: gemini
          gemini:
            api_key: AIza...          # 또는 환경변수 GEMINI_API_KEY
            model: gemini-1.5-flash   # 무료 티어 모델
    """

    def __init__(self, api_key: str, model: str = "gemini-1.5-flash"):
        try:
            import google.generativeai as genai
        except ImportError:
            raise ImportError(
                "Gemini 사용에는 추가 설치가 필요합니다: pip install learninglog-kit[gemini]"
            )
        genai.configure(api_key=api_key)
        self._client = genai.GenerativeModel(model)
        self.model   = model

    @property
    def provider_name(self) -> str:
        return "gemini"

    def health_check(self) -> bool:
        try:
            self._client.generate_content("hi")
            return True
        except Exception:
            return False

    def generate(self, prompt: str) -> str:
        response = self._client.generate_content(prompt)
        return response.text
