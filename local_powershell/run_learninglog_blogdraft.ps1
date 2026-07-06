#Requires -Version 7.0
<#
.SYNOPSIS
    LearningLog Blog Draft — 워킹 노트 → Hugo 블로그 초안 생성

.DESCRIPTION
    하는 것:
      - 03_working_notes\daily_logs\ 의 노트 스캔
      - 대응하는 04_blog_drafts\ 파일이 없는 것만 처리
      - Ollama 로 Hugo 초안 생성 (draft: true)
      - source_registry.csv status → drafted

    하지 않는 것:
      - blog-source 접촉 없음 (publish 는 run_learninglog_publish.ps1)
      - internal-only 소스 처리 없음
      - 원본 파일 수정 없음

.PARAMETER SourceId
    특정 source_id 만 처리
#>

param(
    [string]$SourceId  = "",
    [switch]$Force,
    [int]$NumCtx       = 8192,
    [int]$MaxCharsPerChunk = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "_local_core\LearningLog.LocalCore.psm1") -Force -DisableNameChecking

$Root         = Get-LLRoot
$RegistryPath = Get-LLRegistryPath
$WorkingDir   = Get-LLPath "03_working_notes\daily_logs"
$DraftsRoot   = Get-LLPath "04_blog_drafts"
$OllamaBase   = "http://127.0.0.1:11434"
$ModelDraft   = "gemma3:12b"   # 7.8b 소형은 JSON 불완전 → '정리 필요.' 양산. 12b 로 상향(필요시 gemma3:27b)

$RunDT    = Get-Date
$RunTime  = $RunDT.ToString("yyyy-MM-dd HH:mm:ss")
$TodayStr = $RunDT.ToString("yyyy-MM-dd")
$TimeStamp = $RunDT.ToString("yyyyMMdd_HHmmss")

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  LearningLog Blog Draft Generator" -ForegroundColor Cyan
Write-Host "  $RunTime" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ─── Ollama 헬스체크 ─────────────────────────────────────
Write-Host ""
Write-Host "  Ollama 헬스체크 ... " -ForegroundColor White -NoNewline
try {
    $null = Invoke-RestMethod -Uri "$OllamaBase/" -Method Get -TimeoutSec 5 -ErrorAction Stop
    Write-Host "OK" -ForegroundColor Green
} catch {
    Write-Host "FAIL" -ForegroundColor Red
    Write-Host "  Ollama 를 먼저 실행하세요." -ForegroundColor Yellow
    exit 1
}

# ─── 청크 크기 계산 ──────────────────────────────────────
$DefaultPolicy = Get-LLProcessingPolicy -SourceType "personal_note" -SourceCategory "personal_note" -FileType "md" -ManualChunkChars $MaxCharsPerChunk
Write-Host ("  컨텍스트: {0}토큰 → personal_note direct≤{1}자 / chunk {2}자 / overlap {3}자" -f $NumCtx, $DefaultPolicy.MaxDirectChars, $DefaultPolicy.ChunkChars, $DefaultPolicy.OverlapChars) -ForegroundColor DarkGray

# ─── registry 로드 ────────────────────────────────────────
$schema = Ensure-LLRegistrySchema
if ($schema.upgraded -and $schema.backup) {
    Write-Host ("  registry upgraded: {0}" -f $schema.backup) -ForegroundColor Yellow
}
$registry = Get-LLRegistryRows
$publishedNames = Get-LLPublishedNames   # 06_published 에 있는 글은 draft 지워졌어도 재생성 안 함
$PublishedDirCheck = Get-LLPath "06_published"

# ─── Ollama 호출 헬퍼 ────────────────────────────────────
function Invoke-OllamaGenerate {
    param([string]$Model, [string]$Prompt)
    $bodyObj   = [ordered]@{ model = $Model; prompt = $Prompt; stream = $false
                              options = [ordered]@{ num_predict = 1024; num_ctx = $NumCtx } }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(($bodyObj | ConvertTo-Json -Depth 4 -Compress))
    $resp = Invoke-RestMethod -Uri "$OllamaBase/api/generate" -Method Post `
            -Body $bodyBytes -ContentType "application/json; charset=utf-8" -TimeoutSec 600 -ErrorAction Stop
    return $resp.response
}

function Invoke-OllamaGenerateJson {
    param([string]$Model, [string]$Prompt, [int]$NumPredict = 2048)
    $bodyObj   = [ordered]@{ model = $Model; prompt = $Prompt; stream = $false; format = "json"
                              options = [ordered]@{ num_predict = $NumPredict; num_ctx = $NumCtx; temperature = 0.3 } }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(($bodyObj | ConvertTo-Json -Depth 4 -Compress))
    $resp = Invoke-RestMethod -Uri "$OllamaBase/api/generate" -Method Post `
            -Body $bodyBytes -ContentType "application/json; charset=utf-8" -TimeoutSec 600 -ErrorAction Stop
    return $resp.response
}

function Test-BlogDraftBadTitle {
    param(
        [string]$Title,
        [string]$Topic
    )
    $t = $Title.Trim()
    if ($t -eq "") { return $true }
    if ($t -match '^(학습 노트|제목|블로그 제목)$') { return $true }
    if ($Topic -and $t.ToLowerInvariant() -eq $Topic.ToLowerInvariant()) { return $true }
    if ($t -match '^[a-z0-9]+(?:[-_][a-z0-9]+){1,}$') { return $true }
    return $false
}

function Get-BlogDraftFallbackTitle {
    param(
        [string]$Topic,
        [string[]]$ConceptNames = @()
    )
    $conceptTitle = @($ConceptNames | Where-Object { $_ -and $_ -ne "학습 내용" } | Select-Object -First 2)
    if ($conceptTitle.Count -gt 0) {
        return (($conceptTitle -join "와 ") + " 이해하기")
    }
    $words = @($Topic -split '[-_]' | Where-Object { $_ })
    if ($words.Count -eq 0) { return "학습 내용 정리" }
    $textInfo = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
    return ($textInfo.ToTitleCase(($words -join " ")) + " 정리")
}

function Get-BlogDraftTitle {
    param(
        [string]$Topic,
        [string]$NoteContext,
        [string[]]$ConceptNames,
        [scriptblock]$LLMInvoker
    )
    $conceptText = if ($ConceptNames.Count -gt 0) { ($ConceptNames -join ", ") } else { "학습 내용" }
    $ctx = $NoteContext
    if ($ctx.Length -gt 2500) { $ctx = $ctx.Substring(0, 2500) }
    $prompt = @"
아래 워킹노트로 Hugo 블로그 글 제목을 한 줄로 지어라.
- 한국어 제목
- 12~45자
- 따옴표, 마크다운, 설명 금지
- '$Topic' 같은 파일명/slug 그대로 금지
- '학습 노트'라는 표현 금지

topic: $Topic
핵심 개념: $conceptText

워킹노트:
---
$ctx
---
"@
    $title = Get-LLFieldText -LLMInvoker $LLMInvoker -Prompt $prompt
    $title = (($title -split '\r?\n') | Select-Object -First 1).Trim()
    $title = $title.Trim("#").Trim().Trim('"').Trim("'").Trim()
    if (Test-BlogDraftBadTitle -Title $title -Topic $Topic) {
        $title = Get-BlogDraftFallbackTitle -Topic $Topic -ConceptNames $ConceptNames
    }
    return $title
}

function Test-BlogDraftSlugTitle {
    param([string]$Title)
    $t = $Title.Trim()
    if ($t -eq "") { return $true }
    if ($t -match '^(am|pm)-\d{2}-') { return $true }
    if ($t -match '^[a-z0-9]+(?:[-_][a-z0-9]+){1,}$') { return $true }
    return $false
}

function Get-BlogDraftSectionFallbackTitle {
    param([string]$Topic)
    $stem = $Topic -replace '^(am|pm)-\d{2}-', ''
    $words = @($stem -split '[-_]' | Where-Object { $_ })
    if ($words.Count -eq 0) { return "학습 내용 정리" }

    $known = @{
        "sql" = "SQL"; "sqlite" = "SQLite"; "erd" = "ERD"; "join" = "JOIN";
        "groupby" = "GROUP BY"; "having" = "HAVING"; "rank" = "RANK";
        "ntile" = "NTILE"; "lag" = "LAG"; "lead" = "LEAD"; "mom" = "MoM";
        "rollup" = "ROLLUP"; "cube" = "CUBE"; "union" = "UNION";
        "all" = "ALL"; "view" = "VIEW"; "dual" = "DUAL"; "plsql" = "PL/SQL";
        "classicmodels" = "ClassicModels"; "strftime" = "strftime";
        "over" = "OVER"; "partition" = "PARTITION"; "current" = "CURRENT";
        "row" = "ROW"
    }

    $parts = @($words | ForEach-Object {
        $w = $_.ToLowerInvariant()
        if ($known.ContainsKey($w)) { $known[$w] } else { $w }
    })
    return (($parts -join " ") + " 이해하기")
}

function Get-BlogDraftSectionTitle {
    param(
        [string]$Title,
        [string]$Topic,
        [string]$NoteContext,
        [scriptblock]$LLMInvoker
    )
    $candidate = $Title.Trim()
    if (-not (Test-BlogDraftSlugTitle -Title $candidate)) { return $candidate }

    $ctx = $NoteContext
    if ($ctx.Length -gt 2200) { $ctx = $ctx.Substring(0, 2200) }
    $prompt = @"
아래 워킹노트로 daily 합본 글의 섹션 제목을 한 줄로 지어라.
- 한국어 제목
- 12~45자
- 따옴표, 마크다운, 설명 금지
- '$Topic' 같은 파일명/slug 그대로 금지
- 목차에 들어가도 자연스러운 제목

topic: $Topic
현재 제목: $Title

워킹노트:
---
$ctx
---
"@
    $sectionTitle = Get-LLFieldText -LLMInvoker $LLMInvoker -Prompt $prompt
    $sectionTitle = (($sectionTitle -split '\r?\n') | Select-Object -First 1).Trim()
    $sectionTitle = $sectionTitle.Trim("#").Trim().Trim('"').Trim("'").Trim()
    if (Test-BlogDraftSlugTitle -Title $sectionTitle) {
        $sectionTitle = Get-BlogDraftSectionFallbackTitle -Topic $Topic
    }
    return $sectionTitle
}

function Split-IntoChunks { param([string]$Text, [int]$MaxChars, [int]$OverlapChars = 0)
    $paragraphs = $Text -split "(?m)^\s*$"
    $chunks = [System.Collections.Generic.List[string]]::new()
    $cur    = [System.Text.StringBuilder]::new()
    foreach ($p in $paragraphs) {
        $p = $p.Trim(); if ($p -eq "") { continue }
        if ($cur.Length + $p.Length + 2 -gt $MaxChars -and $cur.Length -gt 0) {
            $chunks.Add($cur.ToString().Trim()); $null = $cur.Clear()
        }
        $null = $cur.AppendLine($p); $null = $cur.AppendLine()
    }
    if ($cur.Length -gt 0) { $chunks.Add($cur.ToString().Trim()) }
    if ($chunks.Count -eq 0) { $chunks.Add($Text) }

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($chunk in $chunks) {
        if ($chunk.Length -le $MaxChars) {
            $result.Add($chunk)
        } else {
            $pos = 0
            while ($pos -lt $chunk.Length) {
                $len = [Math]::Min($MaxChars, $chunk.Length - $pos)
                $result.Add($chunk.Substring($pos, $len))
                $pos += $len
            }
        }
    }

    if ($OverlapChars -le 0 -or $result.Count -le 1) { return $result }

    $withOverlap = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $result.Count; $i++) {
        if ($i -eq 0) { $withOverlap.Add($result[$i]); continue }
        $prev = $result[$i - 1]
        $tailLen = [Math]::Min($OverlapChars, $prev.Length)
        $tail = $prev.Substring($prev.Length - $tailLen)
        $withOverlap.Add("[이전 문맥 일부]`n$tail`n`n[현재 파트]`n$($result[$i])")
    }
    return $withOverlap
}

function Invoke-OllamaChunked { param([string]$Model, [string]$Instruction, [string]$Body, [int]$MaxChars, [int]$DirectChars = 0, [int]$OverlapChars = 0)
    if (($DirectChars -gt 0 -and $Body.Length -le $DirectChars) -or $Body.Length -le $MaxChars) {
        return Invoke-OllamaGenerate -Model $Model -Prompt ($Instruction + "`n---`n" + $Body)
    }
    $chunks = Split-IntoChunks -Text $Body -MaxChars $MaxChars -OverlapChars $OverlapChars
    Write-Host ("      청킹: {0} 파트 (각 ~{1}자, overlap {2}자)" -f $chunks.Count, $MaxChars, $OverlapChars) -ForegroundColor DarkGray
    $parts = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $chunks.Count; $i++) {
        Write-Host ("      파트 {0}/{1} " -f ($i+1), $chunks.Count) -ForegroundColor DarkGray -NoNewline
        $parts.Add((Invoke-OllamaGenerate -Model $Model -Prompt ($Instruction + "`n(파트 $($i+1)/$($chunks.Count))`n---`n" + $chunks[$i])))
        Write-Host "OK" -ForegroundColor Green
    }
    if ($parts.Count -eq 1) { return $parts[0] }
    return $parts -join "`n`n---`n`n"
}

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

    $metaLinePattern = '^\s*(source_id|note_date|mode|model):\s*'
    $boldMetaPattern = '^\s*\*\*(title|제목|date|날짜|draft|categories|category|카테고리|범주|tags|태그|description|설명)\*\*\s*:'

    $i = $start
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line.Trim() -eq "---" -or $line -match $metaLinePattern -or $line -match $boldMetaPattern) {
            $i++
            continue
        }

        $out.Add($line)
        $i++
    }

    return (($out -join "`n").TrimEnd() + "`n")
}

function Update-RegistryStatus { param([string]$Sid, [string]$NewStatus)
    $null = Set-LLRegistryStatus -SourceId $Sid -Status $NewStatus
}

# ─── 워킹 노트 스캔 ──────────────────────────────────────
$workingFiles = @(Get-ChildItem -Path $WorkingDir -Filter "*.md" -File | Sort-Object Name)
Write-Host ("  워킹 노트: {0} 개" -f $workingFiles.Count) -ForegroundColor Yellow

$doneCount = 0; $skipCount = 0; $errCount = 0

# ─── [합본] am/pm 노트 → 하루 = 오전 1편 + 오후 1편 ─────────
#   워킹노트 이름이 'YYYY-MM-DD_am-…' / 'YYYY-MM-DD_pm-…' 이면 날짜·반일별로 묶어
#   합본 글 1편(YYYY-MM-DD-{am|pm}-daily.md)을 생성한다. 묶인 노트는 개별 생성에서 제외.
$consumed = [System.Collections.Generic.HashSet[string]]::new()
$llmTextG = { param($p) Invoke-OllamaGenerate -Model $ModelDraft -Prompt $p }

$groups = @{}
foreach ($wf in $workingFiles) {
    if ($wf.BaseName -match '^(\d{4}-\d{2}-\d{2})_(am|pm)-') {
        $gk = "{0}|{1}" -f $Matches[1], $Matches[2]
        if (-not $groups.ContainsKey($gk)) { $groups[$gk] = [System.Collections.Generic.List[object]]::new() }
        $groups[$gk].Add($wf)
    }
}

foreach ($gk in ($groups.Keys | Sort-Object)) {
    $gDate, $gHalf = $gk -split '\|'
    $gFiles = $groups[$gk]
    foreach ($f in $gFiles) { $null = $consumed.Add($f.FullName) }   # 합본 대상은 개별 생성 금지

    $halfKo = if ($gHalf -eq "am") { "오전" } else { "오후" }
    $dailyName = "$gDate-$gHalf-daily.md"
    $dailyPath = Join-Path (Join-Path $DraftsRoot "learning") $dailyName

    Write-Host ""
    Write-Host ("  [합본] {0} {1} — 노트 {2}개" -f $gDate, $halfKo, $gFiles.Count) -ForegroundColor Magenta

    # 같은 날짜·반일의 합본이 이미 있으면 skip (수동/GPT 합본 'YYYY-MM-DD-am-*.md' 포함)
    $already = @(Get-ChildItem -Path $PublishedDirCheck -Filter "$gDate-$gHalf-*.md" -ErrorAction SilentlyContinue) +
               @(Get-ChildItem -Path (Join-Path $DraftsRoot "learning") -Filter "$gDate-$gHalf-*.md" -ErrorAction SilentlyContinue)
    if ($already.Count -gt 0 -and -not $Force) {
        Write-Host ("    daily_draft ... SKIP (이미 존재: {0})" -f $already[0].Name) -ForegroundColor DarkGray
        $skipCount++; continue
    }

    try {
        # 멤버 노트 수집 (policy 통과분만)
        $members = @()
        foreach ($f in $gFiles) {
            $sidM = ""
            foreach ($ln in [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)) {
                if ($ln -match "^source_id:\s*(.+)") { $sidM = $Matches[1].Trim(); break }
            }
            $rowM = $registry | Where-Object { $_.source_id -eq $sidM } | Select-Object -First 1
            if ($null -eq $rowM) { continue }
            if (-not (Test-LLPublishableSource $rowM)) { continue }
            if ($rowM.PSObject.Properties['status'] -and $rowM.status -eq 'archived') { continue }
            $rawM = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
            $ctxM = Remove-ExtraHugoFrontMatter -Text $rawM
            if ($ctxM.Length -gt 3500) { $ctxM = $ctxM.Substring(0, 3500) }
            $titleM = ""
            if ($rawM -match '(?m)^\s*title:\s*"?(.+?)"?\s*$') { $titleM = $Matches[1].Trim() }
            if (-not $titleM) { $titleM = $rowM.topic }
            $titleM = Get-BlogDraftSectionTitle -Title $titleM -Topic $rowM.topic -NoteContext $ctxM -LLMInvoker $llmTextG
            $tagsM = @()
            if ($rawM -match '(?m)^\s*(recommended_)?tags:\s*\[(.+?)\]') {
                $tagsM = @($Matches[2] -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ })
            }
            $members += [pscustomobject]@{ Sid = $sidM; Title = $titleM; Ctx = $ctxM; Tags = $tagsM }
        }
        if ($members.Count -eq 0) {
            Write-Host "    daily_draft ... SKIP (사용 가능한 멤버 노트 없음)" -ForegroundColor DarkGray
            $skipCount++; continue
        }

        Write-Host ("    daily_draft ... {0} " -f $ModelDraft) -ForegroundColor White -NoNewline

        # 노트당 섹션 1개 채우기 (칸별 plain-text, 회복 대기 내장)
        $rule = " 마크다운 헤딩(#) 금지. 학습자 1인칭 한국어. 강의 원문 복붙 금지. 사족 없이 본문만 출력."
        $sections = @()
        foreach ($m in $members) {
            $ctx = "학습 노트:`n---`n$($m.Ctx)`n---`n"
            $sections += [pscustomobject]@{
                Heading    = $m.Title
                Learned    = (Get-LLFieldText -LLMInvoker $llmTextG -Prompt ($ctx + "이 노트에서 무엇을 배웠는지 2~4문장으로 써라." + $rule))
                Confused   = (Get-LLFieldText -LLMInvoker $llmTextG -Prompt ($ctx + "처음에 헷갈렸거나 오해했던 점을 2~3문장으로 써라." + $rule))
                Understood = (Get-LLFieldText -LLMInvoker $llmTextG -Prompt ($ctx + "최종적으로 정리된 이해를 2~3문장으로 써라." + $rule))
                Code       = (Get-LLFieldText -LLMInvoker $llmTextG -AllowEmpty -Prompt ($ctx + "핵심을 보여주는 코드 예시'만' 백틱3개 코드블록으로 출력하라. 노트에 코드 근거가 없으면 아무것도 쓰지 마라."))
            }
        }

        # 총평 + 제목
        $digest = ($sections | ForEach-Object { "- " + $_.Heading + ": " + $_.Learned }) -join "`n"
        $rctx = "오늘 $halfKo 학습 요약:`n$digest`n"
        $review = [pscustomobject]@{
            learned = (Get-LLFieldText -LLMInvoker $llmTextG -Prompt ($rctx + "'오늘 $halfKo 전체에서 배운 것'을 2~3문장으로 써라." + $rule))
            caution = (Get-LLFieldText -LLMInvoker $llmTextG -Prompt ($rctx + "'다음에 조심할 것'을 2~3문장으로 써라." + $rule))
            review  = (Get-LLFieldText -LLMInvoker $llmTextG -Prompt ($rctx + "'다음에 복습할 주제'를 2~3문장으로 써라." + $rule))
        }
        $gTitle = (Get-LLFieldText -LLMInvoker $llmTextG -Prompt ($rctx + "이 $halfKo 학습글의 블로그 제목을 한 줄로 지어라. '학습 노트'라는 표현 금지. 따옴표 없이 제목만 출력." + $rule))
        if (-not $gTitle -or $gTitle -match '학습 노트') { $gTitle = "$gDate $halfKo SQL 학습 정리: " + $members[0].Title }
        $gTags = @($members | ForEach-Object { $_.Tags } | Select-Object -Unique | Select-Object -First 8)

        $resultG = New-LLDailyPost -Title $gTitle -Date $gDate -Half $gHalf -Sections $sections -Review $review -Tags $gTags
        if (-not (Test-Path (Join-Path $DraftsRoot "learning"))) { New-Item -ItemType Directory -Path (Join-Path $DraftsRoot "learning") -Force | Out-Null }
        [System.IO.File]::WriteAllText($dailyPath, $resultG, [System.Text.Encoding]::UTF8)

        # 합본 글 레지스트리 등록 (topic=파일명stem) — approve 의 NO REGISTRY 차단 방지
        $stemG = [System.IO.Path]::GetFileNameWithoutExtension($dailyName)
        $regAll = @(Import-Csv -LiteralPath $RegistryPath -Encoding utf8)
        if (-not ($regAll | Where-Object { $_.topic -eq $stemG })) {
            $fieldsG = @(Get-LLRegistryFields)
            $o = [ordered]@{}; foreach ($fd in $fieldsG) { $o[$fd] = "" }
            $o.source_id = "SRC-" + ($gDate -replace '-','') + "-9" + $(if ($gHalf -eq "am") { "01" } else { "02" })
            $o.source_path = "04_blog_drafts/learning/$dailyName"
            $o.file_name = $dailyName; $o.file_type = "md"
            $o.source_type = "blog_draft"; $o.source_category = "daily_merged"
            $o.date_added = $gDate; $o.created_at = $gDate; $o.status = "drafted"
            $o.topic = $stemG; $o.language = "korean"; $o.public_policy = "public"
            $o.notes = "am/pm 합본 자동 생성"
            (@($regAll) + @([pscustomobject]$o)) | Export-Csv -LiteralPath $RegistryPath -Encoding utf8 -NoTypeInformation
            $registry = Get-LLRegistryRows
        }

        # 멤버 노트 상태 → drafted (합본으로 소비됨)
        foreach ($m in $members) { Update-RegistryStatus -Sid $m.Sid -NewStatus "drafted" }

        $issG = @(Get-LLDraftQualityIssues -Content $resultG)
        if ($issG.Count -gt 0) {
            Write-Host ("WARN ({0})" -f ($issG -join ", ")) -ForegroundColor Yellow
        } else {
            Write-Host "OK" -ForegroundColor Green
        }
        Write-Host ("    저장: 04_blog_drafts\learning\{0}" -f $dailyName) -ForegroundColor DarkGray
        $doneCount++
    } catch {
        Write-Host "FAIL" -ForegroundColor Red
        Write-Host ("    [ERROR] {0}" -f $_.Exception.Message) -ForegroundColor Red
        $errCount++
    }
}

foreach ($wf in $workingFiles) {
    if ($consumed.Contains($wf.FullName)) { continue }   # am/pm 합본으로 소비됨 — 개별 생성 안 함

    # front matter 에서 source_id 파싱
    $lines = [System.IO.File]::ReadAllLines($wf.FullName, [System.Text.Encoding]::UTF8)
    $sid   = ""
    foreach ($ln in $lines) {
        if ($ln -match "^source_id:\s*(.+)") { $sid = $Matches[1].Trim(); break }
    }

    if ($sid -eq "") { Write-Host ("  [SKIP] {0} — source_id 없음" -f $wf.Name) -ForegroundColor DarkGray; $skipCount++; continue }
    if ($SourceId -ne "" -and $sid -ne $SourceId) { continue }

    # registry 에서 소스 정보 조회
    $row = $registry | Where-Object { $_.source_id -eq $sid } | Select-Object -First 1
    if ($null -eq $row) { Write-Host ("  [SKIP] {0} — registry 없음" -f $sid) -ForegroundColor DarkGray; $skipCount++; continue }
    if (-not (Test-LLPublishableSource $row)) {
        Write-Host ("  [SKIP] {0} — publish policy/category gate" -f $sid) -ForegroundColor DarkGray; $skipCount++; continue
    }

    $topic   = $row.topic
    $section = "learning"  # 기본값

    # classify JSON 에서 section 파싱 시도
    $classifyPath = Join-Path $Root "09_reports\llm_prep\processed\classify_$sid.json"
    if (-not (Test-Path $classifyPath)) {
        $classifyPath = Join-Path $Root "09_reports\llm_prep\classify_$sid.json"
    }
    if (Test-Path $classifyPath) {
        try {
            $cj = [System.IO.File]::ReadAllText($classifyPath, [System.Text.Encoding]::UTF8)
            if ($cj -match '"target_section"\s*:\s*"([^"]+)"') { $section = $Matches[1] }
        } catch {}
    }
    # section 정규화 — learning/projects 2개로만 (생성AI/환경/데이터셋/도구/배포 → projects)
    $section = Get-LLBlogSection -Topic $topic -RawSection $section

    $chunkPolicy = Get-LLProcessingPolicy -SourceType $row.source_type -SourceCategory $row.source_category -FileType $row.file_type -ManualChunkChars $MaxCharsPerChunk
    $ChunkSize = $chunkPolicy.ChunkChars
    $DirectChars = $chunkPolicy.MaxDirectChars
    $OverlapChars = $chunkPolicy.OverlapChars

    $draftDir  = Join-Path $DraftsRoot $section
    $draftPath = Join-Path $draftDir "${topic}.md"

    Write-Host ""
    Write-Host ("  [{0}] {1}" -f $sid, $topic) -ForegroundColor Magenta
    Write-Host ("    LLM 입력 정책 ... direct≤{0}자 / chunk {1}자 / overlap {2}자" -f $DirectChars, $ChunkSize, $OverlapChars) -ForegroundColor DarkGray

    # 이미 발행된 글(06_published)은 draft 가 지워졌어도 재생성하지 않음 (과거 글 재처리 방지)
    if (-not $Force -and $publishedNames.Contains("${topic}.md")) {
        Write-Host "    blog_draft  ... SKIP (이미 발행됨 — 과거 글)" -ForegroundColor DarkGray
        $skipCount++; continue
    }
    # archived 상태(예: dev 로 옮긴 글)도 재생성 안 함
    if (-not $Force -and ($row.PSObject.Properties['status']) -and ($row.status -eq 'archived')) {
        Write-Host "    blog_draft  ... SKIP (archived — 수동 관리)" -ForegroundColor DarkGray
        $skipCount++; continue
    }

    if ((Test-Path $draftPath) -and (-not $Force)) {
        Write-Host "    blog_draft  ... SKIP (이미 존재, -Force 로 재생성)" -ForegroundColor DarkGray
        $skipCount++; continue
    }

    Write-Host ("    blog_draft  ... {0} " -f $ModelDraft) -ForegroundColor White -NoNewline

    try {
        if (-not (Test-Path $draftDir)) { New-Item -ItemType Directory -Path $draftDir -Force | Out-Null }

        $wContent = [System.IO.File]::ReadAllText($wf.FullName, [System.Text.Encoding]::UTF8)

        # ── 슬롯 채우기: 구조는 PS 조립, LLM 은 전부 plain-text 한 칸씩 ──
        #   (JSON 호출은 작은 모델에서 잘 깨지고 model runner crash 유발 → 제거)
        $llmText = { param($p) Invoke-OllamaGenerate -Model $ModelDraft -Prompt $p }

        # 워킹노트 컨텍스트 (frontmatter 제거 + direct 한도 컷)
        $noteCtx = Remove-ExtraHugoFrontMatter -Text $wContent
        if ($DirectChars -gt 0 -and $noteCtx.Length -gt $DirectChars) {
            $noteCtx = $noteCtx.Substring(0, $DirectChars)
        }

        # 생성 (placeholder 검출 시 런너 회복 대기 후 1회 전체 재생성 — 글당 최대 2회)
        $result = ""; $draftIssues = @()
        for ($genTry = 1; $genTry -le 2; $genTry++) {
            $conceptNames = @(Get-LLConceptList -NoteContent $noteCtx -LLMInvoker $llmText -MaxConcepts 4)
            if ($conceptNames.Count -eq 0) { $conceptNames = @("학습 내용") }

            $concepts = @()
            foreach ($cn in $conceptNames) {
                $concepts += [pscustomobject]@{
                    Name  = $cn
                    Slots = Get-LLConceptSlots -ConceptName $cn -NoteContext $noteCtx -LLMInvoker $llmText
                }
            }
            $review = Get-LLOverallReview -NoteContent $noteCtx -ConceptNames $conceptNames -LLMInvoker $llmText
            $postTitle = Get-BlogDraftTitle -Topic $topic -NoteContext $noteCtx -ConceptNames $conceptNames -LLMInvoker $llmText

            $result = New-LLOutlineFromSlots -Title $postTitle -Date $TodayStr -Section $section `
                        -Concepts $concepts -Review $review
            $result = Repair-LLIndentedCodeFences -Content $result   # 중첩/들여쓴 코드펜스 평탄화

            $draftIssues = @(Get-LLDraftQualityIssues -Content $result)
            if (($draftIssues -join " ") -notmatch 'placeholder') { break }   # placeholder 없으면 확정
            if ($genTry -lt 2) {
                Write-Host "    (placeholder 검출 — 런너 회복 대기 후 전체 재생성)" -ForegroundColor DarkYellow
                $null = Wait-LLOllamaReady
            }
        }
        [System.IO.File]::WriteAllText($draftPath, $result, [System.Text.Encoding]::UTF8)
        if ($draftIssues.Count -gt 0) {
            Update-RegistryStatus -Sid $sid -NewStatus "needs_review"
            Write-Host ("WARN ({0})" -f ($draftIssues -join ", ")) -ForegroundColor Yellow
            Write-Host ("    저장: 04_blog_drafts\{0}\{1}.md" -f $section, $topic) -ForegroundColor DarkGray
            Write-Host "    registry: working → needs_review" -ForegroundColor Yellow
        } else {
            Update-RegistryStatus -Sid $sid -NewStatus "drafted"
            Write-Host "OK" -ForegroundColor Green
            Write-Host ("    저장: 04_blog_drafts\{0}\{1}.md" -f $section, $topic) -ForegroundColor DarkGray
            Write-Host "    registry: working → drafted" -ForegroundColor DarkGray
        }
        $doneCount++
    } catch {
        Write-Host "FAIL" -ForegroundColor Red
        Write-Host ("    [ERROR] {0}" -f $_.Exception.Message) -ForegroundColor Red
        $errCount++
    }
}

# ─── 요약 ────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  결과 요약" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor DarkGray
Write-Host ("  생성 완료: {0}" -f $doneCount) -ForegroundColor Green
Write-Host ("  skip:     {0}" -f $skipCount)  -ForegroundColor DarkGray
if ($errCount -gt 0) { Write-Host ("  오류:     {0}" -f $errCount) -ForegroundColor Red }
Write-Host ""
Write-Host "  다음: LearningLog.bat → [6] publish 로 발행" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
