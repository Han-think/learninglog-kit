# Gemini API 키 발급 가이드 / Gemini API Key Setup

**한국어** | [English](#english)

> ⚠️ API 키는 절대 공개하지 마세요. GitHub, 카카오톡, 메신저 어디에도 올리면 안 됩니다.

---

## 한국어

### 1단계 — Google AI Studio 접속

브라우저에서 아래 주소로 이동합니다:

```
https://aistudio.google.com/app/apikey
```

> 구글 계정이 필요합니다. 없다면 [accounts.google.com](https://accounts.google.com) 에서 무료로 만드세요.

---

### 2단계 — 로그인

구글 계정으로 로그인합니다.
처음 접속하면 이용약관 동의 화면이 나올 수 있습니다. **동의(Agree)** 클릭.

---

### 3단계 — API 키 생성

1. 화면 왼쪽 메뉴에서 **"Get API key"** 또는 **"API keys"** 클릭
2. 파란색 버튼 **"Create API key"** 클릭
3. 프로젝트 선택 화면이 나오면:
   - 기존 프로젝트 선택, 또는
   - **"Create API key in new project"** 클릭 (추천)
4. `AIzaSy...` 형태의 키가 생성됩니다

---

### 4단계 — 키 복사

생성된 키 옆의 **복사 아이콘** 클릭 또는 키를 직접 드래그해서 복사합니다.

> ⚠️ 이 키는 **다시 볼 수 없습니다**. 지금 바로 안전한 곳에 저장하세요.
> (메모장, 비밀번호 앱 등 — 절대 메신저/SNS/GitHub 금지)

---

### 5단계 — 환경변수로 설정 (권장)

키를 파일에 직접 쓰지 않고 환경변수로 관리하면 실수로 공개될 위험이 없습니다.

**Git Bash 에서:**
```bash
echo 'export GEMINI_API_KEY="여기에_복사한_키_붙여넣기"' >> ~/.bashrc
source ~/.bashrc
```

**확인:**
```bash
echo $GEMINI_API_KEY
# AIzaSy... 가 출력되면 성공
```

---

### 6단계 — config.yaml 설정

`.learninglog/config.yaml` 파일을 열고:

```yaml
llm:
  provider: "gemini"        # "none" 에서 "gemini" 로 변경
  gemini:
    api_key: ""             # 환경변수 사용 시 비워두세요
    model: "gemini-2.5-flash"
```

환경변수 설정이 어렵다면 api_key 에 직접 입력해도 됩니다.
단, 이 경우 `.gitignore` 에 `.learninglog/config.yaml` 이 포함되어 있는지 꼭 확인하세요.

---

### 7단계 — 연결 확인

```bash
learninglog doctor
```

```
  LLM provider : gemini
  LLM 상태     : OK         ← 이렇게 나오면 성공
```

---

### 무료 한도 안내

| 항목 | 한도 |
|------|------|
| 분당 요청 수 | 15회 |
| 일일 요청 수 | 1,500회 |
| 분당 토큰 수 | 1,000,000 |

**개인 학습 노트 기준으로 하루 1,500회는 충분히 넉넉합니다.**
(노트 10개 처리 시 약 20회 사용)

---

### 자주 묻는 질문

**Q: 신용카드 등록이 필요한가요?**
A: 아니요. 구글 계정만 있으면 무료로 사용할 수 있습니다.

**Q: 한도를 초과하면 어떻게 되나요?**
A: 요청이 실패하고 오류 메시지가 나옵니다. 요금이 청구되지 않습니다.

**Q: 키를 실수로 공개했어요.**
A: Google AI Studio 에서 해당 키를 즉시 삭제하고 새 키를 발급받으세요.

---

---

## English

> ⚠️ Never share your API key publicly — not on GitHub, messaging apps, or social media.

### Step 1 — Go to Google AI Studio

Open your browser and go to:

```
https://aistudio.google.com/app/apikey
```

You need a Google account. Create one free at [accounts.google.com](https://accounts.google.com) if you don't have one.

---

### Step 2 — Sign In

Sign in with your Google account.
If you see a Terms of Service page, click **Agree**.

---

### Step 3 — Create API Key

1. Click **"Get API key"** or **"API keys"** in the left menu
2. Click the blue **"Create API key"** button
3. Select a project or click **"Create API key in new project"** (recommended)
4. Your key will appear — it starts with `AIzaSy...`

---

### Step 4 — Copy Your Key

Click the copy icon next to the key, or select and copy it manually.

> ⚠️ **Save it somewhere safe right now.** You won't be able to see it again.
> Use a password manager or notes app — never paste it into chat apps or GitHub.

---

### Step 5 — Set as Environment Variable (Recommended)

**In Git Bash:**
```bash
echo 'export GEMINI_API_KEY="paste-your-key-here"' >> ~/.bashrc
source ~/.bashrc
```

**Verify:**
```bash
echo $GEMINI_API_KEY
# Should print AIzaSy...
```

---

### Step 6 — Configure

Open `.learninglog/config.yaml`:

```yaml
llm:
  provider: "gemini"
  gemini:
    api_key: ""             # Leave empty — reads from environment variable
    model: "gemini-2.5-flash"
```

---

### Step 7 — Verify

```bash
learninglog doctor
```

You should see `LLM status: OK`.

---

### Free Tier Limits

| Item | Limit |
|------|-------|
| Requests per minute | 15 |
| Requests per day | 1,500 |
| Tokens per minute | 1,000,000 |

For personal notes, 1,500 requests/day is more than enough.
(Processing 10 notes uses about 20 requests.)

---

### FAQ

**Q: Do I need a credit card?**
A: No. A Google account is all you need.

**Q: What happens if I exceed the limit?**
A: Requests fail with an error. You won't be charged.

**Q: I accidentally shared my key.**
A: Delete it immediately in Google AI Studio and create a new one.
