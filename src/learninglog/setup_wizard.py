"""setup_wizard.py — learninglog init 후 실행되는 대화형 LLM 설정 마법사."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Prompt, Confirm
from rich import print as rprint

console = Console()


PROVIDER_MENU = {
    "1": ("gemini",  "Gemini (Google)  — 무료 / Free  ★ 추천",    "GEMINI_API_KEY"),
    "2": ("groq",    "Groq             — 무료 / Free  (초고속)",    "GROQ_API_KEY"),
    "3": ("ollama",  "Ollama           — 완전 무료 / Free forever (로컬)", None),
    "4": ("claude",  "Claude (Anthropic) — 유료 / Paid",           "ANTHROPIC_API_KEY"),
    "5": ("openai",  "OpenAI (GPT)     — 유료 / Paid",             "OPENAI_API_KEY"),
    "6": ("none",    "나중에 설정 / Skip for now",                  None),
}

KEY_GUIDE = {
    "gemini": {
        "url":   "https://aistudio.google.com/app/apikey",
        "steps": [
            "1. 위 주소를 브라우저에서 엽니다 (구글 계정 필요)",
            "2. 'Create API key' 버튼 클릭",
            "3. 'Create API key in new project' 선택",
            "4. 생성된 키(AIzaSy...) 복사",
        ],
        "prefix":  "AIza",
        "model":   "gemini-1.5-flash",
        "model_key": "gemini",
    },
    "groq": {
        "url":   "https://console.groq.com",
        "steps": [
            "1. 위 주소에서 무료 가입",
            "2. 'API Keys' 메뉴 → 'Create API Key'",
            "3. 생성된 키(gsk_...) 복사",
        ],
        "prefix":  "gsk_",
        "model":   "llama-3.1-8b-instant",
        "model_key": "groq",
    },
    "claude": {
        "url":   "https://console.anthropic.com",
        "steps": [
            "1. 위 주소에서 가입 후 로그인",
            "2. 'API Keys' → 'Create Key'",
            "3. 생성된 키(sk-ant-...) 복사",
        ],
        "prefix":  "sk-ant-",
        "model":   "claude-haiku-4-5",
        "model_key": "claude",
    },
    "openai": {
        "url":   "https://platform.openai.com/api-keys",
        "steps": [
            "1. 위 주소에서 로그인",
            "2. 'Create new secret key'",
            "3. 생성된 키(sk-...) 복사",
        ],
        "prefix":  "sk-",
        "model":   "gpt-4o-mini",
        "model_key": "openai",
    },
}


def run_wizard(config_path: Path) -> None:
    """대화형 설정 마법사 실행."""

    console.print()
    console.print(Panel.fit(
        "[bold cyan]LearningLog 설정 마법사[/]\n"
        "[dim]LLM Setup Wizard[/]\n\n"
        "LLM 을 설정하면 노트를 자동으로 처리할 수 있습니다.\n"
        "[dim]Configure an LLM to auto-process your notes.[/]",
        border_style="cyan",
    ))
    console.print()

    # LLM 설정 여부 확인
    do_setup = Confirm.ask(
        "  지금 LLM 을 설정하시겠습니까? / Set up LLM now?",
        default=True,
    )
    if not do_setup:
        console.print("  [dim]나중에 config.yaml 에서 직접 설정하세요.[/]")
        console.print("  [dim]Edit .learninglog/config.yaml later.[/]")
        console.print(f"  [dim]설정 가이드: docs/llm-providers.md[/]")
        return

    # Provider 선택
    console.print()
    console.print("  [bold]LLM Provider 선택 / Choose your LLM:[/]")
    console.print()
    for key, (_, label, _) in PROVIDER_MENU.items():
        marker = "[bold green]★[/] " if key == "1" else "  "
        console.print(f"  {marker}[{key}] {label}")
    console.print()

    choice = Prompt.ask(
        "  번호를 입력하세요 / Enter number",
        choices=list(PROVIDER_MENU.keys()),
        default="1",
    )

    provider, _, env_var = PROVIDER_MENU[choice]

    if provider == "none":
        console.print()
        console.print("  [yellow]나중에 .learninglog/config.yaml 에서 설정하세요.[/]")
        console.print("  [dim]docs/llm-providers.md 참고[/]")
        return

    if provider == "ollama":
        _setup_ollama(config_path)
        return

    # API 키 필요한 provider
    guide = KEY_GUIDE[provider]
    _setup_api_provider(config_path, provider, guide, env_var)


def _setup_ollama(config_path: Path) -> None:
    """Ollama 설정 안내."""
    console.print()
    console.print(Panel.fit(
        "[bold]Ollama 설정[/]\n\n"
        "1. [link=https://ollama.com]https://ollama.com[/link] 에서 Ollama 설치\n"
        "2. 터미널에서 모델 다운로드:\n\n"
        "   [cyan]ollama pull gemma3:4b[/]\n\n"
        "3. Ollama 서버 실행:\n\n"
        "   [cyan]ollama serve[/]",
        border_style="yellow",
    ))

    _update_config(config_path, "ollama", api_key=None,
                   model="gemma3:4b", extra={"host": "http://127.0.0.1:11434", "num_ctx": 4096})

    console.print()
    console.print("  [green]config.yaml 에 Ollama 설정 완료![/]")
    console.print("  [dim]Ollama 서버를 켠 후 'learninglog doctor' 로 확인하세요.[/]")


def _setup_api_provider(config_path: Path, provider: str, guide: dict, env_var: str) -> None:
    """API 키 입력 + 저장."""

    console.print()
    console.print(Panel.fit(
        f"[bold]{provider.upper()} API 키 발급[/]\n\n"
        + "\n".join(guide["steps"])
        + f"\n\n[bold cyan]{guide['url']}[/]",
        border_style="blue",
    ))
    console.print()
    console.print("  [yellow]⚠ 키는 여기서만 입력하고 메신저/GitHub에는 절대 공유하지 마세요![/]")
    console.print("  [dim]⚠ Never share this key in chat apps or GitHub.[/]")
    console.print()

    # 키 입력
    api_key = Prompt.ask(f"  API 키 붙여넣기 / Paste your {provider} API key", password=True)
    api_key = api_key.strip()

    if not api_key:
        console.print("  [yellow]키를 입력하지 않았습니다. 나중에 config.yaml 에서 설정하세요.[/]")
        return

    # 저장 방법 선택
    console.print()
    console.print("  [bold]저장 방법 / Save method:[/]")
    console.print("  [1] 환경변수 ~/.bashrc  (보안 권장 / Recommended)")
    console.print("  [2] config.yaml 에 직접 입력")
    console.print()

    save_choice = Prompt.ask("  선택 / Choose", choices=["1", "2"], default="1")

    if save_choice == "1":
        _save_to_bashrc(env_var, api_key)
        key_for_config = ""  # config.yaml 에는 비워둠
    else:
        console.print("  [yellow]⚠ config.yaml 이 공개 저장소에 올라가지 않도록 주의하세요.[/]")
        key_for_config = api_key

    # config.yaml 업데이트
    _update_config(config_path, provider, api_key=key_for_config,
                   model=guide["model"])

    # 연결 테스트
    console.print()
    if Confirm.ask("  연결 테스트를 해볼까요? / Test connection now?", default=True):
        _test_connection(provider, api_key, guide["model"])


def _save_to_bashrc(env_var: str, api_key: str) -> None:
    """~/.bashrc 에 환경변수 추가."""
    bashrc = Path.home() / ".bashrc"
    line   = f'\nexport {env_var}="{api_key}"\n'

    try:
        with open(bashrc, "a", encoding="utf-8") as f:
            f.write(line)
        console.print(f"  [green]~/.bashrc 에 {env_var} 추가 완료![/]")
        console.print(f"  [dim]적용하려면: source ~/.bashrc[/]")
    except Exception as e:
        console.print(f"  [yellow]~/.bashrc 저장 실패: {e}[/]")
        console.print(f"  [yellow]수동으로 추가하세요: export {env_var}=\"...\"[/]")


def _update_config(config_path: Path, provider: str,
                   api_key: str | None, model: str,
                   extra: dict | None = None) -> None:
    """config.yaml 의 llm 섹션 업데이트."""
    import yaml

    with open(config_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}

    cfg.setdefault("llm", {})
    cfg["llm"]["provider"] = provider

    if provider != "none":
        section = cfg["llm"].setdefault(provider, {})
        if api_key is not None:
            section["api_key"] = api_key
        section["model"] = model
        if extra:
            section.update(extra)

    with open(config_path, "w", encoding="utf-8") as f:
        yaml.dump(cfg, f, allow_unicode=True, default_flow_style=False, sort_keys=False)

    console.print(f"  [green]config.yaml 업데이트 완료 (provider: {provider})[/]")


def _test_connection(provider: str, api_key: str, model: str) -> None:
    """간단한 연결 테스트."""
    console.print("  연결 테스트 중... / Testing connection...", end=" ")

    try:
        if provider == "gemini":
            import google.generativeai as genai
            genai.configure(api_key=api_key)
            genai.GenerativeModel(model).generate_content("hi")

        elif provider == "groq":
            from groq import Groq
            Groq(api_key=api_key).chat.completions.create(
                model=model, messages=[{"role": "user", "content": "hi"}], max_tokens=5
            )

        elif provider == "claude":
            import anthropic
            anthropic.Anthropic(api_key=api_key).messages.create(
                model=model, max_tokens=5,
                messages=[{"role": "user", "content": "hi"}]
            )

        elif provider == "openai":
            from openai import OpenAI
            OpenAI(api_key=api_key).chat.completions.create(
                model=model, messages=[{"role": "user", "content": "hi"}], max_tokens=5
            )

        console.print("[bold green]OK ✓[/]")
        console.print()
        console.print(Panel.fit(
            "[bold green]설정 완료! / Setup Complete![/]\n\n"
            "다음 단계 / Next steps:\n\n"
            "  1. 노트를 [cyan]00_inbox/personal_notes/[/] 에 넣기\n"
            "  2. [cyan]learninglog intake[/]  — 파일 등록\n"
            "  3. [cyan]learninglog extract[/] — LLM 처리",
            border_style="green",
        ))

    except ImportError as e:
        console.print("[yellow]라이브러리 미설치[/]")
        pkg = str(e).split("'")[1] if "'" in str(e) else provider
        console.print(f"  [dim]pip install learninglog-kit[{provider}][/]")

    except Exception as e:
        console.print("[red]실패 / Failed[/]")
        console.print(f"  [dim]오류: {e}[/]")
        console.print("  [yellow]API 키를 다시 확인하거나 'learninglog doctor' 를 실행하세요.[/]")
