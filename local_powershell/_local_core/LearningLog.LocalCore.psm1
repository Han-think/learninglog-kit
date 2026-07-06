#Requires -Version 7.0
Set-StrictMode -Version Latest

$script:LLRoot = Split-Path -Parent $PSScriptRoot
$script:LLRegistryFields = @(
    "source_id",
    "source_path",
    "file_name",
    "file_path",
    "file_type",
    "source_type",
    "source_category",
    "date_added",
    "created_at",
    "status",
    "topic",
    "language",
    "public_policy",
    "hash",
    "notes"
)

function Get-LLRoot { return $script:LLRoot }

function Get-LLPath {
    param([Parameter(Mandatory)][string]$RelativePath)
    return (Join-Path $script:LLRoot $RelativePath)
}

function Read-LLText {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-LLText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
}

function Get-LLRegistryPath {
    return (Get-LLPath "01_registry\source_registry.csv")
}

function Get-LLRegistryFields {
    return @($script:LLRegistryFields)
}

function Get-LLProp {
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][string]$Name,
        [string]$Default = ""
    )
    if ($null -eq $Row) { return $Default }
    $prop = $Row.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    return [string]$prop.Value
}

function Backup-LLFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Prefix = "backup"
    )
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    $backupDir = Get-LLPath "07_archive\backups"
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $name = "{0}_{1}{2}" -f $Prefix, $stamp, [System.IO.Path]::GetExtension($Path)
    $dest = Join-Path $backupDir $name
    Copy-Item -LiteralPath $Path -Destination $dest -Force
    return $dest
}

function Get-LLRelativePath {
    param([Parameter(Mandatory)][string]$FullPath)
    $rel = $FullPath.Replace($script:LLRoot + "\", "").Replace($script:LLRoot + "/", "")
    return $rel.Replace("\", "/").Normalize([System.Text.NormalizationForm]::FormC)
}

function Resolve-LLSourcePath {
    param([Parameter(Mandatory)][string]$SourcePath)
    if ([System.IO.Path]::IsPathRooted($SourcePath)) { return $SourcePath }
    return (Join-Path $script:LLRoot ($SourcePath -replace "/", "\"))
}

function Get-LLHash {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }
    catch { return "" }
}

function Get-LLTopicFromFilename {
    param([Parameter(Mandatory)][string]$FileName)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $name = $name -replace '_\d{4}-\d{2}-\d{2}', ''
    $name = $name -replace '\d{8}', ''
    $name = $name -replace '^PN_\d{4}-\d{2}-\d{2}_?', ''
    $name = $name -replace '^PN_\d*_?', ''
    $name = $name -replace '^SRC-\d{8}-\d{3}_?', ''
    $name = $name -replace '^SRC-\d+-\d+-?', ''
    $name = $name -replace '^\[.*?\]_?\s*', ''
    $name = $name.ToLowerInvariant().Trim()
    $name = $name -replace '[\s_]+', '-'
    $name = $name -replace '-+', '-'
    $name = $name.Trim('-')
    if ($name.Length -lt 3) { return "unclassified" }
    return $name
}

function Get-LLSourceMetadata {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [Parameter(Mandatory)][string]$InboxSubfolder
    )
    $ext = $File.Extension.ToLowerInvariant()
    $name = $File.Name
    $sourceType = "misc"
    $category = "misc"
    $policy = "internal-only"

    if ($name -like "*_INDEX.md") {
        $sourceType = "internal_note"; $category = "index_note"; $policy = "internal-only"
    } elseif ($name -like "CHECKPOINT_*.md") {
        $sourceType = "internal_note"; $category = "checkpoint"; $policy = "internal-only"
    } elseif ($ext -eq ".pdf") {
        $sourceType = "lecture"; $category = "lecture_pdf"; $policy = "internal-only"
    } elseif ($ext -eq ".ipynb") {
        $sourceType = "practice"; $category = "practice_notebook"; $policy = "private"
    } elseif ($ext -eq ".zip") {
        $sourceType = "archive"; $category = "zip_archive"; $policy = "internal-only"
    } elseif ($ext -in @(".png", ".jpg", ".jpeg", ".webp")) {
        $sourceType = "screenshot"; $category = "image"; $policy = "internal-only"
    } elseif ($name -like "PN_*.md" -or $InboxSubfolder -eq "personal_notes") {
        $sourceType = "personal_note"; $category = "personal_note"; $policy = "partial-public"
    } elseif ($name -like "SRC-*.md") {
        $sourceType = "intake_note"; $category = "intake_note"; $policy = "partial-public"
    } elseif ($InboxSubfolder -eq "chat_exports") {
        $sourceType = "chat_export"; $category = "chat_export"; $policy = "partial-public"
    } elseif ($InboxSubfolder -eq "web_notes") {
        $sourceType = "web_note"; $category = "web_note"; $policy = "partial-public"
    } elseif ($ext -in @(".md", ".txt")) {
        $sourceType = "personal_note"; $category = "personal_note"; $policy = "partial-public"
    }

    [pscustomobject]@{
        file_name       = $name
        file_path       = $File.FullName
        file_type       = $ext.TrimStart(".")
        source_type     = $sourceType
        source_category = $category
        public_policy   = $policy
        topic           = Get-LLTopicFromFilename $name
        hash            = Get-LLHash $File.FullName
    }
}

function Get-LLExistingIds {
    param([array]$Rows)
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Rows) {
        $id = Get-LLProp $row "source_id"
        if ($id) { $null = $ids.Add($id) }
    }
    return $ids
}

function Get-LLNextSourceId {
    param(
        [array]$Rows,
        [string]$DateString = (Get-Date -Format "yyyyMMdd")
    )
    $prefix = "SRC-$DateString-"
    $max = 0
    foreach ($row in $Rows) {
        $id = Get-LLProp $row "source_id"
        if ($id.StartsWith($prefix)) {
            $n = 0
            if ([int]::TryParse($id.Substring($prefix.Length), [ref]$n) -and $n -gt $max) { $max = $n }
        }
    }
    return "{0}{1}" -f $prefix, ($max + 1).ToString("D3")
}

function ConvertTo-LLRegistryRow {
    param([Parameter(Mandatory)]$Row)
    $sourcePath = Get-LLProp $Row "source_path"
    $absPath = Get-LLProp $Row "file_path"
    if (-not $absPath -and $sourcePath) { $absPath = Resolve-LLSourcePath $sourcePath }
    $fileName = Get-LLProp $Row "file_name"
    if (-not $fileName -and $sourcePath) { $fileName = [System.IO.Path]::GetFileName($sourcePath) }
    $fileType = Get-LLProp $Row "file_type"
    if (-not $fileType -and $fileName) { $fileType = [System.IO.Path]::GetExtension($fileName).TrimStart(".").ToLowerInvariant() }

    $sourceType = Get-LLProp $Row "source_type" "misc"
    $category = Get-LLProp $Row "source_category"
    if (-not $category) {
        $category = switch ($sourceType) {
            "lecture" { if ($fileType -eq "pdf") { "lecture_pdf" } else { "lecture" } }
            "personal_note" { "personal_note" }
            "chat_export" { "chat_export" }
            "web_note" { "web_note" }
            "screenshot" { "image" }
            default { $sourceType }
        }
    }
    $dateAdded = Get-LLProp $Row "date_added" (Get-Date -Format "yyyy-MM-dd")
    $hash = Get-LLProp $Row "hash"
    if (-not $hash -and $absPath -and (Test-Path -LiteralPath $absPath)) { $hash = Get-LLHash $absPath }
    $topicDefault = "unclassified"
    if ($fileName) { $topicDefault = Get-LLTopicFromFilename $fileName }

    $out = [ordered]@{}
    $out["source_id"] = Get-LLProp $Row "source_id"
    $out["source_path"] = $sourcePath
    $out["file_name"] = $fileName
    $out["file_path"] = $absPath
    $out["file_type"] = $fileType
    $out["source_type"] = $sourceType
    $out["source_category"] = $category
    $out["date_added"] = $dateAdded
    $out["created_at"] = Get-LLProp $Row "created_at" $dateAdded
    $out["status"] = Get-LLProp $Row "status" "registered"
    $out["topic"] = Get-LLProp $Row "topic" $topicDefault
    $out["language"] = Get-LLProp $Row "language" "ko"
    $out["public_policy"] = Get-LLProp $Row "public_policy" "internal-only"
    $out["hash"] = $hash
    $out["notes"] = Get-LLProp $Row "notes"
    return [pscustomobject]$out
}

function Save-LLRegistryRows {
    param([Parameter(Mandatory)][array]$Rows)
    $path = Get-LLRegistryPath
    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Rows | Select-Object $script:LLRegistryFields |
        Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8
}

function Ensure-LLRegistrySchema {
    $path = Get-LLRegistryPath
    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $path)) {
        @() | Select-Object $script:LLRegistryFields | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8
        return [pscustomobject]@{ upgraded = $true; backup = ""; rows = @() }
    }

    $rows = @(Import-Csv -LiteralPath $path -Encoding utf8)
    $headers = @()
    if ($rows.Count -gt 0) { $headers = @($rows[0].PSObject.Properties.Name) }
    else {
        $first = [System.IO.File]::ReadLines($path) | Select-Object -First 1
        if ($first) { $headers = @($first -split ",") }
    }
    $needsUpgrade = $false
    foreach ($field in $script:LLRegistryFields) {
        if ($headers -notcontains $field) { $needsUpgrade = $true; break }
    }

    if (-not $needsUpgrade) {
        return [pscustomobject]@{ upgraded = $false; backup = ""; rows = $rows }
    }

    $backup = Backup-LLFile -Path $path -Prefix "source_registry_pre_local_v05"
    $newRows = @($rows | ForEach-Object { ConvertTo-LLRegistryRow $_ })
    Save-LLRegistryRows $newRows
    return [pscustomobject]@{ upgraded = $true; backup = $backup; rows = $newRows }
}

function Get-LLRegistryRows {
    $null = Ensure-LLRegistrySchema
    $path = Get-LLRegistryPath
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return @(Import-Csv -LiteralPath $path -Encoding utf8)
}

function Set-LLRegistryStatus {
    param(
        [Parameter(Mandatory)][string]$SourceId,
        [Parameter(Mandatory)][string]$Status
    )
    $rows = @(Get-LLRegistryRows)
    $hit = $false
    foreach ($row in $rows) {
        if ((Get-LLProp $row "source_id") -eq $SourceId) {
            $row.status = $Status
            $hit = $true
        }
    }
    if ($hit) { Save-LLRegistryRows $rows }
    return $hit
}

function Test-LLMProcessableSource {
    param([Parameter(Mandatory)]$Row)
    $policy = Get-LLProp $Row "public_policy"
    $sourceType = Get-LLProp $Row "source_type"
    $category = Get-LLProp $Row "source_category"
    $fileType = Get-LLProp $Row "file_type"
    if ($policy -notin @("public", "partial-public")) { return $false }
    if ($sourceType -ne "personal_note") { return $false }
    if ($category -in @("lecture_pdf", "practice_notebook", "zip_archive", "image", "checkpoint", "index_note")) { return $false }
    if ($fileType -notin @("md", "txt")) { return $false }
    return $true
}

function Test-LLPublishableSource {
    param([Parameter(Mandatory)]$Row)
    $policy = Get-LLProp $Row "public_policy"
    $category = Get-LLProp $Row "source_category"
    if ($policy -notin @("public", "partial-public")) { return $false }
    if ($category -in @("lecture_pdf", "practice_notebook", "zip_archive", "image", "checkpoint", "index_note")) { return $false }
    return $true
}

function Get-LLProcessingPolicy {
    param(
        [string]$SourceType = "personal_note",
        [string]$SourceCategory = "personal_note",
        [string]$FileType = "md",
        [int]$ManualChunkChars = 0
    )

    $policy = [ordered]@{
        MaxDirectChars = 0
        ChunkChars     = 4000
        OverlapChars   = 300
        ReferenceOnly  = $false
    }

    if ($SourceCategory -in @("lecture_pdf", "index_note", "checkpoint", "practice_notebook", "zip_archive", "image")) {
        $policy.ReferenceOnly = $true
        $policy.ChunkChars = 3000
        $policy.OverlapChars = 0
    } elseif ($SourceType -eq "chat_export") {
        $policy.ChunkChars = 5000
        $policy.OverlapChars = 500
    } elseif ($SourceType -eq "personal_note" -and $FileType -in @("md", "txt")) {
        $policy.MaxDirectChars = 6000
        $policy.ChunkChars = 4000
        $policy.OverlapChars = 300
    }

    if ($ManualChunkChars -gt 0) { $policy.ChunkChars = $ManualChunkChars }
    return [pscustomobject]$policy
}

function Get-LLChunkSize {
    param(
        [int]$NumCtx = 8192,
        [string]$SourceType = "personal_note",
        [string]$SourceCategory = "personal_note",
        [string]$FileType = "md",
        [int]$ManualChunkChars = 0
    )
    return (Get-LLProcessingPolicy -SourceType $SourceType -SourceCategory $SourceCategory -FileType $FileType -ManualChunkChars $ManualChunkChars).ChunkChars
}

function Get-LLDirectCharLimit {
    param(
        [string]$SourceType = "personal_note",
        [string]$SourceCategory = "personal_note",
        [string]$FileType = "md"
    )
    return (Get-LLProcessingPolicy -SourceType $SourceType -SourceCategory $SourceCategory -FileType $FileType).MaxDirectChars
}

function Get-LLOverlapChars {
    param(
        [string]$SourceType = "personal_note",
        [string]$SourceCategory = "personal_note",
        [string]$FileType = "md"
    )
    return (Get-LLProcessingPolicy -SourceType $SourceType -SourceCategory $SourceCategory -FileType $FileType).OverlapChars
}

function Invoke-LLOllamaGenerate {
    param(
        [string]$BaseUrl = "http://127.0.0.1:11434",
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Prompt,
        [int]$NumPredict = 512,
        [int]$NumCtx = 8192
    )
    $bodyObj = [ordered]@{
        model = $Model
        prompt = $Prompt
        stream = $false
        options = [ordered]@{ num_predict = $NumPredict; num_ctx = $NumCtx }
    }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(($bodyObj | ConvertTo-Json -Depth 4 -Compress))
    $resp = Invoke-RestMethod -Uri "$BaseUrl/api/generate" -Method Post `
        -Body $bodyBytes -ContentType "application/json; charset=utf-8" -TimeoutSec 600 -ErrorAction Stop
    return $resp.response
}

function Split-LLTextChunks {
    param(
        [Parameter(Mandatory)][string]$Text,
        [int]$MaxChars = 4000,
        [int]$OverlapChars = 0
    )
    $paragraphs = $Text -split "(?m)^\s*$"
    $chunks = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    foreach ($para in $paragraphs) {
        $p = $para.Trim()
        if (-not $p) { continue }
        if ($current.Length + $p.Length + 2 -gt $MaxChars -and $current.Length -gt 0) {
            $chunks.Add($current.ToString().Trim())
            $null = $current.Clear()
        }
        $null = $current.AppendLine($p)
        $null = $current.AppendLine()
    }
    if ($current.Length -gt 0) { $chunks.Add($current.ToString().Trim()) }
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
        if ($i -eq 0) {
            $withOverlap.Add($result[$i])
            continue
        }
        $prev = $result[$i - 1]
        $tailLen = [Math]::Min($OverlapChars, $prev.Length)
        $tail = $prev.Substring($prev.Length - $tailLen)
        $withOverlap.Add("[이전 문맥 일부]`n$tail`n`n[현재 파트]`n$($result[$i])")
    }
    return $withOverlap
}

function Remove-ExtraHugoFrontMatter {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $lines = $Text -split "`r?`n"
    if ($lines.Count -eq 0) { return $Text }
    $start = 0
    if ($lines[0].Trim() -eq "---") {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq "---") { $start = $i + 1; break }
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
    $final = ($out -join "`n") -replace '(?m)[ \t]+$', ''
    return ($final.TrimEnd() + "`n")
}

function Get-LLArticleStructureStats {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)

    $stats = [ordered]@{
        purpose  = 0
        learned  = 0
        confused = 0
        practice = 0
        summary  = 0
        combined = 0
    }

    $inFence = $false
    foreach ($line in ($Content -split "`r?`n")) {
        if ($line -match '^\s*```') {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) { continue }
        if ($line -notmatch '^\s*#{2,4}\s+(.+?)\s*$') { continue }

        $heading = $Matches[1].Trim()
        $heading = $heading -replace '^\*\*(.+?)\*\*$', '$1'
        $heading = $heading.Trim().TrimEnd(":").TrimEnd("?").Trim()
        $heading = $heading -replace '^\*\*(.+?)\*\*$', '$1'
        $heading = $heading -replace '\s+', ' '

        if ($heading -match '왜\s*썼나\s*/\s*배운\s*것|왜\s*썼나.+정리된\s*이해|왜\s*썼나.+다음\s*복습') {
            $stats["combined"]++
            continue
        }
        if ($heading -in @("왜 썼나", "왜 이 글을 썼나")) { $stats["purpose"]++; continue }
        if ($heading -in @("배운 것", "오늘 배운 핵심") -or $heading -match '^배운 것\s*\(.+\)$') { $stats["learned"]++; continue }
        if ($heading -in @("헷갈린 것", "헷갈렸던 점", "헷갈렸던 지점", "헷갈리던 점", "헷갈릴 수 있는 점")) { $stats["confused"]++; continue }
        if ($heading -in @("실습 예시", "실습하면서 알게 된 것")) { $stats["practice"]++; continue }
        if ($heading -in @("정리된 이해", "이해 정리")) { $stats["summary"]++; continue }
    }

    return [pscustomobject]$stats
}

function Repair-LLMarkdownCodeFences {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)

    $lines = $Content -split "`r?`n"
    $out = [System.Collections.Generic.List[string]]::new()
    $inFence = $false

    foreach ($line in $lines) {
        if ($line -match '^\s*```') {
            $inFence = -not $inFence
            $out.Add($line)
            continue
        }

        if ($inFence -and $line -match '^\s*#{2,4}\s+') {
            $out.Add('```')
            $inFence = $false
        }

        $out.Add($line)
    }

    if ($inFence) { $out.Add('```') }
    $final = ($out -join "`n") -replace '(?m)[ \t]+$', ''
    return ($final.TrimEnd() + "`n")
}

function Get-LLArticleHeadingKind {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Heading)

    $h = $Heading.Trim()
    $h = $h -replace '^\*\*(.+?)\*\*$', '$1'
    $h = $h.Trim().TrimEnd(":").TrimEnd("?").Trim()
    $h = $h -replace '^\*\*(.+?)\*\*$', '$1'
    $h = $h -replace '^\d+[\.\)]\s*', ''
    $h = $h -replace '\s+', ' '

    if ($h -match '왜\s*썼나\s*/\s*배운\s*것|왜\s*썼나.+정리된\s*이해|왜\s*썼나.+다음\s*복습') { return "combined" }
    if ($h -in @("왜 썼나", "왜 이 글을 썼나")) { return "purpose" }
    if ($h -in @("배운 것", "오늘 배운 핵심") -or $h -match '^배운 것\s*\(.+\)$') { return "learned" }
    if ($h -in @("헷갈린 것", "헷갈렸던 점", "헷갈렸던 지점", "헷갈리던 점", "헷갈릴 수 있는 점")) { return "confused" }
    if ($h -in @("실습 예시", "실습하면서 알게 된 것")) { return "practice" }
    if ($h -in @("정리된 이해", "이해 정리")) { return "summary" }

    if ($h -match '실습|예시|코드|출력') { return "practice" }
    if ($h -match '헷갈|혼란|오해|주의') { return "confused" }
    if ($h -match '정리|이해|결론') { return "summary" }
    if ($h -match '목표|이유|왜') { return "purpose" }
    return "learned"
}

function ConvertTo-LLSingleArticleStructure {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)

    $content = Remove-ExtraHugoFrontMatter -Text $Content
    $content = $content -replace "헷갈릴린", "헷갈린"
    $content = $content -replace '(?m)(print\(count\)\s*#\s*출력:)\s*$', '$1 1'
    $content = $content -replace '(?m)(#\s*(출력|결과):)\s*$', '$1 확인 필요'
    $content = Repair-LLMarkdownCodeFences -Content $content

    $lines = $content -split "`r?`n"
    $frontMatter = [System.Collections.Generic.List[string]]::new()
    $bodyStart = 0
    if ($lines.Count -gt 1 -and $lines[0].Trim() -eq "---") {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq "---") {
                for ($j = 0; $j -le $i; $j++) { $frontMatter.Add($lines[$j]) }
                $bodyStart = $i + 1
                break
            }
        }
    }

    $segments = [System.Collections.Generic.List[object]]::new()
    $currentHeading = ""
    $currentLines = [System.Collections.Generic.List[string]]::new()
    $inFence = $false

    for ($i = $bodyStart; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*```') {
            $inFence = -not $inFence
            $currentLines.Add($line)
            continue
        }

        if (-not $inFence -and $line -match '^\s*#{2,4}\s+(.+?)\s*$') {
            if ($currentHeading -ne "" -or $currentLines.Count -gt 0) {
                $segments.Add([pscustomobject]@{
                    Heading = $currentHeading
                    Text = (($currentLines -join "`n").Trim())
                })
            }
            $currentHeading = $Matches[1].Trim()
            $currentLines = [System.Collections.Generic.List[string]]::new()
            continue
        }

        $currentLines.Add($line)
    }

    if ($currentHeading -ne "" -or $currentLines.Count -gt 0) {
        $segments.Add([pscustomobject]@{
            Heading = $currentHeading
            Text = (($currentLines -join "`n").Trim())
        })
    }

    $buckets = [ordered]@{
        purpose = [System.Collections.Generic.List[object]]::new()
        learned = [System.Collections.Generic.List[object]]::new()
        confused = [System.Collections.Generic.List[object]]::new()
        practice = [System.Collections.Generic.List[object]]::new()
        summary = [System.Collections.Generic.List[object]]::new()
    }

    foreach ($segment in $segments) {
        $heading = [string]$segment.Heading
        $text = ([string]$segment.Text).Trim()
        if (-not $heading -and -not $text) { continue }
        $kind = Get-LLArticleHeadingKind -Heading $heading
        if ($kind -eq "combined") {
            if ($text) {
                $buckets["learned"].Add([pscustomobject]@{ Heading = "학습 내용"; Text = $text })
            }
            continue
        }
        if (-not $buckets.Contains($kind)) { $kind = "learned" }

        $cleanHeading = $heading
        if (-not $cleanHeading) { $cleanHeading = "메모" }
        $cleanHeading = $cleanHeading -replace '^\*\*(.+?)\*\*$', '$1'
        $cleanHeading = $cleanHeading.Trim().TrimEnd(":").TrimEnd("?").Trim()
        if ($cleanHeading -match '왜\s*썼나|배운\s*것|오늘\s*배운\s*핵심|헷갈|정리된\s*이해|실습\s*예시') {
            $cleanHeading = switch ($kind) {
                "purpose" { "글을 남긴 이유" }
                "learned" { "학습 포인트" }
                "confused" { "혼동 포인트" }
                "practice" { "실습 기록" }
                "summary" { "이해 정리" }
                default { "학습 포인트" }
            }
        }
        if ($text) {
            $buckets[$kind].Add([pscustomobject]@{ Heading = $cleanHeading; Text = $text })
        }
    }

    function Add-LLArticleSection {
        param(
            [System.Collections.Generic.List[string]]$Out,
            [string]$Heading,
            [System.Collections.Generic.List[object]]$Items,
            [switch]$NumberedSubsections
        )
        $Out.Add("## $Heading")
        $Out.Add("")
        if ($Items.Count -eq 0) {
            $Out.Add("정리할 내용 없음.")
            $Out.Add("")
            return
        }
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $item = $Items[$i]
            if ($NumberedSubsections -and $Items.Count -gt 1) {
                $sub = ([string]$item.Heading).Trim()
                if (-not $sub) { $sub = "내용" }
                $Out.Add(("### {0}. {1}" -f ($i + 1), $sub))
                $Out.Add("")
            }
            $Out.Add(([string]$item.Text).Trim())
            $Out.Add("")
        }
    }

    $out = [System.Collections.Generic.List[string]]::new()
    if ($frontMatter.Count -gt 0) {
        foreach ($line in $frontMatter) { $out.Add($line) }
        $out.Add("")
    }

    Add-LLArticleSection -Out $out -Heading "왜 이 글을 썼나" -Items $buckets["purpose"]
    Add-LLArticleSection -Out $out -Heading "오늘 배운 핵심" -Items $buckets["learned"] -NumberedSubsections
    Add-LLArticleSection -Out $out -Heading "헷갈렸던 지점" -Items $buckets["confused"] -NumberedSubsections
    Add-LLArticleSection -Out $out -Heading "실습하면서 알게 된 것" -Items $buckets["practice"] -NumberedSubsections
    Add-LLArticleSection -Out $out -Heading "정리된 이해" -Items $buckets["summary"]

    # AI 생성 고지 (한국어/영어)
    $out.Add("---")
    $out.Add("")
    $out.Add("> 🤖 이 글은 로컬 LLM(AI)의 도움을 받아 작성되었습니다.")
    $out.Add("> This post was written with the help of a local LLM (AI).")
    $out.Add("")

    $final = ($out -join "`n") -replace '(?m)[ \t]+$', ''
    return ($final.TrimEnd() + "`n")
}

function Test-LLHasSummarySection {
    param([Parameter(Mandatory)][AllowEmptyString()][object]$Lines)
    if ($Lines -is [string]) { $Lines = $Lines -split "`r?`n" }
    $inFence = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        if ($line -match '^\s*##\s+총평\s*$') { return $true }
    }
    return $false
}

function Get-LLHugoAnchor {
    param([Parameter(Mandatory)][string]$HeadingText)
    $s = $HeadingText.Trim()
    $s = $s.ToLowerInvariant()
    $s = [regex]::Replace($s, '[^0-9a-z가-힣ㄱ-ㅎㅏ-ㅣ \-]', '')
    $s = $s -replace '\s+', '-'
    $s = $s -replace '-+', '-'
    $s = $s.Trim('-')
    return $s
}

function Add-LLTableOfContents {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Body)

    $lines = $Body -split "`r?`n"
    $headings = [System.Collections.Generic.List[object]]::new()
    $firstHeadingIdx = -1
    $inFence = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        if ($line -match '^##\s+(.+?)\s*$' -and $line -notmatch '^###') {
            $full = $Matches[1].Trim()
            if ($full -eq '목차') { continue }
            if ($firstHeadingIdx -lt 0) { $firstHeadingIdx = $i }
            # 번호 분리: '1. 개념 A' → num='1', label='개념 A'
            $num = ''
            $label = $full
            if ($full -match '^(\d+)[\.\)]\s*(.+)$') { $num = $Matches[1]; $label = $Matches[2].Trim() }
            $headings.Add([pscustomobject]@{ Num = $num; Label = $label; Anchor = (Get-LLHugoAnchor -HeadingText $full) })
        }
    }
    if ($headings.Count -eq 0 -or $firstHeadingIdx -lt 0) { return $Body }

    $toc = [System.Collections.Generic.List[string]]::new()
    $toc.Add("## 목차")
    foreach ($h in $headings) {
        if ($h.Num) {
            $toc.Add(("- {0}. [{1}](#{2})" -f $h.Num, $h.Label, $h.Anchor))
        } else {
            $toc.Add(("- [{0}](#{1})" -f $h.Label, $h.Anchor))
        }
    }
    $toc.Add("")
    $toc.Add("---")
    $toc.Add("")

    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq $firstHeadingIdx) { foreach ($t in $toc) { $out.Add($t) } }
        $out.Add($lines[$i])
    }
    return ($out -join "`n")
}

function ConvertTo-LLOutlineArticleStructure {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [string]$FallbackTitle = "",
        [string]$FallbackDate = "",
        [string]$FallbackSection = "learning"
    )

    # 0) BOM 제거
    $Content = $Content -replace "^﻿", ""

    # 1) 기존 후처리 재사용 (메타/오타/빈출력주석/펜스)
    $content = Remove-ExtraHugoFrontMatter -Text $Content
    $content = $content -replace "헷갈릴린", "헷갈린"
    $content = $content -replace '(?m)(#\s*(출력|결과):)\s*$', '$1 확인 필요'
    $content = Repair-LLMarkdownCodeFences -Content $content

    # 2) front matter / body 분리
    $lines = $content -split "`r?`n"
    $fmEnd = -1
    if ($lines.Count -gt 1 -and $lines[0].Trim() -eq "---") {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq "---") { $fmEnd = $i; break }
        }
    }
    $frontMatter = [System.Collections.Generic.List[string]]::new()
    $bodyStart = 0
    if ($fmEnd -gt 0) {
        for ($j = 0; $j -le $fmEnd; $j++) { $frontMatter.Add($lines[$j]) }
        $bodyStart = $fmEnd + 1
    }

    # 2b) front matter 정상성 검사. title:/draft: 없으면 깨진 것 → 정상 YAML 재구성
    $fmText = ($frontMatter -join "`n")
    $hasValidTitle = $fmText -match '(?m)^\s*title:\s*\S'
    if (-not $hasValidTitle) {
        # 깨진 fm 안에서 제목 후보 추출: '**제목: X**' 또는 '**title:** X' 또는 첫 의미줄
        $titleGuess = $FallbackTitle
        if ($fmText -match '제목[:：]\s*(.+)') { $titleGuess = ($Matches[1] -replace '[*`]', '').Trim() }
        elseif ($fmText -match '(?im)title[:：]\s*(.+)') { $titleGuess = ($Matches[1] -replace '[*`"]', '').Trim() }
        if (-not $titleGuess) { $titleGuess = "학습 노트" }
        $dateGuess = if ($FallbackDate) { $FallbackDate } else { (Get-Date -Format 'yyyy-MM-dd') }
        if ($fmText -match '(?m)date:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})') { $dateGuess = $Matches[1] }
        $frontMatter = [System.Collections.Generic.List[string]]::new()
        $frontMatter.Add("---")
        $frontMatter.Add(("title: `"{0}`"" -f ($titleGuess -replace '"', "'")))
        $frontMatter.Add(("date: {0}" -f $dateGuess))
        $frontMatter.Add("draft: true")
        $frontMatter.Add(("categories: [`"{0}`"]" -f $FallbackSection))
        $frontMatter.Add("tags: []")
        $frontMatter.Add("description: `"`"")
        $frontMatter.Add("---")
    }

    # 3) body 수집 + 기존 '## 목차' 블록 제거 (재생성용)
    $body = [System.Collections.Generic.List[string]]::new()
    $inFence = $false
    $skippingToc = $false
    for ($i = $bodyStart; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*```') { $inFence = -not $inFence; $body.Add($line); continue }
        if (-not $inFence -and $line -match '^##\s+목차\s*$') { $skippingToc = $true; continue }
        if ($skippingToc) {
            if (-not $inFence -and ($line -match '^##\s+' -or $line.Trim() -eq '---')) {
                $skippingToc = $false
            } else { continue }
        }
        $body.Add($line)
    }

    # 4) 총평 누락시 스텁 추가
    if (-not (Test-LLHasSummarySection -Lines $body)) {
        $body.Add("")
        $body.Add("## 총평")
        $body.Add("")
        $body.Add("### 오늘 전체에서 배운 것")
        $body.Add("정리 필요.")
        $body.Add("")
        $body.Add("### 다음에 조심할 것")
        $body.Add("정리 필요.")
        $body.Add("")
        $body.Add("### 다음 복습 주제")
        $body.Add("정리 필요.")
        $body.Add("")
    }

    # 5) 목차 자동 주입
    $bodyText = Add-LLTableOfContents -Body ($body -join "`n")

    # 6) 재조립
    $out = [System.Collections.Generic.List[string]]::new()
    if ($frontMatter.Count -gt 0) { foreach ($l in $frontMatter) { $out.Add($l) }; $out.Add("") }
    $out.Add($bodyText.TrimStart())
    $final = ($out -join "`n") -replace '(?m)[ \t]+$', ''
    return ($final.TrimEnd() + "`n")
}

# ─────────────────────────────────────────────────────────
# 슬롯 채우기(fill-in-the-blank) 방식 — 구조는 PS 조립, LLM은 텍스트만
# ─────────────────────────────────────────────────────────

function ConvertFrom-LLJsonResponse {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $t = $Raw.Trim()
    $t = $t -replace "^﻿", ""
    $t = $t -replace '(?s)^\s*```(?:json)?\s*', '' -replace '(?s)\s*```\s*$', ''
    $open  = $t.IndexOf('{')
    $close = $t.LastIndexOf('}')
    if ($open -lt 0 -or $close -le $open) { return $null }
    $json = $t.Substring($open, $close - $open + 1)
    try { return ($json | ConvertFrom-Json -ErrorAction Stop) }
    catch { return $null }
}

function Get-LLJsonField {
    param($Obj, [string]$Key, [string]$Default = "")
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Key]
    if ($p -and $p.Value) { return [string]$p.Value }
    return $Default
}

function Get-LLConceptList {
    param(
        [Parameter(Mandatory)][string]$NoteContent,
        [Parameter(Mandatory)][scriptblock]$LLMInvoker,
        [int]$MaxConcepts = 4
    )
    $prompt = @"
너는 학습 노트에서 다룬 핵심 개념을 추출하는 분류기다.
아래 노트는 같은 주제를 여러 번 반복하거나 잘린 부분이 있을 수 있다.
중복을 제거하고, 실제로 다룬 서로 다른 핵심 개념을 최대 $MaxConcepts 개까지 골라라.
개념명은 짧은 한국어 명사구로. (예: f-string 포매팅, 클래스와 인스턴스)
출력 규칙: 한 줄에 개념 하나씩, 개념명만. 번호/기호/설명/머리말 금지.

노트:
---
$NoteContent
"@
    # plain-text 로 받아 줄 단위 파싱 (JSON 의존 제거 → 작은 모델 안정성↑).
    # 빈 결과면 런너 죽음 의심 → 회복 대기 후 재시도.
    $names = @()
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try { $raw = [string](& $LLMInvoker $prompt) } catch { $raw = "" }
        foreach ($line in ($raw -split "`r?`n")) {
            $n = $line.Trim()
            $n = $n -replace '^\s*[\-\*\d\.\)\#]+\s*', ''   # 선두 번호/기호 제거
            $n = $n.Trim().Trim('"').Trim("'").Trim()
            if ($n -and $n.Length -le 40 -and $n -notmatch '[{}\[\]]') { $names += $n }
        }
        if ($names.Count -gt 0) { break }
        if ($attempt -lt 3) { $null = Wait-LLOllamaReady }
    }
    $names = @($names | Select-Object -Unique)
    if ($names.Count -gt $MaxConcepts) { $names = $names[0..($MaxConcepts-1)] }
    if ($names.Count -eq 0) { $names = @("학습 내용") }
    return $names
}

function Get-LLBlogSection {
    # 블로그 섹션을 learning/projects 2개로 정규화 (2026-06-09 확정).
    # 생성AI·환경구성·데이터셋·도구제작·패키지배포 → projects, 그 외 → learning.
    param([string]$Topic, [string]$RawSection = "")
    $n = (([string]$Topic) + " " + [string]$RawSection).ToLowerInvariant()
    $proj = @(
        'ai-tools','generative','stable-diffusion','audiocraft','magenta','videocrafter','diffusion',
        'environment','-env','conda','colab-local','pip-requirements','ollama-local','venv',
        'package-release','package-environment','classmap','learninglog-kit','local-tool-distribution',
        'pyrecipe','streamlit','dataset','crawl','bookcrawler','llm-design','hallucination'
    )
    foreach ($k in $proj) { if ($n -like "*$k*") { return 'projects' } }
    if ($RawSection -eq 'projects') { return 'projects' }
    return 'learning'
}

function Repair-LLIndentedCodeFences {
    # 들여쓴/중첩 코드펜스(``` )를 컬럼0으로 평탄화 → 'mismatched indented code fence' 차단 방지.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $lines = $Content -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(\s+)(```.*)$') { $lines[$i] = $Matches[2] }
    }
    return ($lines -join "`n")
}

function Wait-LLOllamaReady {
    # Ollama 런너가 죽었을 때 회복을 기다린다. /api/tags 5초 간격 폴링, 최대 $MaxWaitSec.
    # 응답이 돌아오면 모델 재로딩 여유로 5초 추가 대기 후 $true.
    param([int]$MaxWaitSec = 90, [string]$OllamaBase = "http://127.0.0.1:11434")
    $deadline = (Get-Date).AddSeconds($MaxWaitSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $null = Invoke-RestMethod "$OllamaBase/api/tags" -TimeoutSec 4 -ErrorAction Stop
            Start-Sleep -Seconds 5   # 모델 재로딩 여유
            return $true
        } catch {
            Write-Host "    (Ollama 회복 대기...)" -ForegroundColor DarkYellow
            Start-Sleep -Seconds 5
        }
    }
    return $false
}

function Get-LLFieldText {
    # 한 칸(필드)을 plain-text 로 채운다. JSON 파싱 없음 → 작은 모델에서도 잘 안 깨짐.
    # 빈 응답/예외 시 즉시 재시도하지 않고 Wait-LLOllamaReady 로 런너 회복을 기다린 뒤 재시도.
    param(
        [Parameter(Mandatory)][scriptblock]$LLMInvoker,
        [Parameter(Mandatory)][string]$Prompt,
        [int]$Retries = 3,
        [switch]$AllowEmpty
    )
    for ($i = 0; $i -le $Retries; $i++) {
        $failed = $false
        try { $r = ([string](& $LLMInvoker $Prompt)) } catch { $r = ""; $failed = $true }
        $r = $r.Trim()
        # 모델이 통째로 따옴표로 감싼 경우만 한 겹 제거 (코드블록은 보존)
        if ($r -match '^"(.*)"$' -and $r -notmatch '```') { $r = $Matches[1].Trim() }
        if ($r) { Start-Sleep -Seconds 2; return $r }   # 호출 간 간격 (런너 압박 방지)
        # code 칸 등: 예외가 아니라 '내용 없음'으로 비운 거면 정상 — 그대로 반환
        if ($AllowEmpty -and -not $failed) { return "" }
        # 빈 응답/예외 = 런너 죽음 의심 → 회복 대기 후 재시도
        if ($i -lt $Retries) { $null = Wait-LLOllamaReady }
    }
    return ""
}

function Get-LLConceptSlots {
    param(
        [Parameter(Mandatory)][string]$ConceptName,
        [Parameter(Mandatory)][string]$NoteContext,
        [Parameter(Mandatory)][scriptblock]$LLMInvoker
    )
    # 한 번에 5칸 JSON 대신, 칸 하나씩 plain-text 로 채운다(작은 모델 안정성↑).
    $ctx  = "학습 노트:`n---`n$NoteContext`n---`n"
    $rule = " 마크다운 헤딩(#) 금지. 학습자 1인칭 한국어. 강의 원문 복붙 금지. 사족/머리말 없이 본문만 출력."

    $why      = Get-LLFieldText -LLMInvoker $LLMInvoker -Prompt ($ctx + "개념 '$ConceptName' 을(를) 왜 배우게 됐는지 배경을 2~3문장으로 써라." + $rule)
    $confused = Get-LLFieldText -LLMInvoker $LLMInvoker -Prompt ($ctx + "개념 '$ConceptName' 에서 처음에 헷갈렸거나 오해했던 점을 2~3문장으로 써라." + $rule)
    $code     = Get-LLFieldText -LLMInvoker $LLMInvoker -AllowEmpty -Prompt ($ctx + "개념 '$ConceptName' 의 핵심을 보여주는 코드 예시'만' 출력하라. 반드시 백틱3개로 감싼 코드 블록 형태로. 출력 주석은 실제 값으로. 노트에 코드 근거가 없으면 아무것도 쓰지 마라.")
    $result   = Get-LLFieldText -LLMInvoker $LLMInvoker -Prompt ($ctx + "개념 '$ConceptName' 의 코드/실습 결과와 그 해석을 2~3문장으로 써라." + $rule)
    $summary  = Get-LLFieldText -LLMInvoker $LLMInvoker -Prompt ($ctx + "개념 '$ConceptName' 에서 최종적으로 정리된 이해를 2~3문장으로 써라." + $rule)

    if (-not $summary.Trim()) {
        $alt = @($result, $why, $confused | Where-Object { $_.Trim() } | Select-Object -First 1)
        $summary = if ($alt) { [string]$alt } else { '정리 필요.' }
    }
    return [pscustomobject]@{ why = $why; confused = $confused; code = $code; result = $result; summary = $summary }
}

function Get-LLOverallReview {
    param(
        [Parameter(Mandatory)][string]$NoteContent,
        [Parameter(Mandatory)][string[]]$ConceptNames,
        [Parameter(Mandatory)][scriptblock]$LLMInvoker
    )
    $list = ($ConceptNames -join ", ")
    # 총평도 칸 하나씩 plain-text 로 채운다.
    $ctx  = "학습 노트:`n---`n$NoteContent`n---`n오늘 다룬 개념들: $list`n"
    $rule = " 마크다운 헤딩 금지. 학습자 1인칭 한국어. 짧고 구체적으로. 사족 없이 본문만 출력."

    $learned = Get-LLFieldText -LLMInvoker $LLMInvoker -Prompt ($ctx + "'오늘 전체에서 배운 것'을 2~3문장으로 써라." + $rule)
    $caution = Get-LLFieldText -LLMInvoker $LLMInvoker -Prompt ($ctx + "'다음에 조심할 것'을 2~3문장으로 써라." + $rule)
    $review  = Get-LLFieldText -LLMInvoker $LLMInvoker -Prompt ($ctx + "'다음에 복습하거나 더 알아볼 주제'를 2~3문장으로 써라." + $rule)

    $fill = @($learned, $review, $caution | Where-Object { $_.Trim() } | Select-Object -First 1)
    $fillStr = if ($fill) { [string]$fill } else { '정리 필요.' }
    if (-not $learned.Trim()) { $learned = $fillStr }
    if (-not $caution.Trim()) { $caution = $fillStr }
    if (-not $review.Trim())  { $review  = $fillStr }
    return [pscustomobject]@{ learned = $learned; caution = $caution; review = $review }
}

function New-LLOutlineFromSlots {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Date,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][object[]]$Concepts,
        [Parameter(Mandatory)][object]$Review,
        [string[]]$Tags = @()
    )
    function _slot([string]$v, [string]$default = '정리 필요.') {
        $t = ([string]$v).Trim()
        if (-not $t) { return $default }
        return $t
    }

    $tagsYaml = if ($Tags.Count) { '["' + ($Tags -join '","') + '"]' } else { '[]' }
    $safeTitle = $Title -replace '"', "'"

    $sb = [System.Collections.Generic.List[string]]::new()
    $sb.Add('---')
    $sb.Add("title: `"$safeTitle`"")
    $sb.Add("date: $Date")
    $sb.Add('draft: true')
    $sb.Add("categories: [`"$Section`"]")
    $sb.Add("tags: $tagsYaml")
    $sb.Add("description: `"$safeTitle 학습 정리`"")
    $sb.Add('---')
    $sb.Add('')

    for ($i = 0; $i -lt $Concepts.Count; $i++) {
        $c = $Concepts[$i]; $s = $c.Slots
        $sb.Add(("## {0}. {1}" -f ($i + 1), $c.Name))
        $sb.Add('')
        $sb.Add('### 왜 이걸 보게 됐나');   $sb.Add((_slot $s.why));               $sb.Add('')
        $sb.Add('### 내가 헷갈린 지점');    $sb.Add((_slot $s.confused));          $sb.Add('')
        $sb.Add('### 시도한 코드 / 예시');  $sb.Add((_slot $s.code '예시 없음.'));  $sb.Add('')
        $sb.Add('### 결과와 해석');        $sb.Add((_slot $s.result));            $sb.Add('')
        $sb.Add('### 정리된 이해');        $sb.Add((_slot $s.summary));           $sb.Add('')
    }

    $sb.Add('## 총평'); $sb.Add('')
    $sb.Add('### 오늘 전체에서 배운 것'); $sb.Add((_slot $Review.learned)); $sb.Add('')
    $sb.Add('### 다음에 조심할 것');     $sb.Add((_slot $Review.caution)); $sb.Add('')
    $sb.Add('### 다음 복습 주제');       $sb.Add((_slot $Review.review));  $sb.Add('')

    $body = ($sb -join "`n")
    $body = Add-LLTableOfContents -Body $body
    $body = Repair-LLMarkdownCodeFences -Content $body
    $body = $body -replace "^﻿", ""
    return ($body.TrimEnd() + "`n")
}

function New-LLDailyPost {
    # 하루 오전/오후 합본 글 빌더. 노트 1개 = 섹션 1개 (### 무엇을 배웠나/헷갈렸던 점/정리된 이해).
    # 2026-06-08 수동 합본(시범 2편)과 동일 양식.
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Date,
        [Parameter(Mandatory)][ValidateSet("am","pm")][string]$Half,
        [Parameter(Mandatory)][object[]]$Sections,   # @{Heading;Learned;Confused;Code;Understood}
        [Parameter(Mandatory)][object]$Review,        # @{learned;caution;review}
        [string[]]$Tags = @(),
        [string]$Description = ""
    )
    function _s([string]$v, [string]$default = '정리 필요.') {
        $t = ([string]$v).Trim(); if (-not $t) { return $default }; return $t
    }
    $halfKo = if ($Half -eq "am") { "오전" } else { "오후" }
    $safeTitle = $Title -replace '"', "'"
    if (-not $Description) { $Description = "$Date $halfKo 학습 정리" }
    $safeDesc = $Description -replace '"', "'"
    $tagsYaml = if ($Tags.Count) { '["' + (($Tags | Select-Object -Unique) -join '","') + '"]' } else { '[]' }

    $sb = [System.Collections.Generic.List[string]]::new()
    $sb.Add('---')
    $sb.Add("title: `"$safeTitle`"")
    $sb.Add("date: $Date")
    $sb.Add('draft: false')
    $sb.Add('categories: ["learning"]')
    $sb.Add("tags: $tagsYaml")
    $sb.Add("description: `"$safeDesc`"")
    $sb.Add('ai_assisted: true')
    $sb.Add('ai_model: "local-llm"')
    $sb.Add('---')
    $sb.Add('')

    for ($i = 0; $i -lt $Sections.Count; $i++) {
        $sec = $Sections[$i]
        $sb.Add(("## {0}. {1}" -f ($i + 1), ($sec.Heading -replace '"', "'")))
        $sb.Add('')
        $sb.Add('### 무엇을 배웠나');   $sb.Add((_s $sec.Learned));    $sb.Add('')
        $sb.Add('### 헷갈렸던 점');     $sb.Add((_s $sec.Confused));   $sb.Add('')
        $sb.Add('### 정리된 이해');     $sb.Add((_s $sec.Understood)); $sb.Add('')
        $code = ([string]$sec.Code).Trim()
        if ($code) { $sb.Add($code); $sb.Add('') }
    }

    $sb.Add('## 총평'); $sb.Add('')
    $sb.Add("### 오늘 $halfKo 전체에서 배운 것"); $sb.Add((_s $Review.learned)); $sb.Add('')
    $sb.Add('### 다음에 조심할 것');             $sb.Add((_s $Review.caution)); $sb.Add('')
    $sb.Add('### 다음 복습 주제');               $sb.Add((_s $Review.review));  $sb.Add('')
    $sb.Add('> 🤖 이 글은 로컬 LLM(AI)의 도움을 받아 작성되었습니다.')
    $sb.Add('> This post was written with the help of a local LLM (AI).')

    $body = ($sb -join "`n")
    $body = Add-LLTableOfContents -Body $body
    $body = Repair-LLMarkdownCodeFences -Content $body
    $body = Repair-LLIndentedCodeFences -Content $body
    $body = $body -replace "^﻿", ""
    return ($body.TrimEnd() + "`n")
}

function Get-LLDraftQualityIssues {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $issues = [System.Collections.Generic.List[string]]::new()
    $fenceCount = ([regex]::Matches($Content, '(?m)^\s*```')).Count
    if (($fenceCount % 2) -ne 0) { $issues.Add("odd code fence count") }
    $fenceOpen = $false
    $fenceIndent = 0
    foreach ($line in ($Content -split "`r?`n")) {
        if ($line -notmatch '^(\s*)```') { continue }
        $indent = $Matches[1].Length
        if (-not $fenceOpen) {
            $fenceOpen = $true
            $fenceIndent = $indent
        } else {
            if ($fenceIndent -gt 0 -and $indent -lt $fenceIndent) {
                $issues.Add("mismatched indented code fence")
                break
            }
            $fenceOpen = $false
            $fenceIndent = 0
        }
    }
    if ($Content -match '(?m)#\s*(출력|결과):\s*$') { $issues.Add("empty output/result comment") }
    # front matter 영역(맨 위 ---~---) 이후, 목차 구분선 1개는 허용.
    # 본문에 추가 '---'가 또 나오면(목차 구분선 외) front matter 누출로 간주.
    # 코드펜스 안의 '---'(SQL 주석 구분선 등)는 세지 않음 (오탐 방지)
    $inFenceD = $false; $allDelims = 0
    foreach ($dl in ($Content -split "`r?`n")) {
        if ($dl -match '^\s*```') { $inFenceD = -not $inFenceD; continue }
        if (-not $inFenceD -and $dl -match '^---\s*$') { $allDelims++ }
    }
    $allowedDelims = 2   # front matter open/close
    if ($Content -match '(?ms)^##\s+목차\s*$.*?^---\s*$') { $allowedDelims = 3 }  # + 목차 구분선
    if ($allDelims -gt $allowedDelims) { $issues.Add("extra front matter delimiter") }
    if ($Content -match '(?m)^\s*(source_id|note_date|mode|model):\s*') { $issues.Add("internal metadata") }
    if ($Content -match '(?m)^\s*\*\*(title|제목|date|날짜|draft|categories|category|카테고리|범주|tags|태그|description|설명)\*\*\s*:') { $issues.Add("bold metadata block") }
    $structure = Get-LLArticleStructureStats -Content $Content

    # 목차형 구조 게이트
    $bodyLines = $Content -split "`r?`n"

    # (a) ## 총평 필수
    if (-not (Test-LLHasSummarySection -Lines $bodyLines)) {
        $issues.Add("missing 총평 section")
    }

    # (b) 최상위 ## 중복만 차단 (### 면제). 코드펜스 밖, 정규화 후 텍스트 기준.
    $inFence = $false
    $topCounts = @{}
    foreach ($line in $bodyLines) {
        if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        if ($line -match '^##\s+(.+?)\s*$' -and $line -notmatch '^###') {
            $h = $Matches[1].Trim()
            $h = $h -replace '^\*\*(.+?)\*\*$', '$1'
            $h = $h.Trim().TrimEnd(":").TrimEnd("?").Trim()
            $h = $h -replace '\s+', ' '
            if ($topCounts.ContainsKey($h)) { $topCounts[$h]++ } else { $topCounts[$h] = 1 }
        }
    }
    $dupTop = @()
    foreach ($k in $topCounts.Keys) { if ($topCounts[$k] -gt 1) { $dupTop += ("{0}={1}" -f $k, $topCounts[$k]) } }
    if ($dupTop.Count -gt 0) { $issues.Add("repeated top-level ## headings: " + ($dupTop -join ", ")) }

    # (c) ## 목차 권장 (자동주입이 항상 넣으므로 정상 경로선 통과)
    if ($Content -notmatch '(?m)^##\s+목차\s*$') { $issues.Add("missing 목차 section") }

    # (d) 합쳐진 제목 검사 유지
    if ([int]$structure.combined -gt 0) { $issues.Add("combined outline heading") }

    # (e) 미완성 플레이스홀더 차단 — LLM 이 비운 섹션 (New-LLOutlineFromSlots 기본값 '정리 필요.')
    if ($Content -match '정리 필요\.') { $issues.Add("placeholder content (정리 필요)") }

    # (f) 제너릭 제목 차단 — front matter title 이 "학습 노트" 면 미작성으로 간주
    if ($Content -match '(?m)^\s*title:\s*"?학습 노트"?\s*$') { $issues.Add("generic title (학습 노트)") }
    $frontTitle = ""
    if ($Content -match '(?m)^\s*title:\s*"?(.+?)"?\s*$') { $frontTitle = $Matches[1].Trim() }
    if ($frontTitle -match '^[a-z0-9]+(?:[-_][a-z0-9]+){1,}$') { $issues.Add("generic title (slug)") }

    # (g) 잘린 문장 차단 — 코드펜스 밖 본문 문단이 한국어 연결어미/관형형으로 끝난 뒤
    #     빈 줄+heading 또는 문서 끝이 오면 중간에 잘린 것으로 간주.
    #     ('완료','필요' 같은 명사 종결 요약문 오탐 방지를 위해 연결형 어미로 한정)
    $inFenceT = $false
    for ($li = 0; $li -lt $bodyLines.Count; $li++) {
        $ln = $bodyLines[$li]
        if ($ln -match '^\s*```') { $inFenceT = -not $inFenceT; continue }
        if ($inFenceT) { continue }
        $t = $ln.Trim()
        if ($t.Length -lt 15) { continue }
        if ($t -match '^[#>\-\*\|]' ) { continue }   # heading/list/quote/table 제외
        # 연결어미/관형형으로 끝나면 잇따라 내용이 와야 함 (예: ~연결할, ~위한, ~하여, ~하고, ~되어, ~하는, ~에서)
        if ($t -notmatch '(할|하는|되는|위한|대한|하여|하고|되어|이며|에서|으로|면서|또는|그리고)$') { continue }
        $next = ""
        for ($nj = $li + 1; $nj -lt $bodyLines.Count; $nj++) {
            if ($bodyLines[$nj].Trim() -ne "") { $next = $bodyLines[$nj].Trim(); break }
        }
        if ($next -eq "" -or $next -match '^#') { $issues.Add("truncated sentence"); break }
    }

    return @($issues)
}

function ConvertTo-LLPublishMarkdown {
    param(
        [Parameter(Mandatory)][string]$Content,
        [string]$ModelName = "local-llm"
    )
    $content = Remove-ExtraHugoFrontMatter -Text $Content
    if ($content -notmatch "^---") { return $content }
    $lines = $content -split "`n"
    $fmEnd = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "---") { $fmEnd = $i; break }
    }
    if ($fmEnd -eq -1) { return $content }

    $fm = [System.Collections.Generic.List[string]]::new()
    $hasAi = $false
    foreach ($ln in $lines[1..($fmEnd - 1)]) {
        $s = $ln.Trim()
        if ($s.StartsWith("draft:")) { $fm.Add("draft: false"); continue }
        if ($s -match '^date:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})') {
            $fm.Add("date: $($Matches[1])")
            continue
        }
        if ($s.StartsWith("date:")) {
            $fm.Add("date: $(Get-Date -Format 'yyyy-MM-dd')")
            continue
        }
        if ($s.StartsWith("source_id:")) { continue }
        if ($s.StartsWith("note_date:")) { continue }
        if ($s.StartsWith("model:")) { continue }
        if ($s.StartsWith("mode:")) { continue }
        if ($s.StartsWith("ai_assisted:")) { $hasAi = $true }
        $fm.Add($ln)
    }
    if (-not $hasAi) {
        $fm.Add("ai_assisted: true")
        $fm.Add("ai_model: `"$ModelName`"")
    }

    $body = [System.Collections.Generic.List[string]]::new()
    for ($i = $fmEnd + 1; $i -lt $lines.Count; $i++) {
        $s = $lines[$i].Trim()
        if ($s.StartsWith("source_id:") -or $s.StartsWith("note_date:") -or $s.StartsWith("model:") -or $s.StartsWith("mode:")) { continue }
        $body.Add($lines[$i])
    }
    return "---`n" + ($fm -join "`n") + "`n---`n" + (($body -join "`n").TrimStart()) + "`n"
}

# ─────────────────────────────────────────────────────────
# Preview / Approve 안전장치 (Preview First, Publish Later)
# ─────────────────────────────────────────────────────────

function Get-LLRowProp {
    # Get-LLProp 의 null-safe 래퍼 (Row 가 null 이어도 OK)
    param($Row, [Parameter(Mandatory)][string]$Name, [string]$Default = "")
    if ($null -eq $Row) { return $Default }
    return (Get-LLProp -Row $Row -Name $Name -Default $Default)
}

function ConvertTo-LLHtmlEncoded {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $t = $Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
    return $t
}

function Get-LLDraftSourceId {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    if ($Content -match '(?m)^\s*source_id:\s*(\S+)') { return $Matches[1].Trim() }
    return ""
}

function Get-LLDraftTitle {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    if ($Content -match '(?m)^\s*title:\s*"?(.+?)"?\s*$') { return $Matches[1].Trim() }
    return ""
}

function Resolve-LLOriginalNotePath {
    param($Row)
    $p = Get-LLRowProp $Row "source_path"
    if (-not $p) { return "" }
    return (Resolve-LLSourcePath $p)
}

function Resolve-LLPreviewOriginalNote {
    param($Row)

    $path = Resolve-LLOriginalNotePath $Row
    $category = (Get-LLRowProp $Row "source_category").ToLowerInvariant()
    $topic = Get-LLRowProp $Row "topic"

    if ($category -eq "daily_merged" -and $topic -match '^(\d{4}-\d{2}-\d{2})-(am|pm)-daily$') {
        $date = $Matches[1]
        $slot = $Matches[2].ToLowerInvariant()
        $slotLabel = $slot.ToUpperInvariant()
        $slotPattern = "(?i)PN_" + [regex]::Escape($date) + "_" + $slotLabel + "_"
        $rows = @(Get-LLRegistryRows)
        $memberCandidates = @($rows | Where-Object {
            $sourceType = (Get-LLProp $_ "source_type").ToLowerInvariant()
            $sourcePath = Get-LLProp $_ "source_path"
            $memberTopic = (Get-LLProp $_ "topic").ToLowerInvariant()
            $dateAdded = Get-LLProp $_ "date_added"
            $sourceType -in @("personal_note","chat_export","intake_note","web_note") -and
            $dateAdded -eq $date -and
            (
                $memberTopic.StartsWith("$slot-") -or
                $sourcePath -match $slotPattern
            )
        })
        $members = @($memberCandidates | Sort-Object { Get-LLProp $_ "topic" })

        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($m in $members) {
            $memberPath = Resolve-LLSourcePath (Get-LLProp $m "source_path")
            if (-not $memberPath -or -not (Test-Path -LiteralPath $memberPath)) { continue }
            $title = Get-LLProp $m "topic"
            if (-not $title) { $title = Split-Path -LeafBase $memberPath }
            $memberRel = Get-LLRelativePath $memberPath
            $memberHeading = "## " + $title
            $memberSourceLine = "출처: " + $memberRel
            $parts.Add($memberHeading)
            $parts.Add("")
            $parts.Add($memberSourceLine)
            $parts.Add("")
            $parts.Add((Read-LLText $memberPath).Trim())
            $parts.Add("")
        }

        if ($parts.Count -gt 0) {
            $header = [System.Collections.Generic.List[string]]::new()
            $header.Add("# 원본 노트 묶음")
            $header.Add("")
            $header.Add("daily 합본 글의 멤버 원본을 모아 보여줍니다.")
            $header.Add("")
            return [pscustomobject]@{
                Path = "daily source bundle"
                Text = (($header + $parts) -join "`n").TrimEnd() + "`n"
            }
        }
    }

    $text = ""
    if ($path -and (Test-Path -LiteralPath $path)) {
        $text = Read-LLText $path
    }
    return [pscustomobject]@{ Path = $path; Text = $text }
}

function Get-LLDraftBadges {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        $Row
    )
    $issues = @(Get-LLDraftQualityIssues -Content $Content)
    $qaPass = ($issues.Count -eq 0)
    $badges = [System.Collections.Generic.List[object]]::new()

    if ($qaPass) {
        $badges.Add([pscustomobject]@{ text = "QA PASS"; cls = "ok" })
    } else {
        $badges.Add([pscustomobject]@{ text = "REVIEW NEEDED"; cls = "warn" })
        $joined = ($issues -join " ")
        if ($joined -match 'code fence|mismatched|empty output') { $badges.Add([pscustomobject]@{ text = "CODE FENCE"; cls = "warn" }) }
        if ($joined -match 'front matter delimiter')             { $badges.Add([pscustomobject]@{ text = "FRONTMATTER"; cls = "warn" }) }
        if ($joined -match 'internal metadata|bold metadata')    { $badges.Add([pscustomobject]@{ text = "SOURCE LEAK"; cls = "danger" }) }
        if ($joined -match 'missing 총평|missing 목차|repeated|combined') { $badges.Add([pscustomobject]@{ text = "STRUCTURE"; cls = "warn" }) }
    }

    $policy = (Get-LLRowProp $Row "public_policy").ToLowerInvariant()
    switch ($policy) {
        "internal-only"  { $badges.Add([pscustomobject]@{ text = "INTERNAL-ONLY"; cls = "danger" }) }
        "private"        { $badges.Add([pscustomobject]@{ text = "PRIVATE"; cls = "danger" }) }
        "partial-public" { $badges.Add([pscustomobject]@{ text = "PARTIAL"; cls = "warn" }) }
        "public"         { $badges.Add([pscustomobject]@{ text = "PUBLIC"; cls = "ok" }) }
        default          { if (-not $Row) { $badges.Add([pscustomobject]@{ text = "NO REGISTRY"; cls = "danger" }) } }
    }

    $status = (Get-LLRowProp $Row "status").ToLowerInvariant()
    if ($status -in @("needs_review", "archived", "rejected")) {
        $badges.Add([pscustomobject]@{ text = ("STATUS:" + $status); cls = "danger" })
    }

    $isByproduct = $false
    if ($Row) {
        $category = (Get-LLProp $Row "source_category").ToLowerInvariant()
        $sourceType = (Get-LLProp $Row "source_type").ToLowerInvariant()
        $isByproduct = (
            $category -ne "daily_merged" -and
            $policy -eq "partial-public" -and
            $sourceType -in @("personal_note", "chat_export", "intake_note", "web_note")
        )
    }
    if ($isByproduct) {
        $badges.Add([pscustomobject]@{ text = "BYPRODUCT"; cls = "warn" })
    }

    $policyOk = ($policy -in @("public", "partial-public"))
    $statusOk = ($status -notin @("needs_review", "archived", "rejected"))
    $canApprove = ($qaPass -and $policyOk -and $statusOk -and -not $isByproduct)

    return [pscustomobject]@{ qaPass = $qaPass; canApprove = $canApprove; isByproduct = $isByproduct; badges = @($badges) }
}

function Get-LLPublishedNames {
    # 06_published 의 모든 .md 파일명(소문자)을 HashSet 으로 반환.
    # "이미 발행됨" 판정의 단일 소스 (registry status 는 신뢰 불가).
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $pubDir = Get-LLPath "06_published"
    if (Test-Path -LiteralPath $pubDir) {
        foreach ($f in (Get-ChildItem -LiteralPath $pubDir -Recurse -Filter "*.md" -File)) {
            $null = $set.Add($f.Name)
        }
    }
    return $set
}

function Test-LLDraftAlreadyPublished {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$Draft,
        $Row,
        $PublishedNames
    )
    if ($PublishedNames -and $PublishedNames.Contains($Draft.Name)) { return $true }
    if ($Row) {
        $status = (Get-LLProp $Row "status").ToLowerInvariant()
        if ($status -eq "published") { return $true }
    }
    return $false
}

function Test-LLDraftByproduct {
    # 합본 daily 글이 발행 후보가 된 이후, partial-public 개별 노트 초안은
    # preview/approve 후보가 아니라 보관/정리 대상 부산물로 취급한다.
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$Draft,
        $Row
    )
    if (-not $Row) { return $false }
    $category = (Get-LLProp $Row "source_category").ToLowerInvariant()
    if ($category -eq "daily_merged") { return $false }

    $policy = (Get-LLProp $Row "public_policy").ToLowerInvariant()
    if ($policy -ne "partial-public") { return $false }

    $sourceType = (Get-LLProp $Row "source_type").ToLowerInvariant()
    return ($sourceType -in @("personal_note", "chat_export", "intake_note", "web_note"))
}

function Get-LLDraftDate {
    # 정렬 키. registry date_added(yyyy-MM-dd) 우선, 없으면 파일 LastWriteTime.
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$Draft,
        $Row
    )
    if ($Row) {
        $d = Get-LLProp $Row "date_added"
        if ($d) {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($d, [ref]$parsed)) { return $parsed }
        }
    }
    return $Draft.LastWriteTime
}

function New-LLPreviewDashboard {
    param(
        [Parameter(Mandatory)][string]$DraftsDir,
        [Parameter(Mandatory)][string]$OutDir,
        [switch]$IncludePublished,
        [switch]$IncludeByproducts,
        [string]$Section = ""
    )
    $sectionFilter = $Section.Trim().ToLowerInvariant()
    $rows = @(Get-LLRegistryRows)
    $rowBySid = @{}
    $rowByTopic = @{}
    foreach ($r in $rows) {
        $sid = Get-LLProp $r "source_id"
        if ($sid) { $rowBySid[$sid] = $r }
        $topic = Get-LLProp $r "topic"
        if ($topic) { $rowByTopic[$topic] = $r }
    }

    $publishedNames = Get-LLPublishedNames

    $items = [System.Collections.Generic.List[object]]::new()
    $excludedPublished = 0
    $excludedByproducts = 0
    if (Test-Path -LiteralPath $DraftsDir) {
        # 1-pass: row 매칭 + 정렬 키(date) 계산 후, 날짜 내림차순(최신순) 정렬
        $entries = foreach ($d in (Get-ChildItem -LiteralPath $DraftsDir -Recurse -Filter "*.md" -File)) {
            if ($sectionFilter) {
                $relFromDrafts = $d.FullName.Replace($DraftsDir + "\", "").Replace("\", "/")
                $draftSection = (($relFromDrafts -split "/")[0]).ToLowerInvariant()
                if ($draftSection -ne $sectionFilter) { continue }
            }
            $content = Read-LLText $d.FullName
            $sid = Get-LLDraftSourceId $content
            $row = $null
            if ($sid -and $rowBySid.ContainsKey($sid)) {
                $row = $rowBySid[$sid]
            } elseif ($rowByTopic.ContainsKey($d.BaseName)) {
                # slot 방식 draft 는 source_id 가 없으므로 파일명=topic 으로 역매칭
                $row = $rowByTopic[$d.BaseName]
                if (-not $sid) { $sid = Get-LLProp $row "source_id" }
            }
            [pscustomobject]@{
                File = $d; Content = $content; Sid = $sid; Row = $row
                Date = (Get-LLDraftDate -Draft $d -Row $row)
                IsPublished = (Test-LLDraftAlreadyPublished -Draft $d -Row $row -PublishedNames $publishedNames)
                IsByproduct = (Test-LLDraftByproduct -Draft $d -Row $row)
            }
        }
        $entries = @($entries | Sort-Object -Property Date -Descending)

        foreach ($e in $entries) {
            if ($e.IsPublished -and -not $IncludePublished) { $excludedPublished++; continue }
            if ($e.IsByproduct -and -not $IncludeByproducts) { $excludedByproducts++; continue }
            $d = $e.File; $content = $e.Content; $sid = $e.Sid; $row = $e.Row
            $b = Get-LLDraftBadges -Content $content -Row $row
            $badgeList = [System.Collections.Generic.List[object]]::new()
            foreach ($bd in $b.badges) { $badgeList.Add($bd) }
            if ($e.IsPublished) { $badgeList.Add([pscustomobject]@{ text = "PUBLISHED"; cls = "warn" }) }

            $title = Get-LLDraftTitle $content
            if (-not $title) { $title = $d.BaseName }
            $rel = Get-LLRelativePath $d.FullName
            $section = ($rel -split "/")[1]
            if (-not $section) { $section = "?" }

            $orig = Resolve-LLPreviewOriginalNote $row
            $origPath = $orig.Path
            $origB64 = ""
            if ($orig.Text) {
                $origB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$orig.Text))
            }
            $draftB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))

            $items.Add([pscustomobject]@{
                name       = $d.Name
                rel        = $rel
                section    = $section
                sid        = $sid
                title      = $title
                policy     = (Get-LLRowProp $row "public_policy")
                status     = (Get-LLRowProp $row "status")
                canApprove = $b.canApprove
                isByproduct = $e.IsByproduct
                badges     = @($badgeList)
                origPath   = $origPath
                origB64    = $origB64
                draftB64   = $draftB64
            })
        }
    }

    $itemArray = $items.ToArray()
    $dataJson = ($itemArray | ConvertTo-Json -Depth 6 -Compress)
    if (-not $dataJson) {
        $dataJson = "[]"
    } elseif ($itemArray.Count -eq 1 -and -not $dataJson.TrimStart().StartsWith("[")) {
        $dataJson = "[" + $dataJson + "]"
    }
    # </script> 차단: 평문 필드의 </ 를 <\/ 로 (본문은 Base64라 안전)
    $dataJson = $dataJson -replace '</', '<\/'
    $metaJson = ([pscustomobject]@{
        count = $items.Count
        excludedPublished = $excludedPublished
        excludedByproducts = $excludedByproducts
    } | ConvertTo-Json -Compress)

    $template = @'
<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<title>LearningLog Preview Dashboard</title>
<script src="__MARKED__"></script>
<style>
  body{margin:0;font-family:'Malgun Gothic',sans-serif;background:#1a1713;color:#eee;display:flex;height:100vh}
  #list{width:300px;overflow:auto;border-right:1px solid #333;padding:8px;flex-shrink:0}
  #summary{font-size:.75rem;line-height:1.5;color:#bbb;background:#211d17;border:1px solid #332d22;border-radius:6px;padding:7px;margin-bottom:8px}
  #summary b{color:#f0d58d}
  #list .item{padding:8px;border-radius:6px;cursor:pointer;margin-bottom:6px;background:#23201a;border:1px solid #2c2820}
  #list .item:hover{background:#2d2718}
  #list .item.on{border-color:#c49a4a}
  #list .t{font-size:.9rem;font-weight:600;margin-bottom:4px}
  #list .f{font-size:.7rem;color:#888;word-break:break-all}
  #delbar{position:sticky;top:0;background:#1a1713;padding:6px 0;border-bottom:1px solid #333;margin-bottom:8px;z-index:5}
  #delbar button{background:#5a1e1e;color:#fdd;border:1px solid #844;border-radius:6px;padding:4px 10px;cursor:pointer;font-size:.8rem}
  #delbar button:hover{background:#7a2828}
  .itemrow{display:flex;align-items:flex-start;gap:6px}
  .itemrow input{margin-top:10px;flex-shrink:0;accent-color:#c49a4a}
  .itemrow .item{flex:1}
  .delone{background:none;border:none;color:#a66;cursor:pointer;font-size:.9rem;padding:6px 2px;flex-shrink:0}
  .delone:hover{color:#f88}
  .badge{display:inline-block;padding:1px 6px;border-radius:10px;font-size:.65rem;margin:2px 2px 0 0}
  .ok{background:#1e4620;color:#9f9} .warn{background:#5a4a1a;color:#fd6} .danger{background:#5a1e1e;color:#f99}
  #view{flex:1;display:flex;overflow:hidden}
  .pane{flex:1;overflow:auto;padding:16px;border-left:1px solid #333}
  .pane h4{position:sticky;top:0;background:#1a1713;margin:0 0 12px;padding:6px 0;color:#c49a4a;border-bottom:1px solid #333}
  .render{background:#fff;color:#222;padding:20px;border-radius:8px;line-height:1.7}
  .render pre{background:#f4f4f4;padding:12px;border-radius:6px;overflow:auto}
  .render code{background:#eee;padding:1px 4px;border-radius:3px}
  .render pre code{background:none;padding:0}
  .render h1,.render h2,.render h3{border-bottom:1px solid #eee;padding-bottom:4px}
  .empty{color:#888;font-style:italic}
</style></head>
<body>
<div id="list"></div>
<div id="view">
  <div class="pane"><h4>원본 personal note</h4><div id="orig" class="render"></div></div>
  <div class="pane"><h4>블로그 초안 (발행될 모습)</h4><div id="draft" class="render"></div></div>
</div>
<script id="meta" type="application/json">__META__</script>
<script id="data" type="application/json">__DATA__</script>
<script>
  const META = JSON.parse(document.getElementById('meta').textContent);
  const RAW_DATA = JSON.parse(document.getElementById('data').textContent);
  const DATA = Array.isArray(RAW_DATA) ? RAW_DATA : (RAW_DATA ? [RAW_DATA] : []);
  function b64(b){ return new TextDecoder().decode(Uint8Array.from(atob(b), c=>c.charCodeAt(0))); }
  function show(i){
    document.querySelectorAll('#list .item').forEach((e,j)=>e.classList.toggle('on', j===i));
    const d = DATA[i];
    document.getElementById('orig').innerHTML  = d.origB64 ? marked.parse(b64(d.origB64)) : '<p class="empty">원본 note 없음</p>';
    document.getElementById('draft').innerHTML = marked.parse(b64(d.draftB64));
  }
  const list = document.getElementById('list');
  const summary = document.createElement('div');
  summary.id = 'summary';
  summary.innerHTML = '<b>표시 '+META.count+'개</b>'
    + (META.excludedPublished ? '<br>발행 제외 '+META.excludedPublished+'개' : '')
    + (META.excludedByproducts ? '<br>부산물 제외 '+META.excludedByproducts+'개' : '');
  list.appendChild(summary);
  const canDel = location.protocol === 'http:';   // 서버 모드에서만 삭제 가능
  function delOne(rel){ return fetch('/delete?f='+encodeURIComponent(rel)).then(r=>r.text()); }
  async function delSelected(){
    const sel=[...document.querySelectorAll('.sel:checked')].map(e=>DATA[+e.dataset.i]);
    if(!sel.length){ alert('선택된 글이 없습니다.'); return; }
    if(!confirm(sel.length+'개를 .trash 로 이동할까요? (복구 가능)')) return;
    for(const d of sel){ await delOne(d.rel); }
    location.reload();
  }
  async function delIdx(i, ev){
    ev.stopPropagation();
    const d=DATA[i];
    if(!confirm('"'+d.title+'" 을(를) .trash 로 이동할까요?')) return;
    await delOne(d.rel); location.reload();
  }
  if(canDel){
    const bar=document.createElement('div'); bar.id='delbar';
    bar.innerHTML='<button onclick="window.__delSel()">🗑 선택 삭제 (.trash)</button>';
    list.appendChild(bar);
    window.__delSel=delSelected; window.__delIdx=delIdx;
  }
  if(DATA.length===0){ list.innerHTML+='<p class="empty">04_blog_drafts 에 초안이 없습니다.</p>'; }
  DATA.forEach((d,i)=>{
    const row=document.createElement('div'); row.className='itemrow';
    const div=document.createElement('div'); div.className='item'; div.onclick=()=>show(i);
    const badges = Array.isArray(d.badges) ? d.badges : (d.badges ? [d.badges] : []);
    let bg=badges.map(b=>'<span class="badge '+b.cls+'">'+b.text+'</span>').join('');
    div.innerHTML='<div class="t">'+d.title+'</div><div class="f">'+d.section+' / '+d.name+'</div>'+bg;
    if(canDel){
      row.innerHTML='<input type="checkbox" class="sel" data-i="'+i+'" onclick="event.stopPropagation()">';
      row.appendChild(div);
      const db=document.createElement('button'); db.className='delone'; db.textContent='🗑';
      db.onclick=(ev)=>window.__delIdx(i,ev); row.appendChild(db);
    } else { row.appendChild(div); }
    list.appendChild(row);
  });
  if(DATA.length>0) show(0);
</script>
</body></html>
'@

    $html = $template.Replace('__MARKED__', '../../_local_core/vendor/marked.min.js').Replace('__META__', $metaJson).Replace('__DATA__', $dataJson)

    if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
    $htmlPath = Join-Path $OutDir "index.html"
    Write-LLText -Path $htmlPath -Content $html

    return @{ html = $htmlPath; count = $items.Count; items = @($items); excludedPublished = $excludedPublished; excludedByproducts = $excludedByproducts }
}

function Add-LLApprovalLogEntry {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$FileName,
        [string]$SourceId = "",
        [string]$Section = "",
        [string]$QaStatus = "PASS",
        [string]$ApprovedBy = $env:USERNAME,
        [string]$Notes = ""
    )
    $entry = [pscustomobject]@{
        approved_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        file_name   = $FileName
        source_id   = $SourceId
        section     = $Section
        qa_status   = $QaStatus
        approved_by = $ApprovedBy
        notes       = $Notes
    }
    $existing = @()
    if (Test-Path -LiteralPath $LogPath) {
        $existing = @(Import-Csv -LiteralPath $LogPath -Encoding utf8)
    }
    $all = @($existing) + @($entry)
    $parent = Split-Path -Parent $LogPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $all | Export-Csv -LiteralPath $LogPath -Encoding utf8 -NoTypeInformation
}

Export-ModuleMember -Function *-LL*, Remove-ExtraHugoFrontMatter, ConvertTo-LLPublishMarkdown
