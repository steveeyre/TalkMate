# Stop the App / Whisper / TTS processes started by start-all.ps1.
# Only PIDs tracked by start-all.ps1 are touched, and only while that PID still
# runs the expected script — a recycled PID must never be killed.
$ErrorActionPreference = "Stop"

$pidDir = Join-Path $env:TEMP "talkmate-pids"
$targets = [ordered]@{
  app     = "_static_app.py"
  whisper = "local_whisper_server.py"
  tts     = "local_tts_server.py"
}

$stopped = 0
foreach ($name in $targets.Keys) {
  $file = Join-Path $pidDir "$name.pid"
  if (-not (Test-Path $file)) { continue }
  $raw = (Get-Content $file -Raw).Trim()
  Remove-Item $file -Force -ErrorAction SilentlyContinue
  if ($raw -notmatch '^\d+$') {
    Write-Host "  $name : unreadable pid file, removed" -ForegroundColor Yellow
    continue
  }
  $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $raw" -ErrorAction SilentlyContinue
  if (-not $proc) {
    Write-Host "  $name : not running" -ForegroundColor DarkGray
    continue
  }
  if (([string]$proc.CommandLine) -notlike "*$($targets[$name])*") {
    Write-Host "  $name : pid $raw is another process, skipped" -ForegroundColor Yellow
    continue
  }
  Stop-Process -Id ([int]$raw) -Force -ErrorAction SilentlyContinue
  Write-Host "  $name : stopped (pid $raw)" -ForegroundColor Green
  $stopped++
}

if ($stopped -eq 0) {
  Write-Host "Nothing to stop. Ollama keeps running." -ForegroundColor DarkGray
} else {
  Write-Host "Stopped $stopped service(s). Ollama keeps running." -ForegroundColor Cyan
}
