# TalkMate - deploy local TTS mid-tier (Windows)
# Priority: Kokoro-82M ONNX -> edge-tts -> pyttsx3
param(
  [switch]$Start,
  [switch]$SkipModelDownload,
  [int]$Port = 8788,
  [string]$BindHost = "127.0.0.1"
)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$Venv = Join-Path $Root ".venv-tts"
$Server = Join-Path $ScriptDir "local_tts_server.py"
$DlScript = Join-Path $ScriptDir "download_kokoro_models.py"
$Models = Join-Path $ScriptDir "models"

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

Write-Host "[TalkMate] Deploy mid-tier local TTS (Kokoro + edge-tts)" -ForegroundColor Cyan
Write-Host "  server:  $Server"
Write-Host "  venv:    $Venv"
Write-Host "  models:  $Models"
Write-Host "  url:     http://${BindHost}:${Port}/v1"

$PythonExe = Get-PythonExe
Write-Host "  python:  $PythonExe"

if (-not (Test-Path $Server)) { throw "Missing $Server" }

if (-not (Test-Path (Join-Path $Venv "Scripts\python.exe"))) {
  Write-Host "[1/5] Create venv..." -ForegroundColor Yellow
  & $PythonExe -m venv $Venv
  if ($LASTEXITCODE -ne 0) { throw "venv create failed" }
} else {
  Write-Host "[1/5] venv exists" -ForegroundColor Green
}

$VenvPy = Join-Path $Venv "Scripts\python.exe"
if (-not (Test-Path $VenvPy)) { throw "Missing $VenvPy" }

Write-Host "[2/5] Install deps (pinned: scripts/requirements-tts.txt)..." -ForegroundColor Yellow
& $VenvPy -m pip install --upgrade pip | Out-Host
# kokoro-onnx 0.6.1 is not on PyPI: install everything else pinned first,
# then kokoro-onnx from its pinned GitHub source (see requirements-tts.txt note).
& $VenvPy -m pip install -r (Join-Path $ScriptDir "requirements-tts.txt")
if ($LASTEXITCODE -ne 0) { throw "pip install failed" }
Write-Host "  deps ready" -ForegroundColor Green

if (-not $SkipModelDownload) {
  Write-Host "[3/5] Download Kokoro ONNX weights (if missing)..." -ForegroundColor Yellow
  & $VenvPy $DlScript
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  WARN: model download incomplete; TTS will fall back to edge-tts" -ForegroundColor Yellow
  }
} else {
  Write-Host "[3/5] Skip model download" -ForegroundColor Yellow
}

$env:TALKMATE_TTS_PORT = "$Port"
$env:TALKMATE_HOST = $BindHost
$env:TALKMATE_KOKORO_DIR = $Models
Write-Host "[4/5] Env KOKORO_DIR=$Models port=$Port" -ForegroundColor Yellow
Write-Host "[5/5] Health http://${BindHost}:${Port}/health" -ForegroundColor DarkGray

if ($Start) { & $VenvPy $Server }
else {
  Write-Host "Ready. Start with:" -ForegroundColor Green
  Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Start"
  Write-Host "Phone (same Wi-Fi) should use: http://<PC-LAN-IP>:$Port/v1"
}
