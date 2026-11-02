# TalkMate - register local GGUF folders as Ollama models
# Usage: powershell -ExecutionPolicy Bypass -File import-ollama-models.ps1
$ErrorActionPreference = "Stop"
$Ollama = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $Ollama) {
  $cand = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
  if ($cand -and (Test-Path $cand)) { $Ollama = $cand } else { throw "ollama.exe not found" }
}
$ollamaExe = if ($Ollama -is [string]) { $Ollama } else { $Ollama.Source }

$root = $env:TALKMATE_LOCAL_LLM_ROOT
if (-not $root) { $root = Join-Path $env:USERPROFILE ".ollama\models" }
Write-Host "[TalkMate] Import GGUF models into Ollama" -ForegroundColor Cyan
Write-Host "  root: $root"
Write-Host "  ollama: $ollamaExe"

# ensure daemon (& does not throw on non-zero exit under Stop, so check $LASTEXITCODE)
& $ollamaExe list | Out-Null
if ($LASTEXITCODE -ne 0) {
  Start-Process $ollamaExe -ArgumentList "serve" -WindowStyle Hidden
  Start-Sleep -Seconds 3
}

Get-ChildItem $root -Directory | ForEach-Object {
  if ($_.Name -eq "blobs" -or $_.Name -eq "manifests") { return }
  $ggufs = Get-ChildItem $_.FullName -Filter *.gguf -ErrorAction SilentlyContinue
  if (-not $ggufs) { return }
  $main = $ggufs | Where-Object { $_.Name -notmatch 'mmproj|mtp-|draft' } | Sort-Object Length -Descending | Select-Object -First 1
  if (-not $main) { $main = $ggufs | Sort-Object Length -Descending | Select-Object -First 1 }
  $name = $_.Name.ToLower() -replace '_','-'
  if ($name -notmatch '^[a-z0-9][a-z0-9._-]*$') {
    Write-Host "  SKIP $($_.Name): unsafe model name" -ForegroundColor Yellow
    return
  }
  $ggufPath = $main.FullName
  if ($ggufPath -match '[\r\n]') {
    Write-Host "  SKIP ${name}: unsafe gguf path" -ForegroundColor Yellow
    return
  }
  Write-Host ""
  Write-Host "Import $name from $($main.Name) ..." -ForegroundColor Yellow
  $mf = Join-Path $env:TEMP ("talkmate-modelfile-" + $name + ".txt")
  try {
    @(
      "FROM $ggufPath"
    ) | Set-Content -Path $mf -Encoding UTF8
    & $ollamaExe create $name -f $mf
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  WARN: ollama create failed for $name" -ForegroundColor Yellow
    } else {
      Write-Host "  OK $name" -ForegroundColor Green
    }
  } finally {
    Remove-Item $mf -ErrorAction SilentlyContinue
  }
}

Write-Host ""
Write-Host "Ollama models now:" -ForegroundColor Cyan
& $ollamaExe list
