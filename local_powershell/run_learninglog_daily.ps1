#Requires -Version 7.0
<#
.SYNOPSIS
    LearningLog Daily Log — 하루 일과를 카테고리별 '포인트'로 정리하는 텍스트 브이로그 양식 채우기.

.DESCRIPTION
    - 카테고리(요소)를 골라서, 자유 메모를 던지면 로컬 LLM(gemma3:12b)이 카테고리별 포인트로 정리.
    - 메모 없으면 빈 양식만 만들어 직접 채우게.
    - 04_blog_drafts\daily\YYYY-MM-DD-daily.md 로 저장 (발행/업로드 없음 — 순수 정리).

.PARAMETER Date     날짜 (기본 오늘, yyyy-MM-dd)
.PARAMETER NoOpen   저장 후 자동 열기 안 함
.PARAMETER NoLLM    LLM 정리 끄고 빈 양식만
#>
param(
    [string]$Date = (Get-Date).ToString("yyyy-MM-dd"),
    [switch]$NoOpen,
    [switch]$NoLLM
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "_local_core\LearningLog.LocalCore.psm1") -Force -DisableNameChecking

$OllamaBase = "http://127.0.0.1:11434"
$Model      = "gemma3:12b"

# ── 카테고리(요소) 정의 ──
$CATS = @(
    @{ emoji = "📚"; name = "학습" },
    @{ emoji = "💻"; name = "개발" },
    @{ emoji = "🍳"; name = "요리" },
    @{ emoji = "🏃"; name = "운동" },
    @{ emoji = "📖"; name = "독서" },
    @{ emoji = "🎵"; name = "음악" },
    @{ emoji = "🎮"; name = "게임" },
    @{ emoji = "🌿"; name = "일상" },
    @{ emoji = "💡"; name = "생각" }
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  데일리 로그 ($Date)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ── 카테고리 선택 ──
Write-Host ""
Write-Host "  오늘 기록할 요소를 고르세요 (쉼표로 여러 개, 예: 1,3,8)" -ForegroundColor Yellow
for ($i = 0; $i -lt $CATS.Count; $i++) {
    Write-Host ("    [{0}] {1} {2}" -f ($i + 1), $CATS[$i].emoji, $CATS[$i].name)
}
$sel = (Read-Host "  번호").Trim()
if ($sel -eq "") { Write-Host "  취소됨." -ForegroundColor DarkGray; exit 0 }
$picked = @($sel -split "," | ForEach-Object { [int]$_.Trim() - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $CATS.Count } | ForEach-Object { $CATS[$_] })
if ($picked.Count -eq 0) { Write-Host "  선택 없음." -ForegroundColor Yellow; exit 0 }

# ── 자유 메모 입력 (여러 줄, 빈 줄로 종료) ──
Write-Host ""
Write-Host "  오늘 있었던 일을 자유롭게 적으세요. (여러 줄 가능, 빈 줄 입력하면 끝 / 그냥 엔터=수동작성)" -ForegroundColor Yellow
$memoLines = [System.Collections.Generic.List[string]]::new()
while ($true) {
    $line = Read-Host "  >"
    if ($line -eq "") { break }
    $memoLines.Add($line)
}
$memo = ($memoLines -join "`n").Trim()

# ── LLM 헬퍼 ──
$ollamaOk = $false
if (-not $NoLLM -and $memo -ne "") {
    try { $null = Invoke-RestMethod "$OllamaBase/api/tags" -TimeoutSec 4; $ollamaOk = $true } catch { $ollamaOk = $false }
    if (-not $ollamaOk) { Write-Host "  (Ollama 꺼짐 → 빈 양식으로 생성)" -ForegroundColor DarkGray }
}
function Invoke-LLM {
    param([string]$Prompt)
    $body = [ordered]@{ model = $Model; prompt = $Prompt; stream = $false; options = [ordered]@{ num_predict = 512; num_ctx = 8192; temperature = 0.4 } }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 4 -Compress))
    try { return ([string](Invoke-RestMethod -Uri "$OllamaBase/api/generate" -Method Post -Body $bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 120).response).Trim() }
    catch { return "" }
}

# ── 본문 조립 ──
$sb = [System.Collections.Generic.List[string]]::new()
$tagList = ($picked | ForEach-Object { '"' + $_.name + '"' }) -join ", "
$sb.Add("---")
$sb.Add('title: "' + $Date + ' 데일리 로그"')
$sb.Add("date: $Date")
$sb.Add('categories: ["daily"]')
$sb.Add("tags: [$tagList]")
$sb.Add("---")
$sb.Add("")
$sb.Add("## 오늘의 포인트")

foreach ($c in $picked) {
    $head = "- {0} {1}:" -f $c.emoji, $c.name
    if ($ollamaOk) {
        $p = @"
다음은 하루 메모다. 이 중 '$($c.name)' 와 관련된 내용만 1~3개의 짧은 포인트로 정리하라.
규칙: 각 포인트는 한 줄, 간결한 한국어, 머리말/설명/번호 없이 내용만. 관련 내용이 없으면 아무것도 출력하지 마라.

메모:
---
$memo
"@
        $resp = Invoke-LLM $p
        $points = @($resp -split "`r?`n" | ForEach-Object { ($_ -replace '^\s*[-*\d\.\)]+\s*', '').Trim() } | Where-Object { $_ })
        if ($points.Count -eq 1) {
            $sb.Add(("- {0} {1}: {2}" -f $c.emoji, $c.name, $points[0]))
        } elseif ($points.Count -gt 1) {
            $sb.Add($head)
            foreach ($pt in $points) { $sb.Add("  - $pt") }
        } else {
            $sb.Add(("- {0} {1}: " -f $c.emoji, $c.name))
        }
    } else {
        $sb.Add(("- {0} {1}: " -f $c.emoji, $c.name))
    }
}

$sb.Add("")
$sb.Add("## 한 줄 회고")
$retro = ""
if ($ollamaOk) {
    $retro = Invoke-LLM "다음 하루 메모를 바탕으로 '오늘 하루'를 한 줄로 담백하게 회고하라. 한 문장, 사족 없이.`n`n메모:`n---`n$memo"
}
$sb.Add($(if ($retro) { $retro } else { "" }))
$sb.Add("")

# ── 저장 ──
$outDir = Get-LLPath "daily_logs"   # 04 밖: 학습 미리보기/발행과 분리 (데일리는 별개 기능)
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$outPath = Join-Path $outDir "$Date-daily.md"
$content = ($sb -join "`n")
[System.IO.File]::WriteAllText($outPath, $content, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host ("  저장: 04_blog_drafts\daily\{0}-daily.md" -f $Date) -ForegroundColor Green
Write-Host ("  카테고리: {0}" -f (($picked | ForEach-Object { $_.emoji + $_.name }) -join " ")) -ForegroundColor DarkGray
Write-Host ("  LLM 정리: {0}" -f $(if ($ollamaOk) { "사용" } else { "미사용(빈 양식)" })) -ForegroundColor DarkGray
Write-Host "========================================" -ForegroundColor Cyan
if (-not $NoOpen) { Start-Process $outPath }
exit 0
