# learninglog-kit

개인 학습 파이프라인 도구. 노트를 올리면 LLM 이 처리해 블로그 초안까지 만들어줍니다.

## 빠른 시작

```bash
# 1. 설치
pip install learninglog-kit

# 2. 프로젝트 초기화
mkdir my-learning && cd my-learning
learninglog init

# 3. LLM 설정 (무료 옵션)
#    config.yaml 에서 llm.provider 를 gemini 또는 groq 으로 변경
code .learninglog/config.yaml

# 4. 파일 넣기
#    00_inbox/personal_notes/ 에 .md 파일 추가

# 5. 실행
learninglog intake    # 파일 등록
learninglog queue     # 처리 순서 확인
learninglog extract   # LLM 처리
```

## 명령어

| 명령어 | 설명 |
|-------|------|
| `learninglog init` | 프로젝트 폴더 구조 생성 |
| `learninglog intake` | 새 파일 자동 등록 |
| `learninglog queue` | 처리 대기 목록 확인 |
| `learninglog extract` | LLM 으로 extract + working_note 생성 |
| `learninglog status` | 전체 현황 요약 |
| `learninglog doctor` | 설정 및 LLM 연결 진단 |

## LLM 선택

무료로 사용 가능한 옵션이 있습니다. → [docs/llm-providers.md](docs/llm-providers.md)

| Provider | 비용 | 설치 |
|----------|------|------|
| Gemini | 무료 티어 | `pip install learninglog-kit[gemini]` |
| Groq | 무료 티어 | `pip install learninglog-kit[groq]` |
| Ollama | 완전 무료 | 로컬 앱 설치 |
| Claude | 유료 | `pip install learninglog-kit[claude]` |
| OpenAI | 유료 | `pip install learninglog-kit[openai]` |

## 파이프라인

```
00_inbox/  →  intake  →  queue  →  extract  →  03_working_notes/
                                                      ↓
                                              (검토 후) 04_blog_drafts/
                                                      ↓
                                              (승인 후) blog-source/
```

## 요구사항

- Python 3.10+
- Git Bash 또는 터미널
- LLM: 위 표에서 하나 선택
