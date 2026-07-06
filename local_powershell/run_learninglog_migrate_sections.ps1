#Requires -Version 7.0
<#
.SYNOPSIS
    LearningLog Section Migration — 섹션을 learning/projects 2개로 정리 (2026-06-09 확정 규칙)

.DESCRIPTION
    규칙:
      - 최상위 섹션은 learning / projects 2개만.
      - practice → learning 흡수, goals/posts 폐지.
      - 생성AI · 환경구성 · 데이터셋 · 도구제작 · 패키지배포 → 무조건 projects.
    하는 것:
      - blog-source/content, 04_blog_drafts, 05_ready_to_publish 의 practice/goals/posts 파일을
        키워드 분류로 learning/projects 로 이동.
      - registry target_section 갱신.
    하지 않는 것:
      - 이미 learning/projects 에 있는 파일은 건드리지 않음(범위 한정).
      - git push/hugo 빌드 안 함 (이 스크립트는 파일 이동만; 배포는 별도).

.PARAMETER WhatIfList
    이동하지 않고 분류 결과만 표시.
#>

param([switch]$WhatIfList)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "_local_core\LearningLog.LocalCore.psm1") -Force -DisableNameChecking

$BlogContent = "C:\Ollama-IPEX\blog-source\content"
$OldSections = @("practice", "goals", "posts")

# ── 분류기: 파일명(stem) → learning|projects ──
function Get-LLNewSection {
    param([string]$Stem)
    $n = $Stem.ToLowerInvariant()
    $proj = @(
        'ai-tools','generative','stable-diffusion','audiocraft','magenta','videocrafter','diffusion',
        'environment','-env','conda','colab-local','pip-requirements','ollama-local','venv',
        'package-release','package-environment','classmap','learninglog-kit','local-tool-distribution',
        'pyrecipe','streamlit','dataset','crawl','bookcrawler','llm-design','hallucination'
    )
    foreach ($k in $proj) { if ($n -like "*$k*") { return 'projects' } }
    return 'learning'
}

$RunTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  LearningLog Section Migration" -ForegroundColor Cyan
Write-Host "  $RunTime" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 처리 대상 루트들 (content 는 git mv, 나머지는 Move-Item)
$roots = @(
    @{ Path = $BlogContent; Git = $true },
    @{ Path = (Get-LLPath "04_blog_drafts"); Git = $false },
    @{ Path = (Get-LLPath "05_ready_to_publish"); Git = $false }
)

$plan = [System.Collections.Generic.List[object]]::new()
foreach ($r in $roots) {
    foreach ($sec in $OldSections) {
        $secDir = Join-Path $r.Path $sec
        if (-not (Test-Path -LiteralPath $secDir)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $secDir -Recurse -Filter "*.md" -File)) {
            if ($f.BaseName -eq "_index") { continue }
            $target = Get-LLNewSection -Stem $f.BaseName
            $dest = Join-Path $r.Path (Join-Path $target $f.Name)
            $plan.Add([pscustomobject]@{
                Root = $r.Path; Git = $r.Git; From = $f.FullName; To = $dest
                Stem = $f.BaseName; Target = $target
                RootTag = (Split-Path $r.Path -Leaf)
            })
        }
    }
}

if ($plan.Count -eq 0) { Write-Host "  이동 대상 없음 (이미 정리됨)." -ForegroundColor Green; exit 0 }

# 분류 요약 (content 기준)
Write-Host ""
Write-Host "  --- 분류 결과 (content 기준) ---" -ForegroundColor Magenta
foreach ($p in ($plan | Where-Object { $_.Root -eq $BlogContent } | Sort-Object Target, Stem)) {
    $col = if ($p.Target -eq 'projects') { "Yellow" } else { "Green" }
    Write-Host ("  [{0,-8}] {1}" -f $p.Target, $p.Stem) -ForegroundColor $col
}
Write-Host ""
Write-Host ("  이동 대상 총 {0}건 (content+04+05 합산)" -f $plan.Count) -ForegroundColor White

if ($WhatIfList) { Write-Host "  [WhatIfList] 이동 안 함." -ForegroundColor Yellow; exit 0 }

# ── 이동 실행 ──
$moved = 0
foreach ($p in $plan) {
    $destDir = Split-Path -Parent $p.To
    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    if (Test-Path -LiteralPath $p.To) { Remove-Item -LiteralPath $p.From -Force; continue }  # 이미 동일 대상 존재
    if ($p.Git) {
        Push-Location (Split-Path $p.Root -Parent)
        git -C (Split-Path $p.Root -Parent) mv -f -- $p.From $p.To 2>$null
        if ($LASTEXITCODE -ne 0) { Move-Item -LiteralPath $p.From -Destination $p.To -Force }
        Pop-Location
    } else {
        Move-Item -LiteralPath $p.From -Destination $p.To -Force
    }
    $moved++
}

# ── 빈 옛 섹션 폴더 정리 (content/04/05) ──
foreach ($r in $roots) {
    foreach ($sec in $OldSections) {
        $secDir = Join-Path $r.Path $sec
        if (-not (Test-Path -LiteralPath $secDir)) { continue }
        $remain = @(Get-ChildItem -LiteralPath $secDir -Recurse -Filter "*.md" -File | Where-Object { $_.BaseName -ne "_index" })
        if ($remain.Count -eq 0) { Remove-Item -LiteralPath $secDir -Recurse -Force }
    }
}

# ── registry target_section 갱신 ──
$regPath = Get-LLRegistryPath
$rows = @(Import-Csv -LiteralPath $regPath -Encoding utf8)
$changed = 0
foreach ($row in $rows) {
    $hasTs = $row.PSObject.Properties['target_section']
    if (-not $hasTs) { continue }
    if ($row.target_section -in $OldSections) {
        $row.target_section = Get-LLNewSection -Stem ([string]$row.topic)
        $changed++
    }
}
if ($changed -gt 0) { $rows | Export-Csv -LiteralPath $regPath -Encoding utf8 -NoTypeInformation }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ("  이동: {0}건 / registry 갱신: {1}건" -f $moved, $changed) -ForegroundColor Green
Write-Host "  다음: blog-source 에서 hugo 빌드 + git push (또는 publish 스크립트)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
exit 0
