#Requires -Version 7.0
<#
.SYNOPSIS
    DailyLog Kit 1.2 - local daily Markdown logger with optional Ollama or Gemini summarization.

.DESCRIPTION
    Pick categories, enter a free-form memo, then save a Markdown daily log.
    This tool never uploads or publishes anything. It only writes a local Markdown file.

.PARAMETER Provider
    auto, ollama, gemini, or template. auto prefers Gemini key, then Ollama, then template.

.PARAMETER GeminiApiKey
    Google AI Studio API key. If omitted, reads dailylog.config.json or GEMINI_API_KEY.

.PARAMETER SaveGeminiKey
    Save the provided Gemini API key to dailylog.config.json. This file is gitignored.

.PARAMETER NoLLM
    Disable LLM summarization and generate an empty template.
#>

param(
    [string]$Date = (Get-Date).ToString("yyyy-MM-dd"),
    [ValidateSet("auto", "ollama", "gemini", "template")]
    [string]$Provider = "auto",
    [Alias("Model")]
    [string]$OllamaModel = "gemma3:12b",
    [string]$GeminiModel = "gemini-2.5-flash",
    [string]$GeminiApiKey = "",
    [string]$OutDir = (Join-Path $PSScriptRoot "output"),
    [switch]$SaveGeminiKey,
    [switch]$NoOpen,
    [switch]$NoLLM
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$KitVersion = "1.2"
$OllamaBase = "http://127.0.0.1:11434"
$ConfigPath = Join-Path $PSScriptRoot "dailylog.config.json"

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

function Read-DailyConfig {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $null }
    try {
        return (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Host "  [경고] dailylog.config.json 을 읽지 못했습니다. 설정 없이 진행합니다." -ForegroundColor Yellow
        return $null
    }
}

function Save-DailyGeminiConfig {
    param(
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)][string]$Model
    )
    $cfg = [ordered]@{
        provider = "gemini"
        gemini = [ordered]@{
            api_key = $ApiKey
            model = $Model
        }
    }
    $json = $cfg | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($ConfigPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Gemini 설정 저장: dailylog.config.json" -ForegroundColor Green
}

function Get-GeminiKey {
    param($Config)
    if ($GeminiApiKey) { return $GeminiApiKey }
    if ($Config -and $Config.PSObject.Properties["gemini"]) {
        $v = [string]$Config.gemini.api_key
        if ($v) { return $v }
    }
    if ($env:GEMINI_API_KEY) { return $env:GEMINI_API_KEY }
    return ""
}

function Get-GeminiModelName {
    param($Config)
    if ($GeminiModel) { return $GeminiModel }
    if ($Config -and $Config.PSObject.Properties["gemini"]) {
        $v = [string]$Config.gemini.model
        if ($v) { return $v }
    }
    return "gemini-2.5-flash"
}

function Test-OllamaRunning {
    try {
        $null = Invoke-RestMethod "$OllamaBase/api/tags" -TimeoutSec 4
        return $true
    } catch {
        return $false
    }
}

function Invoke-Ollama {
    param([Parameter(Mandatory)][string]$Prompt)
    $body = [ordered]@{
        model = $OllamaModel
        prompt = $Prompt
        stream = $false
        options = [ordered]@{
            num_predict = 512
            num_ctx = 8192
            temperature = 0.4
        }
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 6 -Compress))
    try {
        $response = Invoke-RestMethod -Uri "$OllamaBase/api/generate" -Method Post -Body $bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 120
        return ([string]$response.response).Trim()
    } catch {
        Write-Host ("  [경고] Ollama 호출 실패: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        return ""
    }
}

function Invoke-Gemini {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)][string]$Model
    )
    $escapedModel = [uri]::EscapeDataString($Model)
    $escapedKey = [uri]::EscapeDataString($ApiKey)
    $uri = "https://generativelanguage.googleapis.com/v1beta/models/$escapedModel`:generateContent?key=$escapedKey"
    $body = [ordered]@{
        contents = @(
            [ordered]@{
                parts = @([ordered]@{ text = $Prompt })
            }
        )
        generationConfig = [ordered]@{
            temperature = 0.4
            maxOutputTokens = 512
        }
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 10 -Compress))
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body $bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 120
        $parts = @($response.candidates[0].content.parts | ForEach-Object { [string]$_.text })
        return (($parts -join "`n").Trim())
    } catch {
        Write-Host ("  [경고] Gemini 호출 실패: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        return ""
    }
}

function Invoke-DailyLLM {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$ActiveProvider,
        [string]$GeminiKey = "",
        [string]$ActiveGeminiModel = ""
    )
    switch ($ActiveProvider) {
        "gemini" { return (Invoke-Gemini -Prompt $Prompt -ApiKey $GeminiKey -Model $ActiveGeminiModel) }
        "ollama" { return (Invoke-Ollama -Prompt $Prompt) }
        default { return "" }
    }
}

$config = Read-DailyConfig
$geminiKey = Get-GeminiKey -Config $config
$activeGeminiModel = Get-GeminiModelName -Config $config

if ($SaveGeminiKey) {
    if (-not $GeminiApiKey) {
        Write-Host "  [경고] -SaveGeminiKey 는 -GeminiApiKey 와 함께 사용하세요." -ForegroundColor Yellow
    } else {
        Save-DailyGeminiConfig -ApiKey $GeminiApiKey -Model $activeGeminiModel
    }
}

$activeProvider = "template"
if (-not $NoLLM) {
    switch ($Provider) {
        "template" { $activeProvider = "template" }
        "gemini" {
            if (-not $geminiKey -and [Environment]::UserInteractive) {
                $geminiKey = (Read-Host "  Gemini API Key (비우면 템플릿 모드)").Trim()
            }
            if ($geminiKey) { $activeProvider = "gemini" }
        }
        "ollama" {
            if (Test-OllamaRunning) { $activeProvider = "ollama" }
        }
        default {
            if ($geminiKey) {
                $activeProvider = "gemini"
            } elseif (Test-OllamaRunning) {
                $activeProvider = "ollama"
            }
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ("  DailyLog Kit {0} - {1}" -f $KitVersion, $Date) -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ("  Provider: {0}" -f $activeProvider) -ForegroundColor $(if ($activeProvider -eq "template") { "DarkGray" } else { "Green" })
if ($activeProvider -eq "gemini") {
    Write-Host ("  Gemini model: {0}" -f $activeGeminiModel) -ForegroundColor DarkGray
} elseif ($activeProvider -eq "ollama") {
    Write-Host ("  Ollama model: {0}" -f $OllamaModel) -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  기록할 요소를 고르세요 (쉼표로 여러 개, 예: 1,3,8)" -ForegroundColor Yellow
for ($i = 0; $i -lt $CATS.Count; $i++) {
    Write-Host ("    [{0}] {1} {2}" -f ($i + 1), $CATS[$i].emoji, $CATS[$i].name)
}
$sel = (Read-Host "  번호").Trim()
if ($sel -eq "") { Write-Host "  취소됨." -ForegroundColor DarkGray; exit 0 }

$picked = @(
    $sel -split "," |
        ForEach-Object { [int]$_.Trim() - 1 } |
        Where-Object { $_ -ge 0 -and $_ -lt $CATS.Count } |
        ForEach-Object { $CATS[$_] }
)
if ($picked.Count -eq 0) { Write-Host "  선택 없음." -ForegroundColor Yellow; exit 0 }

Write-Host ""
Write-Host "  오늘 있었던 일을 자유롭게 적으세요. (여러 줄 OK, 빈 줄=끝 / 그냥 엔터=수동작성)" -ForegroundColor Yellow
$memoLines = [System.Collections.Generic.List[string]]::new()
while ($true) {
    $line = Read-Host "  >"
    if ($line -eq "") { break }
    $memoLines.Add($line)
}
$memo = ($memoLines -join "`n").Trim()

if ($memo -eq "") { $activeProvider = "template" }

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
    if ($activeProvider -ne "template") {
        $prompt = @"
다음은 하루 메모다. 이 중 '$($c.name)' 와 관련된 내용만 1~3개의 짧은 포인트로 정리하라.
규칙:
- 각 포인트는 한 줄
- 간결한 한국어
- 머리말/설명/번호 없이 내용만
- 관련 내용이 없으면 아무것도 출력하지 말 것

메모:
---
$memo
"@
        $resp = Invoke-DailyLLM -Prompt $prompt -ActiveProvider $activeProvider -GeminiKey $geminiKey -ActiveGeminiModel $activeGeminiModel
        $points = @(
            $resp -split "`r?`n" |
                ForEach-Object { ($_ -replace '^\s*[-*\d\.\)]+\s*', '').Trim() } |
                Where-Object { $_ }
        )
        if ($points.Count -eq 1) {
            $sb.Add(("- {0} {1}: {2}" -f $c.emoji, $c.name, $points[0]))
        } elseif ($points.Count -gt 1) {
            $sb.Add(("- {0} {1}:" -f $c.emoji, $c.name))
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
if ($activeProvider -ne "template") {
    $retroPrompt = "다음 하루 메모를 바탕으로 '오늘 하루'를 한 줄로 담백하게 회고하라. 한 문장, 사족 없이.`n`n메모:`n---`n$memo"
    $retro = Invoke-DailyLLM -Prompt $retroPrompt -ActiveProvider $activeProvider -GeminiKey $geminiKey -ActiveGeminiModel $activeGeminiModel
}
$sb.Add($(if ($retro) { $retro } else { "" }))
$sb.Add("")

if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$outPath = Join-Path $OutDir "$Date-daily.md"
[System.IO.File]::WriteAllText($outPath, ($sb -join "`n"), [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host ("  저장: {0}" -f $outPath) -ForegroundColor Green
Write-Host ("  카테고리: {0}  |  LLM 정리: {1}" -f (($picked | ForEach-Object { $_.emoji + $_.name }) -join " "), $activeProvider) -ForegroundColor DarkGray
Write-Host "========================================" -ForegroundColor Cyan
if (-not $NoOpen) { Start-Process $outPath }
exit 0
