# TalkMate portable package builder — INCLUDES local model weights
# Target PC only needs Python + pip packages (no model download required).
param(
  [string]$OutName = "TalkMate-Portable.zip"
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ((Split-Path -Leaf $Root) -eq "scripts") { $Root = Split-Path -Parent $Root }
$Stage = Join-Path $Root "_pkg_stage"
$Zip = Join-Path $Root $OutName
$Models = Join-Path $Root "scripts\models"

Write-Host "Packaging TalkMate with bundled models..." -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $Models "kokoro-v1.0.onnx"))) {
  throw "Missing scripts\models\kokoro-v1.0.onnx — run deploy-local-tts.ps1 first"
}
if (-not (Test-Path (Join-Path $Models "faster-whisper-small\model.bin"))) {
  throw "Missing scripts\models\faster-whisper-small — copy whisper weights first"
}

if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Path $Stage | Out-Null

# Ship in-app deploy payloads that match scripts/
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "scripts\sync-embeds.ps1")
if ($LASTEXITCODE -ne 0) { throw "sync-embeds.ps1 failed with code $LASTEXITCODE" }

Copy-Item (Join-Path $Root "index.html") $Stage -Force
Copy-Item (Join-Path $Root "README*.md") $Stage -Force
Copy-Item (Join-Path $Root "01-First-Install.bat") $Stage -Force
Copy-Item (Join-Path $Root "02-Start-TalkMate.bat") $Stage -Force
Copy-Item (Join-Path $Root "03-Stop-TalkMate.bat") $Stage -Force
Copy-Item (Join-Path $Root "scripts") (Join-Path $Stage "scripts") -Recurse -Force
Copy-Item (Join-Path $Root "assets") (Join-Path $Stage "assets") -Recurse -Force

# keep models; strip only junk
Remove-Item (Join-Path $Stage "scripts\__pycache__") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Stage "scripts\models\__pycache__") -Recurse -Force -ErrorAction SilentlyContinue

# inventory
Write-Host "Bundled models:" -ForegroundColor Yellow
Get-ChildItem (Join-Path $Stage "scripts\models") -Recurse -File |
  ForEach-Object { "  {0}  {1:N1} MB" -f $_.FullName.Substring($Stage.Length+1), ($_.Length/1MB) }

if (Test-Path $Zip) { Remove-Item $Zip -Force }
# Compress-Archive can be slow/heavy on 1GB+; still works for portable zip
Compress-Archive -Path (Join-Path $Stage "*") -DestinationPath $Zip -Force
$size = [math]::Round((Get-Item $Zip).Length / 1MB, 2)
Write-Host "Package: $Zip ($size MB)" -ForegroundColor Green
Write-Host "New PC: unzip -> 01-First-Install.bat (pip only, models already inside) -> 02-Start-TalkMate.bat" -ForegroundColor Cyan
Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
