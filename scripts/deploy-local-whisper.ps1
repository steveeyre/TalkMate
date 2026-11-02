# TalkMate - deploy local Whisper ASR mid-tier (Windows)
# Default model: small  (English oral: can switch to distil-small.en)
param(
  [switch]$Start,
  [string]$Model = "small",
  [int]$Port = 8787,
  [string]$BindHost = "127.0.0.1"
)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$Venv = Join-Path $Root ".venv-whisper"
$Server = Join-Path $ScriptDir "local_whisper_server.py"

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

Write-Host "[TalkMate] Deploy mid-tier local Whisper ASR" -ForegroundColor Cyan
Write-Host "  server: $Server"
Write-Host "  venv:   $Venv"
Write-Host "  model:  $Model  (mid-tier default)"
Write-Host "  url:    http://${BindHost}:${Port}/v1"

$PythonExe = Get-PythonExe
Write-Host "  python: $PythonExe"

if (-not (Test-Path $Server)) { throw "Missing $Server" }

if (-not (Test-Path (Join-Path $Venv "Scripts\python.exe"))) {
  Write-Host "[1/4] Create venv..." -ForegroundColor Yellow
  & $PythonExe -m venv $Venv
  if ($LASTEXITCODE -ne 0) { throw "venv create failed" }
} else {
  Write-Host "[1/4] venv exists" -ForegroundColor Green
}

$VenvPy = Join-Path $Venv "Scripts\python.exe"
if (-not (Test-Path $VenvPy)) { throw "Missing $VenvPy" }

Write-Host "[2/4] Install deps (pinned: scripts/requirements-whisper.txt)..." -ForegroundColor Yellow
& $VenvPy -m pip install --upgrade pip | Out-Host
& $VenvPy -m pip install -r (Join-Path $ScriptDir "requirements-whisper.txt")
if ($LASTEXITCODE -ne 0) { throw "pip install failed" }
Write-Host "  deps ready" -ForegroundColor Green

$env:TALKMATE_WHISPER_MODEL = $Model
$env:TALKMATE_WHISPER_PORT = "$Port"
$env:TALKMATE_HOST = $BindHost
Write-Host "[3/4] Env model=$Model" -ForegroundColor Yellow
Write-Host "[4/4] Health http://${BindHost}:${Port}/health" -ForegroundColor DarkGray
Write-Host "       First run downloads faster-whisper '$Model' weights." -ForegroundColor DarkGray

if ($Start) { & $VenvPy $Server }
else {
  Write-Host "Ready. Start with:" -ForegroundColor Green
  Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Start -Model $Model"
  Write-Host "Phone (same Wi-Fi): http://<PC-LAN-IP>:$Port/v1"
}
