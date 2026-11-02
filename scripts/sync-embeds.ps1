# Keep the <script type="text/plain"> deploy payloads in index.html identical
# to the canonical files in scripts/.
#   .\sync-embeds.ps1          rewrite index.html in place
#   .\sync-embeds.ps1 -Check   exit 1 if any block drifted (CI / packaging)
param([switch]$Check)
$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $Here
$IndexPath = Join-Path $Root "index.html"
$Utf8 = New-Object System.Text.UTF8Encoding($false)

$text = [IO.File]::ReadAllText($IndexPath, [Text.Encoding]::UTF8)
$nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }

$pairs = @(
  @{ Id = "embed-whisper-py";  Source = "local_whisper_server.py" },
  @{ Id = "embed-tts-py";      Source = "local_tts_server.py" },
  @{ Id = "embed-whisper-ps1"; Source = "deploy-local-whisper.ps1" },
  @{ Id = "embed-tts-ps1";     Source = "deploy-local-tts.ps1" }
)

$drift = @()
foreach ($p in $pairs) {
  $open = '<script type="text/plain" id="' + $p.Id + '">'
  $start = $text.IndexOf($open)
  if ($start -lt 0) { throw "index.html: block $($p.Id) not found" }
  $bodyStart = $start + $open.Length
  $bodyEnd = $text.IndexOf("</script>", $bodyStart)
  if ($bodyEnd -lt 0) { throw "index.html: block $($p.Id) is not terminated" }

  $src = [IO.File]::ReadAllText((Join-Path $Here $p.Source), [Text.Encoding]::UTF8)
  $src = $src -replace "`r`n", "`n"
  $src = $src.TrimStart([char]0xFEFF).TrimEnd("`n")
  $body = $nl + ($src -replace "`n", $nl) + $nl

  if ($text.Substring($bodyStart, $bodyEnd - $bodyStart) -ne $body) {
    if ($Check) {
      $drift += $p.Id
    } else {
      $text = $text.Substring(0, $bodyStart) + $body + $text.Substring($bodyEnd)
    }
  }
}

if ($Check) {
  if ($drift.Count -gt 0) {
    Write-Host "DRIFT: $($drift -join ', ') — run scripts\sync-embeds.ps1" -ForegroundColor Red
    exit 1
  }
  Write-Host "index.html embeds OK ($($pairs.Count) blocks)" -ForegroundColor Green
  exit 0
}

[IO.File]::WriteAllText($IndexPath, $text, $Utf8)
Write-Host "index.html embeds synced ($($pairs.Count) blocks)" -ForegroundColor Green
