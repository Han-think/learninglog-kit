"""LLM 어댑터 추상 인터페이스 — 모든 provider 가 구현해야 하는 계약."""

from __future__ import annotations

from abc import ABC, abstractmethod


class LLMAdapter(ABC):
    """모든 LLM provider 의 공통 인터페이스."""

    @abstractmethod
    def generate(self, prompt: str) -> str:
        """프롬프트를 받아 텍스트 응답 반환."""
        ...

    @abstractmethod
    def health_check(self) -> bool:
        """서비스 접근 가능 여부 확인."""
        ...

    @property
    @abstractmethod
    def provider_name(self) -> str:
        """'ollama' | 'gemini' | 'groq' | 'claude' | 'openai'"""
        ...
