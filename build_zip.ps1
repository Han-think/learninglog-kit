# build_zip.ps1 — 배포용 zip 생성 (API 키/잔여물 제외)
# 사용: 우클릭 → PowerShell 실행  또는  pwsh -File build_zip.ps1
#
# 동작:
#   1) 임시 스테이징 폴더로 필요한 파일만 복사
#   2) 실제 config.yaml(키 포함) / .git / __pycache__ / 생성물 제외
#   3) config.example.yaml 만 동봉
#   4) 키 문자열이 남아있으면 빌드 중단 (안전장치)
#   5) dist\learninglog-kit-<version>.zip 생성

$ErrorActionPreference = 'Stop'
$root  = $PSScriptRoot
$stage = Join-Path $env:TEMP ("ll_stage_" + [guid]::NewGuid().ToString('N').Substring(0,8))
$dist  = Join-Path $root 'dist'

# 버전 읽기
$ver = (Select-String -Path (Join-Path $root 'pyproject.toml') -Pattern '^version\s*=\s*"(.+?)"').Matches[0].Groups[1].Value
Write-Host "▶ 빌드 버전: $ver" -ForegroundColor Cyan

# 제외 패턴 (경로 일부 일치)
$exclude = @(
  '\.git\', '\.git$',
  '__pycache__', '.pyc',
  '\dist\', '\build\', '.egg-info',
  '\.learninglog\config.yaml',        # ★ 실제 키 파일
  '_with_key.bat', 'test_my_gemini.py',
  '\02_extracted\', '\03_working_notes\', '\04_blog_drafts\', '\09_reports\',
  'source_registry.csv'               # 개인 작업 장부
)

Write-Host "▶ 스테이징: $stage"
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Get-ChildItem -Path $root -Recurse -File | ForEach-Object {
  # 경로 정규화: 앞뒤 구분자를 \ 로 감싸 루트/하위 어디서든 패턴이 일치하도록
  $rel  = $_.FullName.Substring($root.Length).TrimStart('\')
  $norm = '\' + $rel + '\'
  foreach ($p in $exclude) { if ($norm -like "*$p*") { return } }
  $dest = Join-Path $stage $rel
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  Copy-Item $_.FullName $dest
}

# ── 안전장치: 키 잔여 검사 (AIza / AQ. / gsk_ / sk- 접두) ──
$leak = Get-ChildItem -Path $stage -Recurse -File |
  Select-String -Pattern 'AIza[0-9A-Za-z_\-]{20,}', 'AQ\.[0-9A-Za-z_\-]{20,}', 'gsk_[0-9A-Za-z]{20,}', 'sk-[0-9A-Za-z]{20,}' -List
if ($leak) {
  Write-Host "✗ 중단: 스테이징에 API 키로 보이는 문자열이 남아있습니다!" -ForegroundColor Red
  $leak | ForEach-Object { Write-Host "   $($_.Path)" -ForegroundColor Yellow }
  Remove-Item -Recurse -Force $stage
  exit 1
}

# ── zip 생성 ──
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zip = Join-Path $dist "learninglog-kit-$ver.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
Remove-Item -Recurse -Force $stage

$size = [math]::Round((Get-Item $zip).Length / 1MB, 2)
Write-Host "✓ 완료: $zip  ($size MB)" -ForegroundColor Green
Write-Host "  (실제 config.yaml/키/.git/생성물 제외 · config.example.yaml 동봉)" -ForegroundColor DarkGray
