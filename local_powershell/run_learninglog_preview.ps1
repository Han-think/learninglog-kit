#Requires -Version 7.0
<#
.SYNOPSIS
    LearningLog Preview — 초안 미리보기 대시보드 (로컬 서버 모드: 화면에서 선택 삭제 가능)

.DESCRIPTION
    기본(서버 모드):
      - http://127.0.0.1:8765 로 대시보드 서빙
      - 각 초안에 체크박스 + 🗑 버튼 → 클릭 시 .trash\preview_del_<시각>\ 로 이동(복구 가능) 후 목록 새로고침
      - 콘솔에서 Q 입력(또는 창 닫기/Ctrl+C)으로 종료
    -Static:
      - 예전처럼 정적 HTML 만 생성하고 종료 (삭제 버튼 없음)

.PARAMETER NoOpen           브라우저 자동 열기 안 함
.PARAMETER IncludePublished 발행된 글도 PUBLISHED 배지로 포함
.PARAMETER IncludeByproducts 합본 처리 후 생긴 partial-public 부산물 초안도 포함
.PARAMETER Static           정적 HTML 만 생성 (서버 안 띄움)
.PARAMETER Port             서버 포트 (기본 8765)
.PARAMETER Section          특정 섹션만 표시 (learning/projects/practice/goals)
#>

param(
    [switch]$NoOpen,
    [switch]$IncludePublished,
    [switch]$IncludeByproducts,
    [switch]$Static,
    [string]$Section = "",
    [int]$Port = 8765
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "_local_core\LearningLog.LocalCore.psm1") -Force -DisableNameChecking

$RunTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  LearningLog Preview Dashboard" -ForegroundColor Cyan
Write-Host "  $RunTime" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$null = Ensure-LLRegistrySchema
$DraftsDir = Get-LLPath "04_blog_drafts"
$OutDir    = Get-LLPath "09_reports\preview"
$markedPath = Get-LLPath "_local_core\vendor\marked.min.js"
if (-not (Test-Path -LiteralPath $markedPath)) {
    Write-Host "  [경고] marked.min.js 없음: $markedPath" -ForegroundColor Yellow
}

function New-Dashboard {
    return (New-LLPreviewDashboard -DraftsDir $DraftsDir -OutDir $OutDir -IncludePublished:$IncludePublished -IncludeByproducts:$IncludeByproducts -Section $Section)
}

$result = New-Dashboard
Write-Host ""
Write-Host ("  초안 {0} 개 미리보기 생성" -f $result.count) -ForegroundColor Green
if (-not $IncludePublished -and $result.excludedPublished -gt 0) {
    Write-Host ("  발행 제외: {0} 개 (-IncludePublished 로 포함 가능)" -f $result.excludedPublished) -ForegroundColor DarkGray
}
if (-not $IncludeByproducts -and $result.excludedByproducts -gt 0) {
    Write-Host ("  부산물 제외: {0} 개 (-IncludeByproducts 로 포함 가능)" -f $result.excludedByproducts) -ForegroundColor DarkGray
}
$canApprove = @($result.items | Where-Object { $_.canApprove }).Count
Write-Host ("  ✅ 승인 가능 {0} 개  /  ⚠️ 검토 필요 {1} 개" -f $canApprove, ($result.count - $canApprove))

# ── 정적 모드 ──
if ($Static) {
    Write-Host ("  -> {0}" -f $result.html) -ForegroundColor DarkGray
    if ($result.count -gt 0 -and -not $NoOpen) { Start-Process $result.html }
    Write-Host "========================================" -ForegroundColor Cyan
    exit 0
}

# ── 서버 모드 ──
$prefix = "http://127.0.0.1:$Port/"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
try { $listener.Start() } catch {
    Write-Host ("  [ERROR] 포트 {0} 사용 불가 (이미 실행 중?): {1}" -f $Port, $_.Exception.Message) -ForegroundColor Red
    Write-Host "  기존 미리보기 창을 닫거나 -Port 로 다른 포트를 지정하세요." -ForegroundColor Yellow
    exit 1
}

$TrashRoot = Get-LLPath (".trash\preview_del_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
$draftsFull = (Resolve-Path -LiteralPath $DraftsDir).Path

Write-Host ""
Write-Host ("  서버 모드: {0}" -f $prefix) -ForegroundColor Cyan
Write-Host "  화면에서 체크박스/🗑 로 초안을 .trash 로 보낼 수 있습니다." -ForegroundColor Cyan
Write-Host "  종료: 이 창에서 Q 입력 (또는 창 닫기)" -ForegroundColor DarkGray
if (-not $NoOpen) { Start-Process $prefix }

function Send-Text {
    param($Resp, [string]$Text, [string]$CType = "text/plain; charset=utf-8", [int]$Code = 200)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $Resp.StatusCode = $Code
    $Resp.ContentType = $CType
    $Resp.ContentLength64 = $bytes.Length
    $Resp.OutputStream.Write($bytes, 0, $bytes.Length)
    $Resp.OutputStream.Close()
}

# 비동기 수신 + 콘솔 Q 종료 병행
$deleted = 0
while ($listener.IsListening) {
    $task = $listener.GetContextAsync()
    while (-not $task.AsyncWaitHandle.WaitOne(200)) {
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.KeyChar.ToString().ToUpper() -eq "Q") {
                Write-Host ("`n  종료. 이번 세션 삭제 {0}건 -> {1}" -f $deleted, $TrashRoot) -ForegroundColor Green
                $listener.Stop(); exit 0
            }
        }
    }
    $ctx = $task.Result
    $req = $ctx.Request; $resp = $ctx.Response
    $path = $req.Url.AbsolutePath

    try {
        if ($path -eq "/") {
            $r = New-Dashboard
            $html = Read-LLText $r.html
            $html = $html.Replace('../../_local_core/vendor/marked.min.js', '/vendor/marked.min.js')
            Send-Text $resp $html "text/html; charset=utf-8"
        }
        elseif ($path -eq "/vendor/marked.min.js") {
            Send-Text $resp (Read-LLText $markedPath) "application/javascript; charset=utf-8"
        }
        elseif ($path -eq "/delete") {
            $rel = $req.QueryString["f"]   # 예: 04_blog_drafts/learning/x.md
            if (-not $rel) { Send-Text $resp "missing f" -Code 400; continue }
            $full = Join-Path (Get-LLRoot) ($rel -replace "/", "\")
            $fullResolved = ""
            if (Test-Path -LiteralPath $full) { $fullResolved = (Resolve-Path -LiteralPath $full).Path }
            # 안전 검증: 04_blog_drafts 안의 .md 만 허용
            if (-not $fullResolved -or -not $fullResolved.StartsWith($draftsFull) -or -not $fullResolved.EndsWith(".md")) {
                Send-Text $resp "invalid path" -Code 400; continue
            }
            $dest = Join-Path $TrashRoot ($rel -replace "/", "\")
            $destDir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Move-Item -LiteralPath $fullResolved -Destination $dest -Force
            $deleted++
            Write-Host ("  [삭제] {0} -> .trash" -f $rel) -ForegroundColor Yellow
            Send-Text $resp "ok"
        }
        else {
            Send-Text $resp "not found" -Code 404
        }
    } catch {
        try { Send-Text $resp ("error: " + $_.Exception.Message) -Code 500 } catch {}
    }
}
