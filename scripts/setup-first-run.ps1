# TalkMate first-run setup (Windows)
# Creates venvs and installs Python deps. Models are bundled in the portable zip.
param(
  [string]$WhisperModel = "small",
  [int]$AppPort = 8080,
  [int]$WhisperPort = 8787,
  [int]$TtsPort = 8788
)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
if ((Split-Path -Leaf $ScriptDir) -ne "scripts") {
  $Root = $ScriptDir
  $ScriptDir = Join-Path $Root "scripts"
}

function Test-RealPython {
  param([string]$Exe)
  if (-not $Exe) { return $false }
  if (-not (Test-Path $Exe)) { return $false }
  if ($Exe -like "*\WindowsApps\python*.exe") { return $false }
  try {
    $out = & $Exe -c "import sys; print(sys.version_info[0]); print(sys.version_info[1])" 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    $parts = @("$out".Trim() -split '\s+')
    return ($parts.Count -ge 2 -and $parts[0] -eq "3" -and [int]$parts[1] -ge 10)
  } catch {
    return $false
  }
}

function Get-PythonExe {
  if ($env:MIMO_PYTHON -and (Test-RealPython $env:MIMO_PYTHON)) { return $env:MIMO_PYTHON }
  if ($env:TALKMATE_PYTHON -and (Test-RealPython $env:TALKMATE_PYTHON)) { return $env:TALKMATE_PYTHON }
  $cmd = Get-Command python -ErrorAction SilentlyContinue
  if ($cmd) {
    $p = $cmd.Source
    if (Test-RealPython $p) { return $p }
    try {
      $r = (Get-Item $p).Target
      if ($r -and (Test-RealPython $r)) { return $r }
    } catch {}
  }
  $patterns = @(
    "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
    "$env:ProgramFiles\Python3*\python.exe",
    "C:\Python3*\python.exe"
  )
  foreach ($pat in $patterns) {
    $hits = Get-Item $pat -ErrorAction SilentlyContinue | Sort-Object FullName -Descending
    foreach ($h in $hits) {
      if (Test-RealPython $h.FullName) { return $h.FullName }
    }
  }
  throw "Real Python 3.10+ not found. Install from https://www.python.org/downloads/ and check Add python.exe to PATH. Ignore the Microsoft Store python alias."
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " TalkMate first-time setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Folder: $Root"
$PythonExe = Get-PythonExe
Write-Host "Python: $PythonExe"
& $PythonExe --version

Write-Host ""
Write-Host "[1/5] Whisper ASR (pip deps)..." -ForegroundColor Yellow
$BundledW = Join-Path $ScriptDir "models\faster-whisper-small"
if (Test-Path (Join-Path $BundledW "model.bin")) {
  Write-Host "  Bundled Whisper weights found (no model download)." -ForegroundColor Green
  $env:TALKMATE_WHISPER_PATH = $BundledW
} else {
  Write-Host "  No bundled Whisper weights; model may download on first start." -ForegroundColor Yellow
}
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "deploy-local-whisper.ps1") -Model $WhisperModel
if ($LASTEXITCODE -ne 0) { throw "Whisper setup failed" }

Write-Host ""
Write-Host "[2/5] Local TTS (pip deps)..." -ForegroundColor Yellow
if (Test-Path (Join-Path $ScriptDir "models\kokoro-v1.0.onnx")) {
  Write-Host "  Bundled Kokoro weights found (skip download)." -ForegroundColor Green
  powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "deploy-local-tts.ps1") -SkipModelDownload
} else {
  powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "deploy-local-tts.ps1")
}
if ($LASTEXITCODE -ne 0) { throw "TTS setup failed" }

Write-Host ""


Write-Host ""
Write-Host "[3/5] Ollama LLM check..." -ForegroundColor Yellow
$ollamaExe = $null
$cmd = Get-Command ollama -ErrorAction SilentlyContinue
if ($cmd) { $ollamaExe = $cmd.Source }
else {
  $cand = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
  if ($cand -and (Test-Path $cand)) { $ollamaExe = $cand }
}
if ($ollamaExe) {
  Write-Host "  ollama.exe: OK  $ollamaExe" -ForegroundColor Green
  try {
    $tags = Invoke-RestMethod "http://127.0.0.1:11434/api/tags" -TimeoutSec 5
    $n = @($tags.models).Count
    Write-Host "  Ollama API: OK  ($n models)" -ForegroundColor Green
    if ($n -eq 0) {
      Write-Host "  Run import-ollama-models.ps1 to register GGUF under .ollama\models" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "  Ollama API not running yet (start-all will try ollama serve)" -ForegroundColor Yellow
  }
} else {
  Write-Host "  ollama.exe not found - install Ollama or set TALKMATE_LOCAL_LLM_ROOT" -ForegroundColor Yellow
}
$llmRoot = Join-Path $env:USERPROFILE ".ollama\models"
if (Test-Path $llmRoot) {
  Get-ChildItem $llmRoot -Directory | ForEach-Object {
    if ($_.Name -in @("blobs","manifests")) { return }
    $g = Get-ChildItem $_.FullName -Filter *.gguf -EA SilentlyContinue | Where-Object { $_.Name -notmatch "mmproj|mtp-" } | Select-Object -First 1
    if ($g) { Write-Host ("  GGUF {0}  {1}MB" -f $_.Name, [math]::Round($g.Length/1MB,1)) -ForegroundColor DarkGray }
  }
}
Write-Host "[3/5] Local LLM models scan..." -ForegroundColor Yellow
$llmRoot = $env:TALKMATE_LOCAL_LLM_ROOT
if (-not $llmRoot) { $llmRoot = Join-Path $env:USERPROFILE ".ollama\models" }
if (-not (Test-Path $llmRoot)) {
  Write-Host "  Model root not found: $llmRoot" -ForegroundColor Yellow
} else {
  Write-Host "  Root: $llmRoot" -ForegroundColor DarkGray
  $found = @()
  Get-ChildItem $llmRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -eq "blobs") { return }
    $ggufs = Get-ChildItem $_.FullName -Filter *.gguf -ErrorAction SilentlyContinue
    if (-not $ggufs) { return }
    $main = $ggufs | Where-Object { $_.Name -notmatch 'mmproj|mtp-|draft' } | Sort-Object Length -Descending | Select-Object -First 1
    if (-not $main) { $main = $ggufs | Sort-Object Length -Descending | Select-Object -First 1 }
    $mm = $ggufs | Where-Object { $_.Name -match 'mmproj' } | Select-Object -First 1
    $sizeMB = [math]::Round($main.Length / 1MB, 1)
    Write-Host ("  OK  {0}  ({1} MB)  {2}" -f $_.Name, $sizeMB, $main.Name) -ForegroundColor Green
    if ($mm) { Write-Host ("      mmproj: {0}" -f $mm.Name) -ForegroundColor DarkGray }
    $found += [pscustomobject]@{
      id = $_.Name
      title = $_.Name
      alias = ($_.Name.ToLower() -replace '_','-')
      folder = $_.FullName
      gguf = $main.FullName
      mmproj = $(if ($mm) { $mm.FullName } else { "" })
      sizeMB = $sizeMB
      vision = [bool]$mm
    }
  }
  if ($found.Count -eq 0) {
    Write-Host "  No GGUF models found under $llmRoot" -ForegroundColor Yellow
  } else {
    $json = @{ root = $llmRoot; models = $found } | ConvertTo-Json -Depth 4
    $outJson = Join-Path $ScriptDir "local-models.json"
    Set-Content -Path $outJson -Value $json -Encoding UTF8
    Write-Host "  Wrote $($found.Count) models -> $outJson" -ForegroundColor Green
    Write-Host "  Select one in TalkMate Settings -> Local model" -ForegroundColor Cyan
  }
}

Write-Host "[4/5] Firewall (optional, needs admin once)..." -ForegroundColor Yellow
try {
  $fwRules = @(
    @('TalkMate 8080', $AppPort),
    @('TalkMate 8787', $WhisperPort),
    @('TalkMate 8788', $TtsPort)
  )
  $fwCmd = ($fwRules | ForEach-Object {
    $n = $_[0]; $p = $_[1]
    "if (-not (Get-NetFirewallRule -DisplayName '$n' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName '$n' -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow | Out-Null }"
  }) -join '; '
  Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile","-Command", $fwCmd
  Write-Host "  Firewall rules requested." -ForegroundColor Green
} catch {
  Write-Host "  Skipped firewall (no admin). Phone may need manual allow." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Setup done." -ForegroundColor Green
Write-Host "Next: run 02-Start-TalkMate.bat"
Write-Host "Then open http://127.0.0.1:$AppPort/"
$Lan = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.*" } | Select-Object -First 1 -ExpandProperty IPAddress)
if ($Lan) { Write-Host "Phone (same Wi-Fi): http://${Lan}:$AppPort/" }
Write-Host "Paste your DeepSeek API key in Settings, then Test LLM."
