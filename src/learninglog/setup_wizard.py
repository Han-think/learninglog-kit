"""setup_wizard.py — learninglog init 후 실행되는 대화형 LLM 설정 마법사."""

from __future__ import annotations

from pathlib import Path

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Prompt, Confirm

console = Console()


# ─── Provider 메뉴 (3개 무료 + 나중에) ──────────────────────
PROVIDER_MENU = {
    "1": "gemini",
    "2": "groq",
    "3": "ollama",
    "4": "none",
}

PROVIDER_INFO = {
    "gemini": {
        "name":       "Gemini (Google AI Studio)",
        "cost":       "무료 / Free",
        "daily":      "하루 1,500회 요청 · 매일 자정 리셋 / 1,500 req/day · resets daily",
        "speed":      "빠름 / Fast",
        "privacy":    "클라우드 / Cloud",
        "note":       "구글 계정만 있으면 발급 가능. 노트 50개/일 처리 시 한도의 ~7%.",
        "note_en":    "Google account only. Processing 50 notes/day uses ~7% of limit.",
        "url":        "https://aistudio.google.com/app/apikey",
        "key_steps":  [
            "1. 위 주소를 브라우저에서 열기 (구글 계정 로그인)",
            "2. [Create API key] 클릭",
            "3. [Create API key in new project] 선택",
            "4. 생성된 키(AIzaSy...) 복사",
        ],
        "key_steps_en": [
            "1. Open the URL above (sign in with Google)",
            "2. Click [Create API key]",
            "3. Select [Create API key in new project]",
            "4. Copy the key (starts with AIzaSy...)",
        ],
        "env_var":  "GEMINI_API_KEY",
        "model":    "gemini-2.5-flash",
        "key_hint": "AIzaSy",
    },
    "groq": {
        "name":       "Groq",
        "cost":       "무료 / Free",
        "daily":      "하루 14,400회 요청 · 매일 자정(UTC) 리셋 / 14,400 req/day · resets daily UTC",
        "speed":      "매우 빠름 / Very fast",
        "privacy":    "클라우드 / Cloud",
        "note":       "가장 빠른 무료 옵션. Llama 3.1 기반. 노트 50개/일 처리 시 한도의 ~0.7%.",
        "note_en":    "Fastest free option. Llama 3.1 based. 50 notes/day uses ~0.7% of limit.",
        "url":        "https://console.groq.com",
        "key_steps":  [
            "1. 위 주소에서 무료 가입 (이메일)",
            "2. 로그인 후 왼쪽 메뉴 [API Keys] 클릭",
            "3. [Create API Key] → 이름 입력 → 생성",
            "4. 생성된 키(gsk_...) 복사",
        ],
        "key_steps_en": [
            "1. Sign up free at the URL above",
            "2. Go to [API Keys] in the left menu",
            "3. Click [Create API Key] → name it → create",
            "4. Copy the key (starts with gsk_...)",
        ],
        "env_var":  "GROQ_API_KEY",
        "model":    "llama-3.1-8b-instant",
        "key_hint": "gsk_",
    },
    "ollama": {
        "name":       "Ollama (로컬 / Local)",
        "cost":       "완전 무료 / Free forever",
        "daily":      "제한 없음 / No limits",
        "speed":      "로컬 속도 (GPU 권장) / Local speed (GPU recommended)",
        "privacy":    "완전 로컬 · 인터넷 불필요 / Full local · No internet",
        "note":       "인터넷 없이 동작. 데이터가 내 PC 밖으로 나가지 않음.",
        "note_en":    "Works offline. Your data never leaves your machine.",
        "url":        "https://ollama.com",
        "key_steps":  [
            "1. 위 주소에서 Ollama 앱 다운로드 및 설치",
            "2. 터미널에서 모델 다운로드:",
            "   ollama pull gemma3:4b   (추천, 3.3GB)",
            "3. Ollama 서버 실행:",
            "   ollama serve",
        ],
        "key_steps_en": [
            "1. Download and install Ollama from the URL above",
            "2. Pull a model:",
            "   ollama pull gemma3:4b   (recommended, 3.3GB)",
            "3. Start the server:",
            "   ollama serve",
        ],
        "env_var":  None,
        "model":    "gemma3:4b",
        "key_hint": None,
    },
}


def run_wizard(config_path: Path) -> None:
    """대화형 설정 마법사 실행."""

    console.print()
    console.print(Panel.fit(
        "[bold cyan]LearningLog 설정 마법사 / Setup Wizard[/]\n\n"
        "LLM 을 설정하면 노트를 자동으로 처리할 수 있습니다.\n"
        "[dim]Configure an LLM to automatically process your notes.[/]",
        border_style="cyan",
    ))
    console.print()

    do_setup = Confirm.ask(
        "  지금 LLM 을 설정할까요? / Set up LLM now?",
        default=True,
    )
    if not do_setup:
        _skip_message()
        return

    # ─── Provider 선택 ────────────────────────────────────────
    _show_provider_menu()

    choice = Prompt.ask(
        "  번호 선택 / Choose number",
        choices=["1", "2", "3", "4"],
        default="1",
    )
    provider = PROVIDER_MENU[choice]

    if provider == "none":
        _skip_message()
        return

    info = PROVIDER_INFO[provider]

    # ─── 설치 안내 ────────────────────────────────────────────
    console.print()
    steps_text = "\n".join(info["key_steps"])
    console.print(Panel.fit(
        f"[bold]{info['name']} 설정 방법[/]\n\n"
        f"[cyan]{info['url']}[/]\n\n"
        + steps_text,
        border_style="blue",
    ))

    # Ollama 는 키 없음
    if provider == "ollama":
        _setup_ollama(config_path, info)
        return

    # ─── API 키 입력 ──────────────────────────────────────────
    console.print()
    console.print("  [yellow]⚠  키는 메신저/GitHub/SNS에 절대 공유하지 마세요![/]")
    console.print("  [dim]⚠  Never share this key in chat apps, GitHub, or social media.[/]")
    console.print()

    api_key = Prompt.ask(
        f"  키 붙여넣기 / Paste {provider} API key",
        password=True,
    ).strip()

    if not api_key:
        console.print("  [yellow]키 미입력. 나중에 config.yaml 에서 설정하세요.[/]")
        return

    # ─── 저장 방법 ────────────────────────────────────────────
    console.print()
    console.print("  [bold]키 저장 방법 / How to save key:[/]")
    console.print("  [1] 환경변수 ~/.bashrc  — 보안 권장 / Recommended")
    console.print("  [2] config.yaml 직접 입력 — 간단하지만 주의 필요")
    console.print()

    save = Prompt.ask("  선택 / Choose", choices=["1", "2"], default="1")

    if save == "1":
        _save_to_bashrc(info["env_var"], api_key)
        key_for_config = ""
    else:
        console.print("  [yellow]⚠  config.yaml 을 GitHub 에 올리지 않도록 주의하세요.[/]")
        key_for_config = api_key

    _update_config(config_path, provider, key_for_config, info["model"])

    # ─── 연결 테스트 ──────────────────────────────────────────
    console.print()
    if Confirm.ask("  연결 테스트 / Test connection now?", default=True):
        _test_connection(provider, api_key, info["model"])


def _show_provider_menu() -> None:
    """3개 Provider 옵션 + 무료 한도 표시."""
    console.print()
    console.print("  [bold]LLM 선택 / Choose your LLM:[/]")
    console.print()

    rows = [
        ("1", "gemini"),
        ("2", "groq"),
        ("3", "ollama"),
    ]
    for num, pid in rows:
        info = PROVIDER_INFO[pid]
        star = "[bold green]★[/] " if num == "1" else "  "
        console.print(f"  {star}[bold][{num}] {info['name']}[/]")
        console.print(f"       비용: [green]{info['cost']}[/]")
        console.print(f"       한도: {info['daily']}")
        console.print(f"       속도: {info['speed']}")
        console.print(f"       [dim]{info['note']}[/]")
        console.print()

    console.print("    [4] 나중에 설정 / Skip for now")
    console.print()


def _setup_ollama(config_path: Path, info: dict) -> None:
    _update_config(config_path, "ollama", api_key=None,
                   model=info["model"],
                   extra={"host": "http://127.0.0.1:11434", "num_ctx": 4096})
    console.print()
    console.print("  [green]config.yaml 에 Ollama 설정 완료![/]")
    console.print("  [dim]Ollama 서버를 켠 후 'learninglog doctor' 로 확인하세요.[/]")
    console.print("  [dim]After starting Ollama, run 'learninglog doctor' to verify.[/]")


def _save_to_bashrc(env_var: str, api_key: str) -> None:
    bashrc = Path.home() / ".bashrc"
    line   = f'\nexport {env_var}="{api_key}"\n'
    try:
        with open(bashrc, "a", encoding="utf-8") as f:
            f.write(line)
        console.print(f"  [green]~/.bashrc 에 {env_var} 저장 완료![/]")
        console.print(f"  [dim]적용: source ~/.bashrc  (새 터미널은 자동 적용)[/]")
    except Exception as e:
        console.print(f"  [yellow]저장 실패: {e}[/]")
        console.print(f"  [yellow]수동 추가: export {env_var}=\"{api_key}\"[/]")


def _update_config(config_path: Path, provider: str,
                   api_key: str | None, model: str,
                   extra: dict | None = None) -> None:
    import yaml
    with open(config_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}

    cfg.setdefault("llm", {})
    cfg["llm"]["provider"] = provider

    if provider not in ("none", "skip"):
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
    console.print("  연결 테스트 중 / Testing...", end=" ")
    try:
        if provider == "gemini":
            from google import genai
            client = genai.Client(api_key=api_key) if api_key else genai.Client()
            client.models.generate_content(model=(model or "gemini-2.5-flash"), contents="hi")
        elif provider == "groq":
            from groq import Groq
            Groq(api_key=api_key).chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": "hi"}],
                max_tokens=5,
            )
        console.print("[bold green]OK ✓[/]")
        console.print()
        console.print(Panel.fit(
            "[bold green]설정 완료! / All done![/]\n\n"
            "  1. [cyan]00_inbox/personal_notes/[/] 에 노트(.md) 넣기\n"
            "  2. [cyan]learninglog intake[/]  — 파일 등록\n"
            "  3. [cyan]learninglog extract[/] — LLM 처리\n\n"
            "[dim]  learninglog --help  for all commands[/]",
            border_style="green",
        ))
    except ImportError:
        console.print("[yellow]라이브러리 미설치[/]")
        console.print(f"  [dim]pip install \"learninglog-kit[{provider}]\"[/]")
    except Exception as e:
        console.print("[red]실패 / Failed[/]")
        console.print(f"  [dim]{e}[/]")
        console.print("  [yellow]API 키를 확인하거나 'learninglog doctor' 를 실행하세요.[/]")


def _skip_message() -> None:
    console.print()
    console.print("  [dim]나중에 .learninglog/config.yaml 에서 설정하세요.[/]")
    console.print("  [dim]Edit .learninglog/config.yaml to configure LLM later.[/]")
    console.print("  [dim]가이드: docs/llm-providers.md[/]")
