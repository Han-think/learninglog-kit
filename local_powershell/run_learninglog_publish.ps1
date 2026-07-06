#Requires -Version 7.0
<#
.SYNOPSIS
    LearningLog Publish — 승인된 draft 를 blog-source 에 복사 + git push

.DESCRIPTION
    하는 것:
      - 04_blog_drafts\ 의 .md 파일 목록 표시
      - 선택한 파일(들)을 blog-source\content\{section}\ 에 복사
      - front matter 에서 draft:true → false, source_id 제거, ai_assisted 마킹 추가
      - git add + git commit + git push
      - source_registry.csv status → published

    하지 않는 것:
      - 원본 파일 수정/삭제 없음
      - 명시 선택 없이 자동 발행 없음

.PARAMETER All
    모든 draft 를 한번에 발행 (기본: 선택 메뉴)

.PARAMETER DraftPath
    특정 draft 파일 경로 지정

.PARAMETER IncludePublished
    이미 blog-source/content 에 있는 글도 갱신 대상으로 포함한다. 기본값은 신규 글만 발행한다.

.PARAMETER IncludeBacklog
    오늘 날짜가 아닌 과거 승인본도 신규 발행 후보에 포함한다. 기본값은 오늘 승인본만 발행한다.

.PARAMETER Section
    특정 섹션만 발행 후보에 포함한다. 예: learning, projects

.NOTES
    blog-source 경로: $BlogSourceRoot 변수에서 설정
#>

param(
    [switch]$All,
    [string]$DraftPath = "",
    [switch]$IncludePublished,
    [switch]$IncludeBacklog,
    [string]$Section = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "_local_core\LearningLog.LocalCore.psm1") -Force -DisableNameChecking

# ─────────────────────────────────────────────────────────
# 경로 설정
# ─────────────────────────────────────────────────────────
$Root           = Get-LLRoot
$DraftsDir      = Get-LLPath "05_ready_to_publish"   # 승인된 글만 발행 (04 직접 발행 차단)
$PublishedDir   = Get-LLPath "06_published"
$RegistryPath   = Get-LLRegistryPath
$BlogSourceRoot = "C:\Ollama-IPEX\blog-source"   # Hugo 사이트 루트

$RunDT    = Get-Date
$RunTime  = $RunDT.ToString("yyyy-MM-dd HH:mm:ss")
$TodayStr = $RunDT.ToString("yyyy-MM-dd")
$SectionFilter = $Section.Trim().ToLowerInvariant()

$fence = '```'

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

$schema = Ensure-LLRegistrySchema
if ($schema.upgraded -and $schema.backup) {
    Write-Host ("  registry upgraded: {0}" -f $schema.backup) -ForegroundColor Yellow
}
Write-Host "  LearningLog Publish" -ForegroundColor Cyan
Write-Host "  $RunTime" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────
# blog-source 존재 확인
# ─────────────────────────────────────────────────────────
if (-not (Test-Path $BlogSourceRoot)) {
    Write-Host "  [ERROR] blog-source 폴더 없음: $BlogSourceRoot" -ForegroundColor Red
    Write-Host "  blog-source 경로를 스크립트 상단 \$BlogSourceRoot 에서 수정하세요." -ForegroundColor Yellow
    exit 1
}

# git 설치 확인
try { $null = git --version 2>&1 } catch {
    Write-Host "  [ERROR] git 명령어를 찾을 수 없습니다. Git 이 설치되어 있는지 확인하세요." -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────────────────
# draft 파일 목록 수집
# ─────────────────────────────────────────────────────────
function New-PublishPlan {
    param([Parameter(Mandatory)]$Draft)

    $rel = $Draft.FullName.Replace($DraftsDir + "\", "").Replace("\", "/")
    $section = ($rel -split "/")[0]
    $fname = $Draft.Name
    $destDir = Join-Path $BlogSourceRoot "content\$section"
    $destPath = Join-Path $destDir $fname
    $isUpdate = Test-Path -LiteralPath $destPath

    return [pscustomobject]@{
        Draft = $Draft
        Rel = $rel
        Section = $section
        FileName = $fname
        DestDir = $destDir
        DestPath = $destPath
        IsUpdate = $isUpdate
    }
}

function Test-PublishSection {
    param([Parameter(Mandatory)]$Draft)
    if (-not $SectionFilter) { return $true }
    $rel = $Draft.FullName.Replace($DraftsDir + "\", "").Replace("\", "/")
    $sectionName = (($rel -split "/")[0]).ToLowerInvariant()
    return ($sectionName -eq $SectionFilter)
}

$excludedPublished = 0
$excludedBacklog = 0

function Test-TodayDraft {
    param([Parameter(Mandatory)]$Draft)

    if ($IncludeBacklog) { return $true }
    if ($Draft.Name -like "$TodayStr*") { return $true }
    if ($Draft.LastWriteTime.ToString("yyyy-MM-dd") -eq $TodayStr) { return $true }
    return $false
}

if ($DraftPath -ne "") {
    $targets = @(Get-Item $DraftPath -ErrorAction SilentlyContinue)
    if ($SectionFilter) { $targets = @($targets | Where-Object { Test-PublishSection $_ }) }
} elseif ($All) {
    $allDrafts = @(Get-ChildItem -Path $DraftsDir -Recurse -Filter "*.md" -File | Sort-Object FullName)
    if ($SectionFilter) { $allDrafts = @($allDrafts | Where-Object { Test-PublishSection $_ }) }
    if (-not $IncludePublished) {
        $visibleDrafts = @($allDrafts | Where-Object { -not (New-PublishPlan -Draft $_).IsUpdate })
        $excludedPublished = $allDrafts.Count - $visibleDrafts.Count
        $allDrafts = $visibleDrafts
    }
    if (-not $IncludeBacklog) {
        $visibleDrafts = @($allDrafts | Where-Object { Test-TodayDraft -Draft $_ })
        $excludedBacklog = $allDrafts.Count - $visibleDrafts.Count
        $allDrafts = $visibleDrafts
    }
    $targets = $allDrafts
} else {
    # 대화형 선택
    $allDrafts = @(Get-ChildItem -Path $DraftsDir -Recurse -Filter "*.md" -File | Sort-Object FullName)
    if ($SectionFilter) { $allDrafts = @($allDrafts | Where-Object { Test-PublishSection $_ }) }
    if ($allDrafts.Count -eq 0) {
        if ($SectionFilter) {
            Write-Host ("  발행할 승인본이 없습니다. (section={0})" -f $SectionFilter) -ForegroundColor Yellow
        } else {
            Write-Host "  발행할 승인본이 없습니다 (05_ready_to_publish 비어 있음)." -ForegroundColor Yellow
        }
        Write-Host "  먼저 [V] preview 로 확인하고 [A] approve 로 승인하세요." -ForegroundColor DarkGray
        exit 0
    }

    if (-not $IncludePublished) {
        $visibleDrafts = @($allDrafts | Where-Object { -not (New-PublishPlan -Draft $_).IsUpdate })
        $excludedPublished = $allDrafts.Count - $visibleDrafts.Count
        $allDrafts = $visibleDrafts
    }
    if (-not $IncludeBacklog) {
        $visibleDrafts = @($allDrafts | Where-Object { Test-TodayDraft -Draft $_ })
        $excludedBacklog = $allDrafts.Count - $visibleDrafts.Count
        $allDrafts = $visibleDrafts
    }

    if ($allDrafts.Count -eq 0) {
        Write-Host "  발행할 오늘 신규 승인본이 없습니다." -ForegroundColor Yellow
        if ($excludedPublished -gt 0) {
            Write-Host ("  이미 발행된 승인본 {0} 개는 기본 발행에서 제외했습니다." -f $excludedPublished) -ForegroundColor DarkGray
            Write-Host "  기존 글을 갱신해야 할 때만 -IncludePublished 옵션을 사용하세요." -ForegroundColor DarkGray
        }
        if ($excludedBacklog -gt 0) {
            Write-Host ("  과거 미발행 승인본 {0} 개는 기본 발행에서 제외했습니다." -f $excludedBacklog) -ForegroundColor DarkGray
            Write-Host "  과거 승인본을 발행해야 할 때만 -IncludeBacklog 옵션을 사용하세요." -ForegroundColor DarkGray
        }
        exit 0
    }

    Write-Host ""
    if ($SectionFilter) {
        Write-Host ("  --- 발행 가능한 오늘 신규 승인본 목록 (section={0}) ---" -f $SectionFilter) -ForegroundColor Magenta
    } else {
        Write-Host "  --- 발행 가능한 오늘 신규 승인본 목록 ---" -ForegroundColor Magenta
    }
    for ($i = 0; $i -lt $allDrafts.Count; $i++) {
        $rel = $allDrafts[$i].FullName.Replace($DraftsDir + "\", "").Replace("\", "/")
        Write-Host ("  [{0,2}] {1}" -f ($i + 1), $rel) -ForegroundColor White
    }
    if ($excludedPublished -gt 0) {
        Write-Host ("  이미 발행된 승인본 제외: {0} 개 (-IncludePublished 로 갱신 모드)" -f $excludedPublished) -ForegroundColor DarkGray
    }
    if ($excludedBacklog -gt 0) {
        Write-Host ("  과거 미발행 승인본 제외: {0} 개 (-IncludeBacklog 로 포함)" -f $excludedBacklog) -ForegroundColor DarkGray
    }
    Write-Host "  [ A] 전체 발행" -ForegroundColor Yellow
    Write-Host "  [ Q] 취소" -ForegroundColor DarkGray
    Write-Host ""

    $input = Read-Host "  번호 입력 (쉼표로 여러 개 가능, 예: 1,3,5)"
    $input = $input.Trim().ToUpper()

    if ($input -eq "Q" -or $input -eq "") { Write-Host "  취소됨." -ForegroundColor DarkGray; exit 0 }

    if ($input -eq "A") {
        $targets = $allDrafts
    } else {
        $indices = $input -split "," | ForEach-Object { [int]$_.Trim() - 1 }
        $targets = @($indices | ForEach-Object { $allDrafts[$_] } | Where-Object { $null -ne $_ })
    }
}

if ($targets.Count -eq 0) {
    Write-Host "  선택된 파일 없음." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host ("  발행 대상: {0} 개" -f $targets.Count) -ForegroundColor Yellow

$targetPlans = [System.Collections.Generic.List[object]]::new()
$newTargets = [System.Collections.Generic.List[object]]::new()
$updateTargets = [System.Collections.Generic.List[object]]::new()

foreach ($draft in $targets) {
    $plan = New-PublishPlan -Draft $draft
    $targetPlans.Add($plan)
    if ($plan.IsUpdate) { $updateTargets.Add($plan) } else { $newTargets.Add($plan) }
}

Write-Host ("  신규 추가: {0} 개" -f $newTargets.Count) -ForegroundColor Green
Write-Host ("  기존 글 갱신: {0} 개" -f $updateTargets.Count) -ForegroundColor $(if ($updateTargets.Count -gt 0) { "Yellow" } else { "DarkGray" })

if ($updateTargets.Count -gt 0) {
    Write-Host ""
    Write-Host "  --- 기존 글 갱신 대상 ---" -ForegroundColor Yellow
    foreach ($plan in $updateTargets) {
        Write-Host ("  - {0}/{1}" -f $plan.Section, $plan.FileName) -ForegroundColor Yellow
    }
    Write-Host ""
    $confirmUpdate = (Read-Host "  기존 글을 갱신합니다. 계속할까요? (Y/N)").Trim().ToUpperInvariant()
    if ($confirmUpdate -ne "Y") {
        Write-Host "  취소됨. 복사/빌드/푸시를 시작하지 않았습니다." -ForegroundColor DarkGray
        exit 0
    }
}

# ─────────────────────────────────────────────────────────
# 헬퍼: front matter 처리
# ─────────────────────────────────────────────────────────
function Remove-ExtraHugoFrontMatter {
    param([string]$Text)
    $lines = $Text -split "`r?`n"
    if ($lines.Count -eq 0) { return $Text }

    $start = 0
    if ($lines[0].Trim() -eq "---") {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq "---") {
                $start = $i + 1
                break
            }
        }
    }

    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $start; $i++) { $out.Add($lines[$i]) }

    $i = $start
    while ($i -lt $lines.Count) {
        $isBlock = $false
        $end = -1
        if ($lines[$i].Trim() -eq "---") {
            for ($j = $i + 1; $j -lt [Math]::Min($lines.Count, $i + 20); $j++) {
                if ($lines[$j].Trim() -eq "---") { $end = $j; break }
            }
            if ($end -gt $i) {
                $body = @($lines[($i + 1)..($end - 1)] | ForEach-Object { $_.Trim().ToLowerInvariant() })
                $keyCount = @($body | Where-Object {
                    $_.StartsWith("title:") -or $_.StartsWith("date:") -or $_.StartsWith("draft:") -or
                    $_.StartsWith("categories:") -or $_.StartsWith("tags:") -or $_.StartsWith("description:")
                }).Count
                $hasTitle = @($body | Where-Object { $_.StartsWith("title:") }).Count -gt 0
                $hasDateOrDraft = @($body | Where-Object { $_.StartsWith("date:") -or $_.StartsWith("draft:") }).Count -gt 0
                $isBlock = $hasTitle -and $hasDateOrDraft -and ($keyCount -ge 3)
            }
        }

        if ($isBlock) {
            while ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq "") { $out.RemoveAt($out.Count - 1) }
            if ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq "---") { $out.RemoveAt($out.Count - 1) }
            $i = $end + 1
            while ($i -lt $lines.Count -and $lines[$i].Trim() -eq "") { $i++ }
            continue
        }

        $out.Add($lines[$i])
        $i++
    }

    return (($out -join "`n").TrimEnd() + "`n")
}

function Process-FrontMatter {
    param(
        [string]$Content,
        [string]$ModelName = "local-llm"
    )

    return (ConvertTo-LLPublishMarkdown -Content $Content -ModelName $ModelName)
}

# ─────────────────────────────────────────────────────────
# 헬퍼: registry status → published
# ─────────────────────────────────────────────────────────
function _UpdateRegistry {
    param([string]$Sid)
    $null = Set-LLRegistryStatus -SourceId $Sid -Status "published"
}

function Get-HugoCommandPath {
    $cmd = Get-Command hugo -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $knownRoot = "C:\Users\Lenovo\AppData\Local\Microsoft\WinGet\Packages"
    if (Test-Path -LiteralPath $knownRoot) {
        $found = Get-ChildItem -LiteralPath $knownRoot -Recurse -Filter "hugo.exe" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like "*Hugo.Hugo.Extended*" } |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return ""
}

function Get-DraftRegistryRow {
    param(
        [string]$DraftName,
        [string]$RawContent
    )
    $sid = ""
    $RawContent | Select-String "source_id:\s*(\S+)" | ForEach-Object {
        $sid = $_.Matches[0].Groups[1].Value.Trim()
    }
    $rows = Get-LLRegistryRows
    if ($sid) {
        return ($rows | Where-Object { $_.source_id -eq $sid } | Select-Object -First 1)
    }
    $topic = [System.IO.Path]::GetFileNameWithoutExtension($DraftName)
    return ($rows | Where-Object { $_.topic -eq $topic } | Select-Object -First 1)
}

function Get-FrontMatterValue {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Key
    )
    $pattern = "(?m)^$([regex]::Escape($Key)):\s*`"?(.+?)`"?\s*$"
    if ($Content -match $pattern) { return $Matches[1].Trim() }
    return ""
}

function Test-DraftQualityGate {
    param(
        [Parameter(Mandatory)][string]$DraftName,
        [Parameter(Mandatory)][string]$RawContent,
        $SourceRow
    )

    $issues = @(Get-LLDraftQualityIssues -Content $RawContent)
    if ($issues.Count -gt 0) {
        return [pscustomobject]@{ Ok = $false; Reason = "draft quality: " + ($issues -join ", ") }
    }

    if ($null -ne $SourceRow) {
        $status = (Get-LLProp $SourceRow "status").ToLowerInvariant()
        if ($status -in @("needs_review", "archived", "rejected")) {
            return [pscustomobject]@{ Ok = $false; Reason = "status gate: $status" }
        }

        $topic = (Get-LLProp $SourceRow "topic").ToLowerInvariant()
        $category = (Get-LLProp $SourceRow "source_category").ToLowerInvariant()
        $draftTitle = (Get-FrontMatterValue -Content $RawContent -Key "title").ToLowerInvariant()

        # High-signal mismatch guard for single-source drafts only.
        # Daily merged posts can legitimately mention several topics in the title.
        $isDailyMerged = ($category -eq "daily_merged" -or $topic -match '^\d{4}-\d{2}-\d{2}-(am|pm)-daily$')
        $looksLikePandas = ($draftTitle -match "pandas|read[_\. -]?csv|\bcsv\b")
        $sourceIsPandas = ($topic -match "pandas|read[_\. -]?csv|\bcsv\b")
        if (-not $isDailyMerged -and $looksLikePandas -and -not $sourceIsPandas) {
            return [pscustomobject]@{
                Ok = $false
                Reason = "title/topic mismatch: title looks like pandas/read_csv but topic is '$topic'"
            }
        }
    }

    return [pscustomobject]@{ Ok = $true; Reason = "" }
}

# ─────────────────────────────────────────────────────────
# 발행 처리
# ─────────────────────────────────────────────────────────
$publishedCount = 0
$publishedNewCount = 0
$publishedUpdateCount = 0
$errors         = [System.Collections.Generic.List[string]]::new()

foreach ($targetPlan in $targetPlans) {
    $draft   = $targetPlan.Draft
    $rel     = $targetPlan.Rel
    $section = $targetPlan.Section
    $fname   = $targetPlan.FileName

    Write-Host ""
    Write-Host ("  >> {0}" -f $rel) -ForegroundColor Magenta

    # 대상 경로
    $destDir  = $targetPlan.DestDir
    $destPath = $targetPlan.DestPath

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    try {
        $raw       = [System.IO.File]::ReadAllText($draft.FullName, [System.Text.Encoding]::UTF8)
        $sourceRow = Get-DraftRegistryRow -DraftName $fname -RawContent $raw
        if ($null -ne $sourceRow -and -not (Test-LLPublishableSource $sourceRow)) {
            Write-Host ("     [SKIP] publish policy gate: {0}/{1}" -f $sourceRow.source_id, $sourceRow.public_policy) -ForegroundColor Yellow
            continue
        }
        # front matter 처리 및 publish 직전 검수
        $processed = Process-FrontMatter -Content $raw
        $quality = Test-DraftQualityGate -DraftName $fname -RawContent $processed -SourceRow $sourceRow
        if (-not $quality.Ok) {
            Write-Host ("     [SKIP] quality gate: {0}" -f $quality.Reason) -ForegroundColor Yellow
            continue
        }

        [System.IO.File]::WriteAllText($destPath, $processed, [System.Text.Encoding]::UTF8)
        Write-Host ("     복사: {0}" -f $destPath.Replace($BlogSourceRoot, "blog-source")) -ForegroundColor Green

        # 06_published 기록
        if (-not (Test-Path $PublishedDir)) { New-Item -ItemType Directory -Path $PublishedDir -Force | Out-Null }
        [System.IO.File]::WriteAllText((Join-Path $PublishedDir $fname), $processed, [System.Text.Encoding]::UTF8)

        # source_id가 없는 daily 합본은 파일명/topic 매칭으로 registry 업데이트
        $sid = ""
        $raw | Select-String "source_id:\s*(\S+)" | ForEach-Object {
            $sid = $_.Matches[0].Groups[1].Value.Trim()
        }
        if (-not $sid -and $null -ne $sourceRow) {
            $sid = Get-LLProp $sourceRow "source_id"
        }
        if ($sid) { _UpdateRegistry $sid }

        $publishedCount++
        if ($targetPlan.IsUpdate) { $publishedUpdateCount++ } else { $publishedNewCount++ }

    } catch {
        Write-Host ("     [ERROR] {0}" -f $_.Exception.Message) -ForegroundColor Red
        $errors.Add($rel)
    }
}

# ─────────────────────────────────────────────────────────
# Hugo 빌드 + 배포 (public submodule 먼저, blog-source 나중)
#   STRUCTURE.md 5장 순서 준수
# ─────────────────────────────────────────────────────────
if ($publishedCount -gt 0) {
    $deployOk = $false
    $PublicDir = Join-Path $BlogSourceRoot "public"

    # hugo CLI 확인
    $hugoCmd = Get-HugoCommandPath
    if (-not $hugoCmd) {
        Write-Host ""
        Write-Host "  [ERROR] hugo 명령을 찾을 수 없습니다. Hugo 설치/PATH 확인 필요." -ForegroundColor Red
        Write-Host "  글은 04_blog_drafts → content 로 복사됐지만 라이브 배포는 건너뜁니다." -ForegroundColor Yellow
        Write-Host "  수동 배포: STRUCTURE.md 5장 참고" -ForegroundColor DarkGray
        exit 1
    } else {
        # ── 1. Hugo 빌드 → public/ 에 HTML 생성 ──
        Write-Host ""
        Write-Host "  [1/3] Hugo 빌드 중..." -ForegroundColor Cyan
        Push-Location $BlogSourceRoot
        & $hugoCmd --cleanDestinationDir --logLevel warn
        $hugoExit = $LASTEXITCODE
        Pop-Location

        if ($hugoExit -ne 0) {
            Write-Host "  [ERROR] Hugo 빌드 실패 (exit $hugoExit). 배포 중단." -ForegroundColor Red
            exit $hugoExit
        } else {
            Write-Host "  Hugo 빌드 완료" -ForegroundColor Green

            # ── 2. 라이브 사이트(public submodule) 먼저 푸시 ──
            Write-Host "  [2/3] 라이브 사이트(public) 푸시 중..." -ForegroundColor Cyan
            Push-Location $PublicDir
            git add -A
            $pubAdd = $LASTEXITCODE
            if ($pubAdd -ne 0) {
                Pop-Location
                Write-Host "  [ERROR] public git add 실패" -ForegroundColor Red
                exit $pubAdd
            }
            git diff --cached --quiet
            $pubHasNoStagedChanges = ($LASTEXITCODE -eq 0)
            if ($pubHasNoStagedChanges) {
                Write-Host "  public 커밋할 변경 없음" -ForegroundColor DarkGray
            } else {
                git commit -m "LearningLog publish: $publishedCount posts ($TodayStr)" 2>&1 | Out-Host
                $pubCommit = $LASTEXITCODE
                if ($pubCommit -ne 0) {
                    Pop-Location
                    Write-Host "  [ERROR] public 커밋 실패" -ForegroundColor Red
                    exit $pubCommit
                }
            }
            git push origin main
            $pubPush = $LASTEXITCODE
            Pop-Location
            if ($pubPush -eq 0) { Write-Host "  라이브 사이트 푸시 완료" -ForegroundColor Green }
            else {
                Write-Host "  [ERROR] public 푸시 실패" -ForegroundColor Red
                exit $pubPush
            }

            # ── 3. 소스 백업 푸시 ──
            Write-Host "  [3/3] 소스(blog-source) 백업 푸시 중..." -ForegroundColor Cyan
            Push-Location $BlogSourceRoot
            git add -A
            $sourceAdd = $LASTEXITCODE
            if ($sourceAdd -ne 0) {
                Pop-Location
                Write-Host "  [ERROR] blog-source git add 실패" -ForegroundColor Red
                exit $sourceAdd
            }
            git diff --cached --quiet
            $sourceHasNoStagedChanges = ($LASTEXITCODE -eq 0)
            if ($sourceHasNoStagedChanges) {
                Write-Host "  blog-source 커밋할 변경 없음" -ForegroundColor DarkGray
            } else {
                git commit -m "LearningLog source: $publishedCount posts ($TodayStr)" 2>&1 | Out-Host
                $sourceCommit = $LASTEXITCODE
                if ($sourceCommit -ne 0) {
                    Pop-Location
                    Write-Host "  [ERROR] blog-source 커밋 실패" -ForegroundColor Red
                    exit $sourceCommit
                }
            }
            git push
            $sourcePush = $LASTEXITCODE
            Pop-Location
            if ($sourcePush -ne 0) {
                Write-Host "  [ERROR] blog-source 푸시 실패" -ForegroundColor Red
                exit $sourcePush
            }
            Write-Host "  소스 백업 완료" -ForegroundColor Green
            $deployOk = $true

            Write-Host ""
            Write-Host "  배포 완료! https://han-think.github.io/ 확인" -ForegroundColor Green
        }
    }
}

# ─────────────────────────────────────────────────────────
# 결과
# ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ("  발행 완료: {0} 개" -f $publishedCount) -ForegroundColor Green
Write-Host ("  신규 추가: {0} 개" -f $publishedNewCount) -ForegroundColor Green
Write-Host ("  기존 글 갱신: {0} 개" -f $publishedUpdateCount) -ForegroundColor $(if ($publishedUpdateCount -gt 0) { "Yellow" } else { "DarkGray" })
if ($errors.Count -gt 0) {
    Write-Host ("  오류:      {0} 개" -f $errors.Count) -ForegroundColor Red
}
if ($publishedCount -gt 0) {
    Write-Host "  blog-source 처리 완료" -ForegroundColor DarkGray
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
