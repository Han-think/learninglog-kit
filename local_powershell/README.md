# LearningLog Windows Local Runner

This folder contains the Windows PowerShell version of LearningLog. It is the full local workflow for turning raw study material into reviewed blog drafts, project series, and approved posts.

## Start

Run:

```powershell
.\LearningLog.bat
```

The batch file opens:

```text
learninglog_launch.ps1
```

## Main Menu

Use the first screen to choose the kind of work:

```text
[1] LearningLog    study notes and learning blog posts
[2] Projects       multi-part project series
[3] Daily          separate personal daily log
[0] Ollama server
```

`LearningLog` and `Projects` use the same safe publish pipeline, but they are scoped to different sections so old learning posts and project posts do not get mixed accidentally.

## Learning Flow

For daily study material:

```text
intake -> prep -> extract -> blogdraft -> register -> preview -> approve -> publish
```

In the launcher this is grouped as:

- `오늘 자동 처리`: `intake -> prep -> extract`, stopping at working notes.
- `단계별 처리`: run intake, prep, or extract one by one.
- `블로그/발행`: daily learning post generation, registration, preview, approve, publish.
- `점검/관리`: queue, review, cleanup, unpublish, restructure dry-run.

## Project Flow

For portfolio or team-project writeups, use:

```text
Projects -> 시리즈 초안 만들기 -> 초안 등록 -> 미리보기 -> 승인본 이동 -> 발행하기
```

Project drafts are created under:

```text
04_blog_drafts/projects/
```

The project menu passes `-Section projects` to registration, preview, approval, and publish. This keeps project posts separate from daily learning posts.

The included project-series generator can create:

- a custom five-part project skeleton
- a Kaggle House Prices preset with posts for overview, pipeline syntax, analysis tracks, LLM review, and validation/action plan

## Folder Structure

The runner expects this workspace layout:

```text
00_inbox              raw source files
01_registry           CSV registry and source tracking
02_extracted          extracted factual summaries
03_working_notes      personal learning notes
04_blog_drafts        Hugo-style blog drafts
05_ready_to_publish   approved posts waiting for publish
06_published          local copies after publish
07_archive            archived processed material
08_templates          Markdown and CSV templates
09_reports            generated reports, previews, prep packets
_local_core           shared PowerShell module and local assets
```

Section meanings:

```text
learning   class/study learning posts and AM/PM daily learning summaries
practice   practice execution logs
projects   project writeups, analysis series, LLM reviews, validation notes
goals      ideas and future plans
```

## Preview and Approval

Preview opens a local dashboard and shows the original note beside the draft. Daily combined posts show the member source notes in the original-note pane.

By default:

- byproduct drafts are hidden unless `-IncludeByproducts` is used
- already-published drafts are hidden unless `-IncludePublished` is used
- learning menu preview is scoped to `learning`
- project menu preview is scoped to `projects`

Approval keeps the same QA and public-policy gates. Project approval uses `-Section projects -IncludeBacklog`, because project posts may be written across several days.

## Publish Safety

Before publishing, the script checks the final destination path:

```text
blog-source/content/{section}/{filename}.md
```

It then shows:

```text
new additions
existing updates
```

If any existing post will be updated, publish asks for confirmation before copying, building, or pushing anything.

## Unpublish

The unpublish script can remove an already-published post by list selection, file name, slug, or published URL.

## Notes

- Keep `00_inbox` source files immutable.
- Copying into `blog-source/content` should happen only through the explicit publish step.
- Keep `.learninglog/config.yaml` and any API keys outside redistributable zips.
- This runner is Windows-first and expects PowerShell 7.
