# 빠른 시작 가이드 / Quick Start Guide

**한국어** | [English](#english)

---

## 한국어

### 준비물

- Python 3.10 이상
- Git Bash 또는 터미널
- 구글 계정 (Gemini 무료 API 사용 시)

---

### Step 1 — 설치

```bash
pip install "learninglog-kit[gemini]"
```

> Gemini 대신 다른 LLM을 쓰고 싶다면 → [llm-providers.md](llm-providers.md)

---

### Step 2 — 프로젝트 만들기

원하는 위치에 폴더를 만들고 초기화합니다.

```bash
mkdir my-learning
cd my-learning
learninglog init
```

아래 구조가 자동으로 생성됩니다:

```
my-learning/
├── .learninglog/
│   └── config.yaml       ← LLM 설정 파일
├── 00_inbox/
│   ├── personal_notes/   ← 내 노트를 여기에
│   ├── lectures/         ← 강의 자료 (내부용)
│   └── web_notes/        ← 웹 참고 자료
├── 02_extracted/         ← 자동 생성: 사실 추출
├── 03_working_notes/     ← 자동 생성: 워킹 노트
└── 04_blog_drafts/       ← 자동 생성: 블로그 초안
```

---

### Step 3 — Gemini API 키 발급 (무료)

1. [https://aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey) 접속
2. 구글 계정으로 로그인
3. **Create API key** 클릭
4. 키 복사 (`AIza...` 형태)

> **무료 한도:** 하루 1,500회 요청. 개인 학습 노트에는 충분합니다.

---

### Step 4 — config.yaml 설정

VS Code나 텍스트 에디터로 `.learninglog/config.yaml`을 엽니다.

```bash
code .learninglog/config.yaml
```

`provider` 를 `gemini` 로 바꾸고 API 키를 입력합니다:

```yaml
llm:
  provider: "gemini"          # "none" → "gemini" 로 변경
  gemini:
    api_key: "AIza..."        # 발급받은 키 입력
    model: "gemini-2.5-flash"
```

---

### Step 5 — 진단

설정이 제대로 됐는지 확인합니다.

```bash
learninglog doctor
```

```
  LLM provider : gemini
  LLM 상태     : OK
  config.yaml  : /path/to/.learninglog/config.yaml
```

---

### Step 6 — 노트 넣기

`00_inbox/personal_notes/` 폴더에 `.md` 파일을 넣습니다.

예시 파일: `2024-01-15_python_basics.md`

```markdown
# 오늘 배운 것

## 핵심 내용
- Python 리스트는 순서가 있다
- append()로 항목 추가

## 헷갈렸던 점
인덱스가 0부터 시작한다는 것을 자꾸 잊어버렸다.
```

---

### Step 7 — 실행

```bash
# 1. 새 파일 등록
learninglog intake

# 2. 처리 순서 확인 (선택)
learninglog queue

# 3. LLM으로 노트 생성
learninglog extract
```

---

### 결과물 확인

처리가 완료되면:

```
03_working_notes/daily_logs/    ← 워킹 노트 (내 해석 포함)
02_extracted/concept_extracts/  ← 사실 추출 요약
```

---

### 팁

- 노트는 한국어로 써도 됩니다. LLM이 한국어를 이해합니다.
- 강의 PDF는 `00_inbox/lectures/`에 넣으세요. 자동으로 `internal-only`로 분류됩니다.
- `learninglog status`로 전체 현황을 볼 수 있습니다.

---

---

## English

### Requirements

- Python 3.10+
- Git Bash or any terminal
- Google account (for free Gemini API)

---

### Step 1 — Install

```bash
pip install "learninglog-kit[gemini]"
```

> Want a different LLM? See [llm-providers.md](llm-providers.md)

---

### Step 2 — Create a Project

```bash
mkdir my-learning
cd my-learning
learninglog init
```

This creates:

```
my-learning/
├── .learninglog/
│   └── config.yaml       ← LLM configuration
├── 00_inbox/
│   ├── personal_notes/   ← Put your notes here
│   ├── lectures/         ← Lecture materials (internal only)
│   └── web_notes/        ← Web references
├── 02_extracted/         ← Auto-generated: fact extraction
├── 03_working_notes/     ← Auto-generated: working notes
└── 04_blog_drafts/       ← Auto-generated: blog drafts
```

---

### Step 3 — Get a Free Gemini API Key

1. Go to [https://aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)
2. Sign in with your Google account
3. Click **Create API key**
4. Copy the key (starts with `AIza...`)

> **Free limits:** 1,500 requests/day. More than enough for personal notes.

---

### Step 4 — Configure

Open `.learninglog/config.yaml`:

```bash
code .learninglog/config.yaml
```

Change `provider` to `gemini` and add your key:

```yaml
llm:
  provider: "gemini"
  gemini:
    api_key: "AIza..."
    model: "gemini-2.5-flash"
```

---

### Step 5 — Verify Setup

```bash
learninglog doctor
```

You should see `LLM status: OK`.

---

### Step 6 — Add Your Notes

Put `.md` files in `00_inbox/personal_notes/`.

Example: `2024-01-15_python_basics.md`

---

### Step 7 — Run

```bash
learninglog intake    # Register new files
learninglog queue     # See processing order (optional)
learninglog extract   # Generate notes with LLM
```

---

### Output

After processing:

```
03_working_notes/daily_logs/    ← Working notes with your interpretation
02_extracted/concept_extracts/  ← Factual summaries
```
