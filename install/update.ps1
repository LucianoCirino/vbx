# Background updater (Windows). install.ps1 copies this to %LOCALAPPDATA%\vbx and schedules it
# every 15 minutes for the current user; it also runs once right after an install.
#
# Each run: read the installed game's version, look for the newest release of this repo built for
# that version, and install it when it is newer than what is installed, or when the game program is
# no longer the modded one (the game updated itself, or a release for the new version came out).
# Never while the game or its launcher is open. Log: %LOCALAPPDATA%\vbx\update.log
param([switch]$Now)
$ErrorActionPreference = "Stop"
$Repo = "LucianoCirino/vbx"
$Home_ = Join-Path $env:LOCALAPPDATA "vbx"
$Log = Join-Path $Home_ "update.log"
function Say($m) {
  $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $m
  Add-Content -Path $Log -Value $line
  if ((Get-Item $Log).Length -gt 200KB) { (Get-Content $Log -Tail 400) | Set-Content $Log }
  if ($Now) { Write-Host $m }
}
function Get-GameVersion($file) {
  $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($file))
  $m = [regex]::Match($text, '(?<=\x00)0\.\d+\.\d+(?=\x00)')
  if ($m.Success) { $m.Value } else { "" }
}

try {
  $Game = (Get-Content (Join-Path $Home_ "game.txt") -Raw).Trim()
  $Exe = Join-Path $Game "melee_source.exe"
  if (-not (Test-Path $Exe)) { Say "no game at $Game"; exit 0 }
  if (Get-Process melee_source, melee_port, MeleeUnlockedLauncher -ErrorAction SilentlyContinue) { if ($Now) { Say "game or launcher open: later" }; exit 0 }

  $Ver = Get-GameVersion $Exe
  if (-not $Ver) { Say "could not read the game version"; exit 0 }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $rels = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=40" -Headers @{ "User-Agent" = "vbx-updater"; "Accept" = "application/vnd.github+json" } -TimeoutSec 30
  $rel = $rels | Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -like "v$Ver-*" } |
         Where-Object { $_.assets | Where-Object { $_.name -like "*-windows.zip" } } | Select-Object -First 1
  if (-not $rel) { if ($Now) { Say "no build for game $Ver yet" }; exit 0 }

  $stateFile = Join-Path $Home_ "installed.txt"
  $state = if (Test-Path $stateFile) { (Get-Content $stateFile -Raw).Trim() -split '\s+' } else { @("", "") }
  $hash = (Get-FileHash $Exe -Algorithm SHA256).Hash.ToLower()
  if ($state[0] -eq $rel.tag_name -and $state[1] -eq $hash) { if ($Now) { Say "up to date ($($rel.tag_name))" }; exit 0 }

  $asset = $rel.assets | Where-Object { $_.name -like "*-windows.zip" } | Select-Object -First 1
  $tmp = Join-Path $env:TEMP ("vbx-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    $zip = Join-Path $tmp $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -Headers @{ "User-Agent" = "vbx-updater" } -TimeoutSec 300
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inst = Get-ChildItem -Path $tmp -Recurse -Filter install.ps1 | Select-Object -First 1
    if (-not $inst) { throw "no install.ps1 in $($asset.name)" }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $inst.FullName -Game $Game -NoPause -Quiet 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "install failed: $($out.Trim())" }
    Say "installed $($rel.tag_name) on game $Ver"
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
} catch {
  Say "error: $($_.Exception.Message)"
  exit 1
}
