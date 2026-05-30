# learninglog-kit

**한국어** | [English](#english-guide)

개인 학습 노트를 자동으로 정리해주는 파이프라인 도구.
노트를 폴더에 넣으면 LLM이 핵심 추출 → 워킹 노트 → 블로그 초안까지 만들어줍니다.

---

## 가장 쉬운 시작 — 웹 UI (추천)

```bash
pip install "learninglog-kit[web,gemini]"
learninglog ui
```

브라우저(`http://127.0.0.1:8765`)가 열리면:
1. **작업 폴더 생성** 버튼 클릭
2. **Gemini** 선택 → [API 키 발급](https://aistudio.google.com/app/apikey) → 키 붙여넣기 → 저장+테스트
3. `00_inbox/personal_notes/` 에 노트(.md) 넣기
4. **① intake → ② extract → ③ publish** 버튼 클릭

설치·설정·실행을 전부 버튼으로. 터미널 명령 몰라도 됩니다.

---

## 빠른 시작 — 터미널 (한국어)

### 1. 설치

```bash
# 기본 설치 (Ollama 로컬 모델용)
pip install learninglog-kit

# Gemini 무료 API 사용 시
pip install "learninglog-kit[gemini]"

# Groq 무료 API 사용 시
pip install "learninglog-kit[groq]"

# 전체 설치
pip install "learninglog-kit[all]"
```

### 2. 프로젝트 초기화

```bash
mkdir my-learning
cd my-learning
learninglog init
```

### 3. LLM 설정

`.learninglog/config.yaml` 파일을 열어 LLM을 선택합니다.

```bash
code .learninglog/config.yaml   # VS Code로 열기
```

**무료 옵션 (추천):**

```yaml
llm:
  provider: "gemini"      # 구글 계정만 있으면 무료
  gemini:
    api_key: "AIza..."    # aistudio.google.com 에서 발급
    model: "gemini-1.5-flash"
```

→ 자세한 설정 방법: [docs/llm-providers.md](docs/llm-providers.md)

### 4. 노트 넣기

```
my-learning/
└── 00_inbox/
    └── personal_notes/    ← 여기에 .md 파일을 넣으세요
```

### 5. 실행

```bash
learninglog intake     # 새 파일 감지 및 등록
learninglog queue      # 처리 순서 확인
learninglog extract    # LLM으로 노트 + 블로그 초안 생성
learninglog publish    # 블로그로 발행 (blog 설정 시)
```

---

## 명령어 목록

| 명령어 | 설명 |
|-------|------|
| `learninglog ui` | **브라우저 설정/실행 UI** (설치·API키·실행을 버튼으로) |
| `learninglog init [폴더]` | 프로젝트 폴더 구조 생성 + LLM 설정 마법사 |
| `learninglog intake` | 새 파일 자동 등록 |
| `learninglog queue` | 처리 대기 목록 확인 |
| `learninglog extract` | LLM으로 extract + working_note + blog_draft 생성 |
| `learninglog publish` | 초안을 블로그로 발행 (draft:false + ai_assisted 마킹 + hugo 빌드 + git push) |
| `learninglog status` | 전체 현황 요약 |
| `learninglog doctor` | 설정 및 LLM 연결 진단 |
| `learninglog clean` | 생성 **데이터만** 정리 (재시작용, 패키지 유지) |
| `learninglog uninstall` | 프로그램 + 데이터 **모두 제거** (install 의 반대) |

### 설치 ↔ 제거 (install ↔ uninstall)

| 개념 | 대상 | 명령 |
|------|------|------|
| **install** | 프로그램 설치 | `pip install "learninglog-kit[web,gemini]"` |
| **uninstall** | 프로그램 + 데이터 제거 | `learninglog uninstall` |

### 데이터만 정리 (clean — 재시작용)

```bash
learninglog clean             # 생성물만 (02~06, 09_reports)
learninglog clean --config    # 설정(.learninglog)도
learninglog clean --api-key   # ~/.bashrc 의 API 키 줄 제거
learninglog clean --all -y    # 데이터 전부 (패키지는 유지)
```

### 완전 제거 (uninstall)

```bash
learninglog uninstall         # 데이터 정리 + pip 패키지 제거 (한 번에)
learninglog uninstall --keep-package  # 데이터만, 패키지 유지
```

> `00_inbox/` 의 원본 노트는 **어떤 경우에도 자동 삭제되지 않습니다.** 직접 지우세요.

### 블로그 발행 설정

`.learninglog/config.yaml` 의 `blog` 섹션:
```yaml
blog:
  platform:    "hugo"            # hugo | jekyll | none
  source_path: "../blog-source"  # 블로그 소스 폴더
  auto_build:  true              # hugo 빌드 실행
  auto_push:   false             # git push 자동 (기본 off)
```

---

## LLM 선택 가이드

| 옵션 | 비용 | 설치 난이도 | 속도 | 프라이버시 |
|------|------|------------|------|-----------|
| **Gemini** | 무료 (일 1,500회) | 쉬움 | 빠름 | 클라우드 |
| **Groq** | 무료 (일 14,400회) | 쉬움 | 매우 빠름 | 클라우드 |
| **Ollama** | 완전 무료 | 앱 설치 필요 | 로컬 속도 | 로컬 (최고) |
| **Claude** | 유료 | 쉬움 | 빠름 | 클라우드 |
| **OpenAI** | 유료 | 쉬움 | 빠름 | 클라우드 |

→ [docs/llm-providers.md](docs/llm-providers.md) 에서 단계별 설정 방법 확인

---

## 파이프라인 구조

```
00_inbox/  →  intake  →  queue  →  extract
                                      ↓
                              02_extracted/       (사실 추출)
                              03_working_notes/   (워킹 노트)
                                      ↓
                              (검토 후) 04_blog_drafts/
                                      ↓
                              (승인 후) blog-source/
```

---

---

# English Guide

A personal learning pipeline tool.
Drop your notes into a folder — LLM extracts key facts, creates working notes, and drafts blog posts.

## Quick Start

### 1. Install

```bash
# Basic install (for Ollama local models)
pip install learninglog-kit

# With Gemini free API
pip install "learninglog-kit[gemini]"

# With Groq free API
pip install "learninglog-kit[groq]"

# Everything
pip install "learninglog-kit[all]"
```

### 2. Initialize Project

```bash
mkdir my-learning
cd my-learning
learninglog init
```

### 3. Configure LLM

Open `.learninglog/config.yaml` and choose your LLM provider.

**Free option (recommended for beginners):**

```yaml
llm:
  provider: "gemini"
  gemini:
    api_key: "AIza..."    # Get free key at aistudio.google.com
    model: "gemini-1.5-flash"
```

See [docs/llm-providers.md](docs/llm-providers.md) for all options.

### 4. Add Your Notes

```
my-learning/
└── 00_inbox/
    └── personal_notes/    ← Put your .md files here
```

### 5. Run

```bash
learninglog intake     # Detect and register new files
learninglog queue      # See processing priority
learninglog extract    # Generate notes with LLM
```

## Commands

| Command | Description |
|---------|-------------|
| `learninglog init [path]` | Create project folder structure |
| `learninglog intake` | Auto-register new files |
| `learninglog queue` | View processing queue |
| `learninglog extract` | Run LLM: extract facts + working notes |
| `learninglog status` | Show pipeline summary |
| `learninglog doctor` | Diagnose config and LLM connection |

## LLM Options

| Option | Cost | Setup | Speed | Privacy |
|--------|------|-------|-------|---------|
| **Gemini** | Free (1,500/day) | Easy | Fast | Cloud |
| **Groq** | Free (14,400/day) | Easy | Very fast | Cloud |
| **Ollama** | Free forever | App install | Local speed | Local (best) |
| **Claude** | Paid | Easy | Fast | Cloud |
| **OpenAI** | Paid | Easy | Fast | Cloud |

## Requirements

- Python 3.10+
- Git Bash or any terminal
- One LLM option configured (see table above)
