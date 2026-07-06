#Requires -Version 7.0
<#
.SYNOPSIS
    LearningLog Cleanup — 차단된(검수 미통과) 초안을 .trash 로 이동 (복구 가능)

.DESCRIPTION
    하는 것:
      - 04_blog_drafts\ 초안 스캔 → Get-LLDraftBadges 로 canApprove 판정
      - 차단된(canApprove=false) 초안만 목록화 + QA 사유 배지 표시
      - 선택한 초안을 .trash\<timestamp>\04_blog_drafts\<section>\ 로 이동 (하드 삭제 아님)
      - 09_reports\cleanup_log.csv 에 이동 기록

    하지 않는 것:
      - 발행본/원본 노트 삭제 없음
      - 영구 삭제 없음 (.trash 로 이동만 — 복구 가능)

.PARAMETER All
    차단된 모든 초안을 한번에 이동
.PARAMETER DryRun
    이동하지 않고 차단 목록만 표시
#>

param(
    [switch]$All,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "_local_core\LearningLog.LocalCore.psm1") -Force -DisableNameChecking

$RunDT     = Get-Date
$RunTime   = $RunDT.ToString("yyyy-MM-dd HH:mm:ss")
$Stamp     = $RunDT.ToString("yyyyMMdd_HHmmss")
$null      = Ensure-LLRegistrySchema
$DraftsDir = Get-LLPath "04_blog_drafts"
$TrashDir  = Get-LLPath ".trash\$Stamp\04_blog_drafts"
$LogPath   = Get-LLPath "09_reports\cleanup_log.csv"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  LearningLog Cleanup (차단 초안 정리)" -ForegroundColor Cyan
Write-Host "  $RunTime" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# registry topic/sid 인덱스 (approve 와 동일 패턴)
$rows = @(Get-LLRegistryRows)
$rowByTopic = @{}
$rowBySid = @{}
foreach ($r in $rows) {
    $t = Get-LLProp $r "topic";     if ($t) { $rowByTopic[$t] = $r }
    $s = Get-LLProp $r "source_id"; if ($s) { $rowBySid[$s] = $r }
}

function Resolve-DraftRow {
    param($Draft, $Content)
    $sid = Get-LLDraftSourceId $Content
    if ($sid -and $rowBySid.ContainsKey($sid)) { return $rowBySid[$sid] }
    if ($rowByTopic.ContainsKey($Draft.BaseName)) { return $rowByTopic[$Draft.BaseName] }
    return $null
}

# ── 차단 초안 수집 ──
$allDrafts = @(Get-ChildItem -LiteralPath $DraftsDir -Recurse -Filter "*.md" -File | Sort-Object FullName)
if ($allDrafts.Count -eq 0) {
    Write-Host "  04_blog_drafts 에 초안이 없습니다." -ForegroundColor Yellow
    exit 0
}

$blockedList = [System.Collections.Generic.List[object]]::new()
foreach ($d in $allDrafts) {
    $c = Read-LLText $d.FullName
    $row = Resolve-DraftRow $d $c
    $b = Get-LLDraftBadges -Content $c -Row $row
    if (-not $b.canApprove) {
        $why = ($b.badges | Where-Object { $_.cls -ne "ok" } | ForEach-Object { $_.text }) -join ", "
        $blockedList.Add([pscustomobject]@{ File = $d; Why = $why })
    }
}

if ($blockedList.Count -eq 0) {
    Write-Host ""
    Write-Host "  차단된 초안이 없습니다. (모두 승인 가능 상태)" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    exit 0
}

Write-Host ""
Write-Host ("  --- 차단된 초안 {0} 개 ---" -f $blockedList.Count) -ForegroundColor Magenta
for ($i = 0; $i -lt $blockedList.Count; $i++) {
    $rel = $blockedList[$i].File.FullName.Replace($DraftsDir + "\", "").Replace("\", "/")
    Write-Host ("  [{0,2}] ⛔ {1}" -f ($i + 1), $rel) -ForegroundColor DarkGray
    Write-Host ("       사유: {0}" -f $blockedList[$i].Why) -ForegroundColor DarkGray
}
Write-Host ""

if ($DryRun) {
    Write-Host "  [DryRun] 이동하지 않고 목록만 표시했습니다." -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    exit 0
}

# ── 대상 선택 ──
if ($All) {
    $targets = @($blockedList)
} else {
    Write-Host "  [ A] 차단된 전체 이동" -ForegroundColor Yellow
    Write-Host "  [ Q] 취소" -ForegroundColor DarkGray
    Write-Host ""
    $sel = (Read-Host "  이동할 번호 입력 (쉼표로 여러 개, 예: 1,3,5)").Trim().ToUpper()
    if ($sel -eq "Q" -or $sel -eq "") { Write-Host "  취소됨." -ForegroundColor DarkGray; exit 0 }
    if ($sel -eq "A") {
        $targets = @($blockedList)
    } else {
        $indices = $sel -split "," | ForEach-Object { [int]$_.Trim() - 1 }
        $targets = @($indices | ForEach-Object { $blockedList[$_] } | Where-Object { $null -ne $_ })
    }
}

if ($targets.Count -eq 0) {
    Write-Host "  선택된 파일 없음." -ForegroundColor Yellow
    exit 0
}

# ── 이동 처리 ──
$moved = 0
$logEntries = [System.Collections.Generic.List[object]]::new()
Write-Host ""
foreach ($t in $targets) {
    $d = $t.File
    $rel = $d.FullName.Replace($DraftsDir + "\", "")
    $destPath = Join-Path $TrashDir $rel
    $destDir = Split-Path -Parent $destPath
    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Move-Item -LiteralPath $d.FullName -Destination $destPath -Force
    Write-Host ("  [이동] {0} -> .trash/{1}/04_blog_drafts/{2}" -f ($rel -replace '\\','/'), $Stamp, ($rel -replace '\\','/')) -ForegroundColor Yellow
    $logEntries.Add([pscustomobject]@{
        moved_at   = $RunTime
        file_name  = $d.Name
        rel_path   = ($rel -replace '\\','/')
        reason     = $t.Why
        trash_path = $destPath
        moved_by   = $env:USERNAME
    })
    $moved++
}

# ── 로그 기록 (실패해도 이동 결과는 유지) ──
if ($logEntries.Count -gt 0) {
    try {
        $parent = Split-Path -Parent $LogPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $existing = @()
        if (Test-Path -LiteralPath $LogPath) { $existing = @(Import-Csv -LiteralPath $LogPath -Encoding utf8) }
        $all = @($existing) + @($logEntries.ToArray())
        $all | Export-Csv -LiteralPath $LogPath -Encoding utf8 -NoTypeInformation
    } catch {
        Write-Host ("  [경고] 로그 기록 실패(이동은 정상): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ("  이동 완료: {0} 개 -> .trash\{1}\" -f $moved, $Stamp) -ForegroundColor Green
Write-Host "  복구하려면 .trash 에서 04_blog_drafts 로 되돌리세요." -ForegroundColor DarkGray
Write-Host ("  로그: {0}" -f $LogPath) -ForegroundColor DarkGray
Write-Host "========================================" -ForegroundColor Cyan
exit 0
