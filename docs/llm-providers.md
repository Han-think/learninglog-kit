# LLM Provider 선택 가이드 / LLM Provider Guide

**한국어** | [English](#english)

---

## 한국어

### 한눈에 비교

| Provider | 비용 | 일일 한도 | 설치 | 속도 | 프라이버시 |
|----------|------|----------|------|------|-----------|
| **Gemini** | 무료 | 1,500회 | 키 발급만 | 빠름 | 클라우드 |
| **Groq** | 무료 | 14,400회 | 키 발급만 | 매우 빠름 | 클라우드 |
| **Ollama** | 완전 무료 | 무제한 | 앱 설치 필요 | 로컬 속도 | 완전 로컬 |
| **Claude** | 유료 | 제한 없음 | 키 발급만 | 빠름 | 클라우드 |
| **OpenAI** | 유료 | 제한 없음 | 키 발급만 | 빠름 | 클라우드 |

---

### 무료 옵션 A — Gemini (초보자 추천)

**학습 노트 10개 기준 API 호출 수:**
- 소스 1개당 extract(1회) + working_note(1회) = 2회
- 10개 × 2회 = **20회** → 하루 1,500회 한도의 1.3%

충분하다.

**설정:**

1. [https://aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey) → 무료 키 발급
2. 설치:
   ```bash
   pip install "learninglog-kit[gemini]"
   ```
3. config.yaml:
   ```yaml
   llm:
     provider: "gemini"
     gemini:
       api_key: "AIza..."
       model: "gemini-1.5-flash"
   ```

**또는 환경변수로 키 관리 (보안 권장):**
```bash
# ~/.bashrc 또는 Git Bash 프로파일에 추가
export GEMINI_API_KEY="AIza..."
```
config.yaml에서 `api_key` 를 비워두면 자동으로 환경변수를 읽습니다.

---

### 무료 옵션 B — Groq (속도 우선)

**특징:** 로컬 모델보다 빠를 때도 있음. Llama 3.1 기반.

1. [https://console.groq.com](https://console.groq.com) → 무료 가입 → API Keys
2. 설치:
   ```bash
   pip install "learninglog-kit[groq]"
   ```
3. config.yaml:
   ```yaml
   llm:
     provider: "groq"
     groq:
       api_key: "gsk_..."
       model: "llama-3.1-8b-instant"
   ```

---

### 로컬 옵션 — Ollama (프라이버시 최고)

**특징:** 인터넷 불필요. 데이터가 내 PC를 벗어나지 않음.

1. [https://ollama.com](https://ollama.com) 에서 Ollama 설치
2. 모델 다운로드:
   ```bash
   ollama pull llama3.2:3b    # 소형 (1.9GB)
   ollama pull gemma3:4b      # 중형 (3.3GB, 추천)
   ```
3. config.yaml:
   ```yaml
   llm:
     provider: "ollama"
     ollama:
       host: "http://127.0.0.1:11434"
       model: "gemma3:4b"
       num_ctx: 4096           # GPU VRAM 부족 시 2048로 낮춤
   ```

> **참고:** Ollama는 GPU가 있으면 빠르고, 없으면 CPU로 느리게 동작합니다.

---

### 유료 옵션 — Claude (품질 최고)

```bash
pip install "learninglog-kit[claude]"
```
```yaml
llm:
  provider: "claude"
  claude:
    api_key: "sk-ant-..."
    model: "claude-haiku-4-5"   # 가장 저렴
```

---

### 유료 옵션 — OpenAI

```bash
pip install "learninglog-kit[openai]"
```
```yaml
llm:
  provider: "openai"
  openai:
    api_key: "sk-..."
    model: "gpt-4o-mini"        # 가장 저렴
```

---

### 진단 명령어

```bash
learninglog doctor
```

설정과 LLM 연결 상태를 바로 확인할 수 있습니다.

---

---

## English

### Comparison

| Provider | Cost | Daily Limit | Setup | Speed | Privacy |
|----------|------|-------------|-------|-------|---------|
| **Gemini** | Free | 1,500 req | Key only | Fast | Cloud |
| **Groq** | Free | 14,400 req | Key only | Very fast | Cloud |
| **Ollama** | Free forever | Unlimited | App install | Local speed | Full local |
| **Claude** | Paid | Unlimited | Key only | Fast | Cloud |
| **OpenAI** | Paid | Unlimited | Key only | Fast | Cloud |

---

### Free Option A — Gemini (Recommended for beginners)

**API calls for 10 notes:**
- 2 calls per source (extract + working_note)
- 10 × 2 = **20 calls** out of 1,500/day limit = 1.3%

More than enough.

**Setup:**

1. Get free key at [https://aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)
2. Install:
   ```bash
   pip install "learninglog-kit[gemini]"
   ```
3. config.yaml:
   ```yaml
   llm:
     provider: "gemini"
     gemini:
       api_key: "AIza..."
       model: "gemini-1.5-flash"
   ```

**Using environment variables (recommended for security):**
```bash
export GEMINI_API_KEY="AIza..."
```
Leave `api_key` empty in config.yaml — it reads from the environment automatically.

---

### Free Option B — Groq (Speed priority)

1. Sign up free at [https://console.groq.com](https://console.groq.com) → API Keys
2. Install:
   ```bash
   pip install "learninglog-kit[groq]"
   ```
3. config.yaml:
   ```yaml
   llm:
     provider: "groq"
     groq:
       api_key: "gsk_..."
       model: "llama-3.1-8b-instant"
   ```

---

### Local Option — Ollama (Best privacy)

No internet required. Your data never leaves your machine.

1. Install Ollama from [https://ollama.com](https://ollama.com)
2. Pull a model:
   ```bash
   ollama pull gemma3:4b      # Recommended (3.3GB)
   ```
3. config.yaml:
   ```yaml
   llm:
     provider: "ollama"
     ollama:
       host: "http://127.0.0.1:11434"
       model: "gemma3:4b"
       num_ctx: 4096           # Lower to 2048 if GPU VRAM is limited
   ```

---

### Paid Options

**Claude:**
```bash
pip install "learninglog-kit[claude]"
```
```yaml
llm:
  provider: "claude"
  claude:
    api_key: "sk-ant-..."
    model: "claude-haiku-4-5"
```

**OpenAI:**
```bash
pip install "learninglog-kit[openai]"
```
```yaml
llm:
  provider: "openai"
  openai:
    api_key: "sk-..."
    model: "gpt-4o-mini"
```

---

### Diagnose

```bash
learninglog doctor
```

Shows your current provider and connection status.
