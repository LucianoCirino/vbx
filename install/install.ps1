# Installer (Windows).
#
#   Double-click install.bat (or: powershell -ExecutionPolicy Bypass -File install.ps1 [-Game <folder>] [-Uninstall] [-NoAutoUpdate])
#
# Run it from the unzipped release folder (next to melee_source.exe, VERSION, TAG and SHA256SUMS).
# It only replaces the game program; settings, replays and the disc are not touched. The original
# program is kept as melee_source.release-<version>.exe beside it. Close the game first.
# To update, run it again: it looks online for the newest build for the installed game version
# (also after the game updated itself) and installs that instead. -Offline skips the check.
param([string]$Game = "", [switch]$Uninstall, [switch]$NoPause, [switch]$Quiet, [switch]$Offline, [switch]$NoProAI)
if ($Quiet) { $NoPause = $true }
function Wait-Close { if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null } }
function Say($m, $c = "Gray") { if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Home_ = Join-Path $env:LOCALAPPDATA "vbx"
$Task = "vbx-update"   # builds 1-2 set up a background task; removed on any install
$Repo = "LucianoCirino/vbx"

function Stop-Install($msg) { Write-Host "`nSTOPPED: $msg`nNothing was changed." -ForegroundColor Red; Wait-Close; exit 1 }
function Get-GameVersion($file) {
  $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($file))
  $m = [regex]::Match($text, '(?<=\x00)0\.\d+\.\d+(?=\x00)')
  if ($m.Success) { $m.Value } else { "" }
}
function Test-Modded($file) {
  $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($file))
  $text.Contains("padmod_cstick_up_jump")
}

if (-not $Game -and (Test-Path "$Home_\game.txt")) { $Game = (Get-Content "$Home_\game.txt" -Raw).Trim() }
# A typed or dragged path: quotes (either kind), PowerShell's "& '...'", spaces; the program itself
# (melee_source.exe or MeleeUnlocked.exe) dragged instead of its folder.
function Clean-Path($p) {
  $p = "$p".Trim()
  if ($p.StartsWith('&')) { $p = $p.Substring(1).Trim() }
  $p = $p.Trim('"', "'", ' ')
  if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { $p = Split-Path -Parent $p }
  return $p.TrimEnd('\')
}
function Find-Game {
  # The launcher or the game running from it, then the usual places (a folder named MeleeUnlocked*,
  # also one level down, as unzipping often makes MeleeUnlocked-x\MeleeUnlocked-x).
  foreach ($n in @("melee_source", "MeleeUnlocked")) {
    foreach ($pr in @(Get-Process $n -ErrorAction SilentlyContinue)) {
      try { $d = Split-Path -Parent $pr.Path; if (Test-Path "$d\melee_source.exe") { return $d } } catch {}
    }
  }
  $roots = @($env:LOCALAPPDATA, $env:USERPROFILE, "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads",
             "$env:USERPROFILE\Documents", "$env:USERPROFILE\OneDrive\Desktop", "$env:USERPROFILE\OneDrive\Documents",
             $env:ProgramFiles, "C:\Games", "C:\", "D:\", "E:\")
  foreach ($r in $roots) {
    if (-not $r -or -not (Test-Path $r)) { continue }
    foreach ($d in @(Get-ChildItem -LiteralPath $r -Directory -Filter "MeleeUnlocked*" -ErrorAction SilentlyContinue)) {
      if (Test-Path "$($d.FullName)\melee_source.exe") { return $d.FullName }
      foreach ($d2 in @(Get-ChildItem -LiteralPath $d.FullName -Directory -Filter "MeleeUnlocked*" -ErrorAction SilentlyContinue)) {
        if (Test-Path "$($d2.FullName)\melee_source.exe") { return $d2.FullName }
      }
    }
  }
  return ""
}
if ($Game) { $Game = Clean-Path $Game }
if (-not $Game) { $Game = Find-Game; if ($Game) { Say "Found the game in $Game" } }
for ($try = 0; -not ($Game -and (Test-Path "$Game\melee_source.exe")) -and -not $Quiet -and $try -lt 3; $try++) {
  if ($Game) { Write-Host "No melee_source.exe in '$Game'." -ForegroundColor Yellow }
  $Game = Clean-Path (Read-Host "Your Melee Unlocked folder (the one with melee_source.exe in it, NOT the ISO). Drag the folder here and press Enter")
}
$Exe = Join-Path $Game "melee_source.exe"
if (-not (Test-Path $Exe)) { Stop-Install "no melee_source.exe in '$Game'" }
if (Get-Process melee_source -ErrorAction SilentlyContinue) { Stop-Install "the game is running; close it first" }

$Installed = Get-GameVersion $Exe
if (-not $Installed) { Stop-Install "could not read the game's version" }

Unregister-ScheduledTask -TaskName $Task -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item "$Home_\update.ps1", "$Home_\update.log", "$Home_\installed.txt" -ErrorAction SilentlyContinue

if ($Uninstall) {
  Remove-Item -Recurse -Force $Home_ -ErrorAction SilentlyContinue
  $Bak = Join-Path $Game "melee_source.release-$Installed.exe"
  if (-not (Test-Modded $Exe)) { Say "The game program is already the original ($Installed)."; Wait-Close; exit 0 }
  if (-not (Test-Path $Bak)) { Stop-Install "no backup $Bak (update the game in its launcher instead: that puts the original back)" }
  Copy-Item $Bak $Exe -Force
  Say "Original $Installed program back. Start the game again." Green
  Wait-Close; exit 0
}

$New = Join-Path $Here "melee_source.exe"
if (-not (Test-Path $New) -or -not (Test-Path "$Here\VERSION")) { Stop-Install "run this from the unzipped release folder" }
$ModVer = (Get-Content "$Here\VERSION" -Raw).Trim()
$Tag = if (Test-Path "$Here\TAG") { (Get-Content "$Here\TAG" -Raw).Trim() } else { "v$ModVer" }

# A newer build online for this game version (or any build, when this zip is for another version):
# download it and let its own installer do the rest.
if (-not $Offline) {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rels = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=40" -Headers @{ "User-Agent" = "vbx-installer" } -TimeoutSec 20
    $rel = $rels | Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -like "v$Installed-*" } |
           Where-Object { $_.assets | Where-Object { $_.name -like "*-windows.zip" } } | Select-Object -First 1
    $build = { param($t) if ($t -match '-(\d+)$') { [int]$Matches[1] } else { 0 } }
    if ($rel -and ($ModVer -ne $Installed -or (& $build $rel.tag_name) -gt (& $build $Tag))) {
      Say "Newer build online: $($rel.tag_name). Downloading..." Cyan
      $asset = $rel.assets | Where-Object { $_.name -like "*-windows.zip" } | Select-Object -First 1
      $tmp = Join-Path $env:TEMP ("vbx-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
      New-Item -ItemType Directory -Path $tmp | Out-Null
      try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile "$tmp\b.zip" -UseBasicParsing -Headers @{ "User-Agent" = "vbx-installer" } -TimeoutSec 300
        Expand-Archive -Path "$tmp\b.zip" -DestinationPath $tmp -Force
        $inst = Get-ChildItem -Path $tmp -Recurse -Filter install.ps1 | Select-Object -First 1
        $args2 = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $inst.FullName, "-Game", $Game, "-Offline", "-NoPause")
        if ($Quiet) { $args2 += "-Quiet" }
        if ($NoProAI) { $args2 += "-NoProAI" }
        & powershell @args2
        $code = $LASTEXITCODE
      } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
      Wait-Close; exit $code
    }
  } catch {
    Say "Could not check for a newer build ($($_.Exception.Message)); installing this one." Yellow
  }
}
if ($Installed -ne $ModVer) {
  Stop-Install "your game is $Installed, this build is for $ModVer.`nGet the newest build: https://github.com/$Repo/releases/latest (or update the game in its launcher). Playing online needs everyone on the same game version."
}
$want = (Get-Content "$Here\SHA256SUMS" | Where-Object { $_ -match 'melee_source\.exe$' }) -split '\s+' | Select-Object -First 1
$have = (Get-FileHash $New -Algorithm SHA256).Hash.ToLower()
if ($want -ne $have) { Stop-Install "the download is damaged (checksum mismatch); download it again" }
if ((Get-GameVersion $New) -ne $ModVer) { Stop-Install "the modded program is not version $ModVer" }

if (-not (Test-Modded $Exe)) { Copy-Item $Exe (Join-Path $Game "melee_source.release-$Installed.exe") -Force }
Copy-Item $New "$Exe.tmp" -Force
Move-Item "$Exe.tmp" $Exe -Force

New-Item -ItemType Directory -Force -Path $Home_ | Out-Null
Set-Content -Path "$Home_\game.txt" -Value $Game

# Every Pro AI model in the game's own catalog (ProAI\catalog.json), the ones not there yet, each
# checked against the catalog's sha256 before it is put in place. A failure only warns.
$Cat = Join-Path $Game "ProAI\catalog.json"
if (-not $NoProAI -and (Test-Path $Cat)) {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = "SilentlyContinue"
    $models = (Get-Content $Cat -Raw | ConvertFrom-Json).models
    $miss = @($models | Where-Object { -not (Test-Path (Join-Path $Game "ProAI\$($_.file)")) })
    if ($miss.Count -eq 0) { Say "`nPro AI models: all $($models.Count) already here." }
    else {
      $mb = [math]::Round((($miss | Measure-Object -Property size -Sum).Sum) / 1MB)
      Say "`nPro AI models (the AI takeover's pro AIs): $($miss.Count) to download, $mb MB..."
      $i = 0; $bad = 0
      foreach ($m in $miss) {
        $i++
        $dst = Join-Path $Game "ProAI\$($m.file)"; $tmp = "$dst.part"
        try {
          Invoke-WebRequest -Uri $m.source -OutFile $tmp -UseBasicParsing -UserAgent "vbx-installer"
          if ((Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower() -ne $m.sha256) { throw "checksum mismatch" }
          Move-Item $tmp $dst -Force
          Say "  [$i/$($miss.Count)] $($m.file)"
        } catch {
          $bad++; Say "  [$i/$($miss.Count)] $($m.file) FAILED ($($_.Exception.Message))" Yellow
          Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
      }
      if ($bad) { Say "Some Pro AI models did not download; run install.bat again later." Yellow }
    }
  } catch { Say "Pro AI models: skipped ($($_.Exception.Message))" Yellow }
}
Say "`nInstalled $Tag on game $Installed. Start the game, then F1 > Game > Vooby Mods." Green
Say "To update later (also after the game updates itself), run install.bat again."
Wait-Close
exit 0
