"""Gemini 어댑터 — Google Gen AI SDK (google-genai).

새 공식 SDK 사용 (구 google-generativeai 단종).
구글의 새 키 형식(AQ. ...)도 이 SDK로 정상 동작.

설치: pip install learninglog-kit[gemini]   (google-genai)
키 발급: https://aistudio.google.com/app/apikey
"""

from __future__ import annotations

from .base import LLMAdapter

DEFAULT_MODEL = "gemini-2.5-flash"
FALLBACK_MODELS = ["gemini-2.5-flash", "gemini-2.0-flash", "gemini-flash-latest"]


class GeminiAdapter(LLMAdapter):
    """
    설정 예시 (config.yaml):
        llm:
          provider: gemini
          gemini:
            api_key: ""               # 또는 환경변수 GEMINI_API_KEY
            model: gemini-2.5-flash
    """

    def __init__(self, api_key: str, model: str = DEFAULT_MODEL):
        try:
            from google import genai
        except ImportError:
            raise ImportError(
                "Gemini 사용에는 추가 설치가 필요합니다: pip install learninglog-kit[gemini]"
            )
        # api_key 가 비면 SDK 가 환경변수 GEMINI_API_KEY 를 읽음
        self._client = genai.Client(api_key=api_key) if api_key else genai.Client()
        self.model = model or DEFAULT_MODEL

    @property
    def provider_name(self) -> str:
        return "gemini"

    def health_check(self) -> bool:
        try:
            self._client.models.generate_content(model=self.model, contents="hi")
            return True
        except Exception:
            return False

    def generate(self, prompt: str) -> str:
        try:
            resp = self._client.models.generate_content(model=self.model, contents=prompt)
            return resp.text
        except Exception:
            # 모델명이 안 맞으면 후보 모델로 재시도
            for m in FALLBACK_MODELS:
                if m == self.model:
                    continue
                try:
                    resp = self._client.models.generate_content(model=m, contents=prompt)
                    self.model = m
                    return resp.text
                except Exception:
                    continue
            raise
