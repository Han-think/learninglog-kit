"""어댑터 팩토리 — config.yaml 의 provider 설정으로 어댑터 자동 생성."""

from __future__ import annotations

import os
from typing import Any

from .base import LLMAdapter


def create_adapter(cfg: dict[str, Any]) -> LLMAdapter:
    """
    config.yaml 의 llm 섹션을 읽어 적절한 어댑터 반환.

    provider 가 none 이거나 llm 섹션이 없으면 NullAdapter 반환
    (LLM 없이 intake/queue 만 사용하는 경우).
    """
    provider = cfg.get("llm", {}).get("provider", "none").lower()

    if provider == "ollama":
        from .ollama import OllamaAdapter
        c = cfg.get("llm", {}).get("ollama", {})
        return OllamaAdapter(
            host  = c.get("host",  "http://127.0.0.1:11434"),
            model = c.get("model", "llama3.2:3b"),
        )

    elif provider == "gemini":
        from .gemini import GeminiAdapter
        c       = cfg.get("llm", {}).get("gemini", {})
        api_key = c.get("api_key") or os.environ.get("GEMINI_API_KEY", "")
        return GeminiAdapter(api_key=api_key, model=c.get("model", "gemini-1.5-flash"))

    elif provider == "groq":
        from .groq_adapter import GroqAdapter
        c       = cfg.get("llm", {}).get("groq", {})
        api_key = c.get("api_key") or os.environ.get("GROQ_API_KEY", "")
        return GroqAdapter(api_key=api_key, model=c.get("model", "llama-3.1-8b-instant"))

    elif provider == "claude":
        from .claude import ClaudeAdapter
        c       = cfg.get("llm", {}).get("claude", {})
        api_key = c.get("api_key") or os.environ.get("ANTHROPIC_API_KEY", "")
        return ClaudeAdapter(api_key=api_key, model=c.get("model", "claude-haiku-4-5"))

    elif provider == "openai":
        from .openai_adapter import OpenAIAdapter
        c       = cfg.get("llm", {}).get("openai", {})
        api_key = c.get("api_key") or os.environ.get("OPENAI_API_KEY", "")
        return OpenAIAdapter(api_key=api_key, model=c.get("model", "gpt-4o-mini"))

    else:
        return NullAdapter()


class NullAdapter(LLMAdapter):
    """LLM 없이 실행 — intake/queue 는 동작, extract 는 스킵."""

    @property
    def provider_name(self) -> str:
        return "none"

    def health_check(self) -> bool:
        return False

    def generate(self, prompt: str) -> str:
        raise RuntimeError(
            "LLM provider 가 설정되지 않았습니다.\n"
            "config.yaml 의 llm.provider 를 설정하거나 --skip-llm 옵션을 사용하세요.\n"
            "자세한 내용: docs/llm-providers.md"
        )
