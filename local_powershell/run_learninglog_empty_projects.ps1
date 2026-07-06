#Requires -Version 7.0
<#
.SYNOPSIS
    projects 섹션 비우기 — 학습노트는 learning 으로, 생성/레시피는 .trash 로 내림 (2026-06-09).
.DESCRIPTION
    - content/04/05 의 projects/ 안에서:
        * 생성/레시피(아래 RECIPE 목록) → .trash 백업 후 제거 (블로그에서 내림, 나중에 따로 관리)
        * 그 외(날짜형 학습노트) → learning/ 으로 이동
    - registry target_section projects → learning
    - projects 폴더는 빈 채로 두거나 제거 (배포는 별도)
.PARAMETER WhatIfList  이동 없이 계획만 표시
#>
param([switch]$WhatIfList)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "_local_core\LearningLog.LocalCore.psm1") -Force -DisableNameChecking

$BlogContent = "C:\Ollama-IPEX\blog-source\content"
$Stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$TrashRoot = Get-LLPath ".trash\projects_recipes_$Stamp"

# 블로그에서 내릴 생성/레시피 (날짜 없는 옛 프로젝트성 글)
$RECIPE = @(
    'audiocraft-setup','bookcrawler-pipeline','how-crawling-works','magenta-music-conda',
    'ollama-local-setup','pandas-ai-env','pyrecipe-architecture','stable-diffusion-ipex','videocrafter-local'
)

$roots = @(
    @{ Path = $BlogContent; Git = $true },
    @{ Path = (Get-LLPath "04_blog_drafts"); Git = $false },
    @{ Path = (Get-LLPath "05_ready_to_publish"); Git = $false }
)

$toLearning = [System.Collections.Generic.List[object]]::new()
$toTrash    = [System.Collections.Generic.List[object]]::new()
foreach ($r in $roots) {
    $projDir = Join-Path $r.Path "projects"
    if (-not (Test-Path -LiteralPath $projDir)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $projDir -Filter "*.md" -File)) {
        if ($f.BaseName -eq "_index") { continue }
        if ($RECIPE -contains $f.BaseName) {
            $toTrash.Add([pscustomobject]@{ From = $f.FullName; Root = $r.Path })
        } else {
            $dest = Join-Path $r.Path (Join-Path "learning" $f.Name)
            $toLearning.Add([pscustomobject]@{ From = $f.FullName; To = $dest; Git = $r.Git; Root = $r.Path })
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  projects 비우기" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ("  학습노트 → learning : {0}건" -f $toLearning.Count) -ForegroundColor Green
Write-Host ("  생성/레시피 → .trash : {0}건" -f $toTrash.Count) -ForegroundColor Yellow

if ($WhatIfList) {
    Write-Host "`n  --- learning 이동 (content) ---" -ForegroundColor Green
    $toLearning | Where-Object { $_.Root -eq $BlogContent } | ForEach-Object { Write-Host ("   → {0}" -f (Split-Path $_.From -Leaf)) }
    Write-Host "  --- .trash (content) ---" -ForegroundColor Yellow
    $toTrash | Where-Object { $_.Root -eq $BlogContent } | ForEach-Object { Write-Host ("   ✗ {0}" -f (Split-Path $_.From -Leaf)) }
    exit 0
}

# learning 이동
foreach ($m in $toLearning) {
    $destDir = Split-Path -Parent $m.To
    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    if (Test-Path -LiteralPath $m.To) { Remove-Item -LiteralPath $m.From -Force; continue }
    if ($m.Git) {
        git -C (Split-Path $m.Root -Parent) mv -f -- $m.From $m.To 2>$null
        if ($LASTEXITCODE -ne 0) { Move-Item -LiteralPath $m.From -Destination $m.To -Force }
    } else { Move-Item -LiteralPath $m.From -Destination $m.To -Force }
}

# 레시피 → .trash
foreach ($t in $toTrash) {
    $rel = $t.From.Replace("C:\Ollama-IPEX\", "").Replace("\", "/")
    $dest = Join-Path $TrashRoot $rel
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    if ($t.Root -eq $BlogContent) {
        git -C (Split-Path $t.Root -Parent) rm -f -- $t.From 2>$null
        if ($LASTEXITCODE -ne 0) { Move-Item -LiteralPath $t.From -Destination $dest -Force }
        else { Copy-Item -LiteralPath $dest -Destination $dest -ErrorAction SilentlyContinue }
    } else { Move-Item -LiteralPath $t.From -Destination $dest -Force }
}

# 빈 projects 폴더 제거 (_index 만 남으면 폴더째)
foreach ($r in $roots) {
    $projDir = Join-Path $r.Path "projects"
    if (-not (Test-Path -LiteralPath $projDir)) { continue }
    $remain = @(Get-ChildItem -LiteralPath $projDir -Filter "*.md" -File | Where-Object { $_.BaseName -ne "_index" })
    if ($remain.Count -eq 0) {
        if ($r.Path -eq $BlogContent) { git -C (Split-Path $r.Path -Parent) rm -rf -- $projDir 2>$null }
        if (Test-Path -LiteralPath $projDir) { Remove-Item -LiteralPath $projDir -Recurse -Force }
    }
}

# registry target_section projects → learning
$regPath = Get-LLRegistryPath
$rows = @(Import-Csv -LiteralPath $regPath -Encoding utf8)
$ch = 0
foreach ($row in $rows) { if ($row.PSObject.Properties['target_section'] -and $row.target_section -eq 'projects') { $row.target_section = 'learning'; $ch++ } }
if ($ch -gt 0) { $rows | Export-Csv -LiteralPath $regPath -Encoding utf8 -NoTypeInformation }

Write-Host ""
Write-Host ("  완료. learning 이동 {0} / .trash {1} / registry {2}" -f $toLearning.Count, $toTrash.Count, $ch) -ForegroundColor Green
Write-Host "  다음: hugo 빌드 + push (메뉴/홈 projects 제거 후)" -ForegroundColor Cyan
exit 0
