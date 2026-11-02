# TalkMate - start App + Whisper + TTS + Ollama LLM
param(
  [int]$AppPort = 8080,
  [int]$WhisperPort = 8787,
  [int]$TtsPort = 8788,
  [int]$LlmPort = 11434,
  [string]$WhisperModel = "small",
  [string]$BindHost = "127.0.0.1",
  # LAN/phone access is opt-in: start with -BindHost 0.0.0.0 (and allow firewall).
  [string]$LocalLlmRoot = "",
  [string]$LlmModel = "",
  [switch]$SkipLocalLlm
)
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$VenvW = Join-Path $Root ".venv-whisper"
$VenvT = Join-Path $Root ".venv-tts"
$PyW = Join-Path $VenvW "Scripts\python.exe"
$PyT = Join-Path $VenvT "Scripts\python.exe"

if (-not $LocalLlmRoot) {
  if ($env:TALKMATE_LOCAL_LLM_ROOT) { $LocalLlmRoot = $env:TALKMATE_LOCAL_LLM_ROOT }
  else { $LocalLlmRoot = Join-Path $env:USERPROFILE ".ollama\models" }
}

if (-not (Test-Path $PyW) -or -not (Test-Path $PyT)) {
  Write-Host "[TalkMate] First run - installing Python deps..." -ForegroundColor Yellow
  powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "setup-first-run.ps1")
  if ($LASTEXITCODE -ne 0) { throw "setup-first-run.ps1 failed with code $LASTEXITCODE" }
  if (-not (Test-Path $PyW) -or -not (Test-Path $PyT)) {
    throw "Setup incomplete. Run 01-First-Install.bat first."
  }
}

# Only stop processes previously started by this script (tracked in $pidDir).
# Never kill an unrelated process that happens to own the port.
$pidDir = Join-Path $env:TEMP "talkmate-pids"
function Stop-Tracked([string]$Name) {
  $f = Join-Path $pidDir "$Name.pid"
  if (-not (Test-Path $f)) { return }
  $pid_ = (Get-Content $f -Raw).Trim()
  Remove-Item $f -Force -ErrorAction SilentlyContinue
  if ($pid_ -match '^\d+$') {
    try { Stop-Process -Id ([int]$pid_) -Force -ErrorAction Stop } catch {}
  }
}
function Save-Pid([string]$Name, [int]$Id) {
  New-Item -ItemType Directory -Path $pidDir -Force | Out-Null
  Set-Content -Path (Join-Path $pidDir "$Name.pid") -Value "$Id" -NoNewline
}
function Probe([string]$Url) {
  try { Invoke-RestMethod $Url -TimeoutSec 8 | Out-Null; return $true } catch { return $false }
}

$Lan = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
  $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*"
} | Select-Object -First 1 -ExpandProperty IPAddress)
if (-not $Lan) { $Lan = "127.0.0.1" }

Write-Host "[TalkMate] Starting services..." -ForegroundColor Cyan
$logDir = Join-Path $env:TEMP "talkmate-logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
# Keep exactly one previous run for diagnosis; Start-Process truncates on launch.
Get-ChildItem $logDir -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '\.log(\.err)?$' } |
  ForEach-Object { Move-Item $_.FullName ($_.FullName + ".1") -Force }
Write-Host "  logs: $logDir" -ForegroundColor DarkGray
Stop-Tracked "app"
Stop-Tracked "whisper"
Stop-Tracked "tts"
# Do NOT stop 11434 (Ollama system service)

$env:TALKMATE_HOST = $BindHost
$env:TALKMATE_WHISPER_MODEL = $WhisperModel
$env:TALKMATE_WHISPER_PORT = "$WhisperPort"
$env:TALKMATE_TTS_PORT = "$TtsPort"
$env:TALKMATE_APP_PORT = "$AppPort"
$env:TALKMATE_KOKORO_DIR = Join-Path $ScriptDir "models"
$BundledW = Join-Path $ScriptDir "models\faster-whisper-small"
if (Test-Path (Join-Path $BundledW "model.bin")) {
  $env:TALKMATE_WHISPER_PATH = $BundledW
  Write-Host "  Whisper weights: BUNDLED" -ForegroundColor Green
}

Write-Host "  App     http://127.0.0.1:$AppPort/"
if ($BindHost -eq "0.0.0.0") {
  Write-Host "  Phone   http://${Lan}:$AppPort/"
} else {
  Write-Host "  Phone   (LAN disabled — relaunch with -BindHost 0.0.0.0 for phone access)" -ForegroundColor DarkGray
}

$appScript = Join-Path $ScriptDir "_static_app.py"

$wlog = Join-Path $logDir "whisper.log"
$tlog = Join-Path $logDir "tts.log"
$alog = Join-Path $logDir "app.log"
# Visible window (not Hidden) with per-service logs so failures are diagnosable;
# PIDs are tracked for clean shutdown via Stop-Tracked.
$pw = Start-Process -FilePath $PyW -ArgumentList (Join-Path $ScriptDir "local_whisper_server.py") -WorkingDirectory $Root -RedirectStandardOutput $wlog -RedirectStandardError ($wlog + ".err") -PassThru
Save-Pid "whisper" $pw.Id
$pt = Start-Process -FilePath $PyT -ArgumentList (Join-Path $ScriptDir "local_tts_server.py") -WorkingDirectory $Root -RedirectStandardOutput $tlog -RedirectStandardError ($tlog + ".err") -PassThru
Save-Pid "tts" $pt.Id
$pa = Start-Process -FilePath $PyT -ArgumentList $appScript -WorkingDirectory $Root -RedirectStandardOutput $alog -RedirectStandardError ($alog + ".err") -PassThru
Save-Pid "app" $pa.Id

# ----- Ollama LLM -----
$llmNote = "skipped"
$llmOk = $false
if (-not $SkipLocalLlm) {
  $ollamaExe = $null
  $cmd = Get-Command ollama -ErrorAction SilentlyContinue
  if ($cmd) { $ollamaExe = $cmd.Source }
  $cand = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
  if (-not $ollamaExe -and $cand -and (Test-Path $cand)) {
    $ollamaExe = $cand
  }
  if (-not $ollamaExe) {
    Write-Host "  Ollama not found (skip Local LLM)" -ForegroundColor Yellow
    $llmNote = "ollama missing"
  } else {
    Write-Host "  Ollama: $ollamaExe" -ForegroundColor DarkGray
    if (-not (Probe "http://127.0.0.1:$LlmPort/api/tags")) {
      Write-Host "  Starting ollama serve..." -ForegroundColor Yellow
      try { Start-Process -FilePath $ollamaExe -ArgumentList "serve" -WindowStyle Hidden } catch {}
      Start-Sleep -Seconds 3
    }
    $tags = $null
    try {
      $tags = Invoke-RestMethod "http://127.0.0.1:$LlmPort/api/tags" -TimeoutSec 5
    } catch {}
    $names = @()
    if ($tags -and $tags.models) { $names = @($tags.models | ForEach-Object { $_.name -replace ':latest$','' }) }
    $pickName = $LlmModel
    if (-not $pickName -and $env:TALKMATE_LLM_MODEL) { $pickName = $env:TALKMATE_LLM_MODEL }
    if (-not $pickName -and $names.Count) {
      $pickName = ($names | Where-Object { $_ -like "*9b*" } | Select-Object -First 1)
      if (-not $pickName) { $pickName = $names[0] }
    }
    if (-not $pickName) { $pickName = "qwen3.8-9b-distill" }
    Write-Host "  Ollama model: $pickName" -ForegroundColor Green
    Write-Host "  API: http://127.0.0.1:$LlmPort/v1" -ForegroundColor DarkGray
    $llmNote = "ollama ready"
  }
}

Write-Host "Waiting for services (up to ~3 min for first Whisper load)..." -ForegroundColor DarkGray
$w = $false; $t = $false; $a = $false
for ($i = 1; $i -le 36; $i++) {
  if (-not $w) { $w = Probe "http://127.0.0.1:$WhisperPort/health" }
  if (-not $t) { $t = Probe "http://127.0.0.1:$TtsPort/health" }
  if (-not $a) { try { Invoke-WebRequest "http://127.0.0.1:$AppPort/index.html" -TimeoutSec 8 -UseBasicParsing | Out-Null; $a = $true } catch {} }
  if ($w -and $t -and $a) { break }
  Start-Sleep -Seconds 5
}
if (-not $w) { Write-Host "  Whisper still loading — see $wlog" -ForegroundColor Yellow }
$llmOk = Probe "http://127.0.0.1:$LlmPort/api/tags"
if ($llmOk) { $llmNote = "OK" } elseif ($llmNote -ne "ollama missing") { $llmNote = "API down" }

Write-Host ""
Write-Host "App     : $(if($a){'OK'}else{'FAIL'})  http://127.0.0.1:$AppPort/" -ForegroundColor $(if($a){'Green'}else{'Red'})
Write-Host "Whisper : $(if($w){'OK'}else{'FAIL / loading'})  http://127.0.0.1:$WhisperPort/health" -ForegroundColor $(if($w){'Green'}else{'Yellow'})
Write-Host "TTS     : $(if($t){'OK'}else{'FAIL'})  http://127.0.0.1:$TtsPort/health" -ForegroundColor $(if($t){'Green'}else{'Red'})
Write-Host "LLM     : $llmNote  Ollama http://127.0.0.1:$LlmPort/v1" -ForegroundColor $(if($llmOk){'Green'}else{'Yellow'})
Write-Host "Phone   : $(if(($a)-and($BindHost -eq '0.0.0.0')){"http://${Lan}:$AppPort/"}else{'LAN disabled'})" -ForegroundColor Green

try { Start-Process "http://127.0.0.1:$AppPort/" } catch {}
