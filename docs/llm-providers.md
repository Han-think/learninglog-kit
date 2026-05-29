# LLM Provider 선택 가이드

## 한눈에 보기

| Provider | 비용 | 설치 | 속도 | 프라이버시 |
|----------|------|------|------|-----------|
| **Gemini** | 무료 (한도 있음) | API 키만 | 빠름 | 클라우드 |
| **Groq** | 무료 (한도 있음) | API 키만 | 매우 빠름 | 클라우드 |
| **Ollama** | 완전 무료 | 앱 설치 필요 | 로컬 속도 | 로컬 (최고) |
| **Claude** | 유료 | API 키만 | 빠름 | 클라우드 |
| **OpenAI** | 유료 | API 키만 | 빠름 | 클라우드 |

---

## 무료로 시작하려면

### 옵션 A — Gemini (가장 쉬움)

1. https://aistudio.google.com 에서 구글 계정으로 로그인
2. **Get API key** 클릭 → API 키 복사
3. 설치:
   ```bash
   pip install learninglog-kit[gemini]
   ```
4. config.yaml 수정:
   ```yaml
   llm:
     provider: "gemini"
     gemini:
       api_key: "AIza..."
       model: "gemini-1.5-flash"
   ```

**무료 한도:** 분당 15회 요청, 하루 1,500회

---

### 옵션 B — Groq (가장 빠름)

1. https://console.groq.com 에서 무료 가입
2. API Keys 메뉴 → 키 생성
3. 설치:
   ```bash
   pip install learninglog-kit[groq]
   ```
4. config.yaml 수정:
   ```yaml
   llm:
     provider: "groq"
     groq:
       api_key: "gsk_..."
       model: "llama-3.1-8b-instant"
   ```

**무료 한도:** 분당 30회, 하루 14,400회

---

### 옵션 C — Ollama (완전 무료, 로컬)

1. https://ollama.com 에서 Ollama 설치
2. 모델 다운로드:
   ```bash
   ollama pull llama3.2:3b
   ```
3. 추가 설치 불필요 (기본 포함)
4. config.yaml 수정:
   ```yaml
   llm:
     provider: "ollama"
     ollama:
       host: "http://127.0.0.1:11434"
       model: "llama3.2:3b"
   ```

**장점:** 완전 무료, 인터넷 불필요, 데이터 로컬 유지

---

## 유료 옵션

### Claude (Anthropic)

```bash
pip install learninglog-kit[claude]
```
```yaml
llm:
  provider: "claude"
  claude:
    api_key: "sk-ant-..."
    model: "claude-haiku-4-5"   # 가장 저렴
```

### OpenAI

```bash
pip install learninglog-kit[openai]
```
```yaml
llm:
  provider: "openai"
  openai:
    api_key: "sk-..."
    model: "gpt-4o-mini"   # 가장 저렴
```

---

## 환경변수로 API 키 관리 (권장)

config.yaml 에 키를 직접 쓰는 대신 환경변수를 사용하면 안전합니다.

```bash
# Git Bash / .bashrc 에 추가
export GEMINI_API_KEY="AIza..."
export GROQ_API_KEY="gsk_..."
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
```

config.yaml 에서 api_key 를 비워두면 자동으로 환경변수를 읽습니다.

---

## 진단

```bash
learninglog doctor
```

설정과 LLM 연결 상태를 바로 확인할 수 있습니다.
