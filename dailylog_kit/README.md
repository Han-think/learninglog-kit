# DailyLog Kit 1.2

DailyLog Kit turns a quick daily brain dump into a small Markdown daily log.

It is intentionally separate from LearningLog publishing:

- DailyLog Kit creates local `output/*.md` files.
- LearningLog creates reviewed learning/project blog drafts.
- DailyLog Kit does not run Hugo, publish to a blog, or push to Git.

## Quick Start

```powershell
.\DailyLog.bat
```

or:

```powershell
pwsh -File .\dailylog.ps1
```

Pick categories, write a free-form memo, then press Enter on an empty line.

## LLM Options

DailyLog Kit works without an LLM. If an LLM is available, it can summarize each category and create a one-line reflection.

| Provider | Setup | Example |
|----------|-------|---------|
| Template only | No key, no server | `.\dailylog.ps1 -NoLLM` |
| Ollama | Local Ollama server | `.\dailylog.ps1 -Provider ollama` |
| Gemini | Google AI Studio API key | `.\dailylog.ps1 -Provider gemini -GeminiApiKey "YOUR_KEY"` |

## Gemini API Key

Get a free key from:

```text
https://aistudio.google.com/app/apikey
```

Use it once without saving:

```powershell
.\dailylog.ps1 -Provider gemini -GeminiApiKey "YOUR_KEY"
```

Save it locally for later runs:

```powershell
.\dailylog.ps1 -Provider gemini -GeminiApiKey "YOUR_KEY" -SaveGeminiKey
```

The saved key goes to:

```text
dailylog.config.json
```

That file is ignored by Git and should not be uploaded.

You can also use an environment variable:

```powershell
$env:GEMINI_API_KEY = "YOUR_KEY"
.\dailylog.ps1 -Provider gemini
```

## Parameters

```powershell
.\dailylog.ps1 -Date 2026-07-06
.\dailylog.ps1 -Provider auto
.\dailylog.ps1 -Provider gemini -GeminiModel gemini-2.5-flash
.\dailylog.ps1 -Provider ollama -Model gemma3:12b
.\dailylog.ps1 -OutDir D:\logs
.\dailylog.ps1 -NoOpen
.\dailylog.ps1 -NoLLM
```

`-Provider auto` prefers a saved/env Gemini key, then Ollama, then template mode.

## Output

```markdown
---
title: "2026-07-06 데일리 로그"
date: 2026-07-06
categories: ["daily"]
tags: ["학습", "개발"]
---

## 오늘의 포인트
- 학습: SQL 문제 풀이 감각을 정리함
- 개발: LearningLog와 DailyLog 역할을 분리함

## 한 줄 회고
도구의 역할을 나누면서 기록 흐름이 덜 헷갈리게 됐다.
```

## Version

- DailyLog Kit: `1.2`
- Added Gemini API key support.
- Kept Ollama and template-only modes.
