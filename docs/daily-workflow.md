# 하루 학습 기록 권장 방법 / Daily Learning Workflow

**한국어** | [English](#english)

---

## 한국어

### 핵심 원칙: 한 번에 다 넣지 않는다

하루 배운 것을 한 파일에 전부 넣으면 LLM이 맥락을 제대로 처리하지 못합니다.
**강의 시간 단위로 나눠서** 파일을 만드는 것을 권장합니다.

---

### 권장 파일 구조

```
00_inbox/personal_notes/
│
├── PN_2026-05-30_01_python-basics.md        ← 오전 강의
├── PN_2026-05-30_02_web-server-http.md      ← 오후 강의
└── PN_2026-05-30_03_git-github-review.md    ← 저녁 복습
```

**파일명 규칙:**
```
PN_YYYY-MM-DD_순번_주제.md
```

---

### 왜 나눠야 하나?

| 한 파일에 전부 | 시간대별로 분리 |
|--------------|---------------|
| LLM 맥락 혼선 | 각 주제 명확히 처리 |
| 나중에 찾기 어려움 | 주제별 검색 가능 |
| 토큰 초과 가능성 | 청킹 최소화 |
| 블로그 1편이 너무 길어짐 | 편당 적절한 분량 |

---

### LLM(Gemini/ChatGPT)으로 노트 만드는 법

강의가 끝난 후, Gemini나 ChatGPT에게 아래 형식으로 요청하세요.

#### 요청 템플릿 복사해서 사용:

```
오늘 [강의 주제] 수업을 들었어.
아래 형식의 마크다운 파일로 정리해줘.

---
# PN_[날짜]_[순번]_[주제]

## 오늘 배운 핵심 내용
(3~5줄로 요약)

## 헷갈렸던 것
(무엇이 어려웠는지)

## 이해한 방식
(내 말로 다시 설명)

## 실습했거나 해보고 싶은 것
(실제 예시 또는 시도)

## 초보자 키워드
- 용어: 의미 (검색어)

## 다음에 확인할 것
(아직 모르는 것, 궁금한 것)
---

오늘 수업 내용은 다음과 같아:
[여기에 수업 내용 또는 필기 붙여넣기]
```

---

### 강의 자료(PDF) 처리 방법

강의 PDF는 **저작권 보호**를 위해 원문을 그대로 발행하지 않습니다.

```
00_inbox/lectures/강의명.pdf    ← 여기에 저장 (internal-only 자동 분류)
        ↓
강의를 듣고 내가 이해한 것을
personal_notes/ 에 노트로 작성
        ↓
그 노트가 블로그로 발행됨
```

> 강의 PDF 자체는 절대 블로그에 올라가지 않습니다.

---

### 하루 흐름 예시

```
오전 9시  수업 → 점심에 Gemini에게 요청 → PN_01_주제.md 생성
오후 1시  수업 → 수업 후 바로 요청     → PN_02_주제.md 생성
오후 5시  실습 → 저녁에 요청           → PN_03_실습.md 생성

저녁:
learninglog intake   → 3개 파일 자동 등록
learninglog extract  → 노트 처리 + draft 생성
→ 블로그에 오늘 학습 3편 자동 발행
```

---

### AI 보조 마킹

이 파이프라인으로 생성된 블로그 글에는 자동으로 표시됩니다:

```yaml
ai_assisted: true
ai_model: "gemma3:4b"
```

독자들이 AI 보조로 작성된 글임을 알 수 있습니다.
**학습 내용과 해석은 본인의 것**이며, AI는 정리를 도운 것입니다.

---

---

## English

### Core Principle: Don't dump everything at once

Putting all day's learning into one file causes LLM context issues.
**Separate files by class/lecture time** is strongly recommended.

---

### Recommended File Structure

```
00_inbox/personal_notes/
│
├── PN_2026-05-30_01_python-basics.md        ← Morning class
├── PN_2026-05-30_02_web-server-http.md      ← Afternoon class
└── PN_2026-05-30_03_git-github-review.md    ← Evening review
```

**Naming rule:**
```
PN_YYYY-MM-DD_sequence_topic.md
```

---

### Why Separate Files?

| All in one file | Separated by time slot |
|----------------|----------------------|
| LLM context confusion | Each topic handled clearly |
| Hard to find later | Searchable by topic |
| Token overflow risk | Minimal chunking needed |
| Blog posts too long | Appropriate length per post |

---

### Creating Notes with LLM (Gemini/ChatGPT)

After each class, ask Gemini or ChatGPT using this template:

#### Copy and use this template:

```
I attended a [topic] class today.
Please organize it into a markdown file with this format:

---
# PN_[date]_[sequence]_[topic]

## Key concepts learned today
(3-5 bullet points)

## What was confusing
(what was difficult)

## How I understood it
(explain in my own words)

## What I practiced or want to try
(actual examples or attempts)

## Beginner keywords
- term: meaning (search phrase)

## Things to check next
(what I still don't know)
---

Here's what we covered in class today:
[paste your notes or class content here]
```

---

### Lecture Materials (PDF) Handling

Lecture PDFs are kept **internal-only** to protect copyright.

```
00_inbox/lectures/lecture.pdf    ← Store here (auto: internal-only)
        ↓
Write your personal understanding
in personal_notes/ as a note
        ↓
That note becomes a blog post
```

> Lecture PDFs themselves never get published to the blog.

---

### Example Daily Flow

```
9 AM  class → ask Gemini at lunch  → PN_01_topic.md
1 PM  class → ask right after      → PN_02_topic.md
5 PM  lab   → ask in the evening   → PN_03_lab.md

Evening:
learninglog intake   → auto-register 3 files
learninglog extract  → process notes + generate drafts
→ 3 blog posts from today's learning auto-published
```

---

### AI-Assisted Marking

Posts generated through this pipeline are automatically marked:

```yaml
ai_assisted: true
ai_model: "gemma3:4b"
```

Readers can see the post was AI-assisted.
**The learning content and interpretation are yours** — AI just helped organize it.
