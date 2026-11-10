# Installer (Windows).
#
#   Double-click install.bat (or: powershell -ExecutionPolicy Bypass -File install.ps1 [-Game <folder>] [-Uninstall] [-NoAutoUpdate])
#
# Run it from the unzipped release folder (next to melee_source.exe, VERSION, TAG and SHA256SUMS).
# It only replaces the game program; settings, replays and the disc are not touched. The original
# program is kept as melee_source.release-<version>.exe beside it. Close the game first.
# It also sets up the background updater (update.ps1, every 15 minutes, this user only), which
# installs new builds by itself, also after the game updates. -NoAutoUpdate leaves it out.
param([string]$Game = "", [switch]$Uninstall, [switch]$NoPause, [switch]$Quiet, [switch]$NoAutoUpdate)
if ($Quiet) { $NoPause = $true }
function Wait-Close { if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null } }
function Say($m, $c = "Gray") { if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Home_ = Join-Path $env:LOCALAPPDATA "vbx"
$Task = "vbx-update"

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
if (-not $Game) {
  foreach ($c in @("$env:LOCALAPPDATA\MeleeUnlocked", "$env:USERPROFILE\MeleeUnlocked", "$env:USERPROFILE\Desktop\MeleeUnlocked", "C:\MeleeUnlocked")) {
    if (Test-Path "$c\melee_source.exe") { $Game = $c; break }
  }
}
if (-not $Game -and -not $Quiet) { $Game = (Read-Host "Game folder (the one with melee_source.exe in it; you can drag it here)").Trim('"', ' ') }
$Game = $Game.TrimEnd('\')
$Exe = Join-Path $Game "melee_source.exe"
if (-not (Test-Path $Exe)) { Stop-Install "no melee_source.exe in '$Game'" }
if (Get-Process melee_source -ErrorAction SilentlyContinue) { Stop-Install "the game is running; close it first" }

$Installed = Get-GameVersion $Exe
if (-not $Installed) { Stop-Install "could not read the game's version" }

if ($Uninstall) {
  Unregister-ScheduledTask -TaskName $Task -Confirm:$false -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force $Home_ -ErrorAction SilentlyContinue
  $Bak = Join-Path $Game "melee_source.release-$Installed.exe"
  if (-not (Test-Modded $Exe)) { Say "The game program is already the original ($Installed). Auto update removed."; Wait-Close; exit 0 }
  if (-not (Test-Path $Bak)) { Stop-Install "no backup $Bak (update the game in its launcher instead: that puts the original back)" }
  Copy-Item $Bak $Exe -Force
  Say "Original $Installed program back, auto update removed. Start the game again." Green
  Wait-Close; exit 0
}

$New = Join-Path $Here "melee_source.exe"
if (-not (Test-Path $New) -or -not (Test-Path "$Here\VERSION")) { Stop-Install "run this from the unzipped release folder" }
$ModVer = (Get-Content "$Here\VERSION" -Raw).Trim()
$Tag = if (Test-Path "$Here\TAG") { (Get-Content "$Here\TAG" -Raw).Trim() } else { "v$ModVer" }
if ($Installed -ne $ModVer) {
  Stop-Install "your game is $Installed, this build is for $ModVer.`nUpdate the game in its launcher (or wait for a build for $Installed). Playing online needs everyone on the same game version."
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
Set-Content -Path "$Home_\installed.txt" -Value "$Tag $have"
$auto = $false
if (-not $NoAutoUpdate -and (Test-Path "$Here\update.ps1")) {
  Copy-Item "$Here\update.ps1" "$Home_\update.ps1" -Force
  try {
    $ps = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Home_\update.ps1`""
    $action = New-ScheduledTaskAction -Execute "conhost.exe" -Argument "--headless $ps"
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 15)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $Task -Action $action -Trigger $trigger -Settings $settings -Description "Keeps the game's control mods up to date" -Force | Out-Null
    $auto = $true
  } catch {
    Say "Auto update could not be set up ($($_.Exception.Message)); install new builds by hand." Yellow
  }
}
Say "`nInstalled $Tag on game $Installed. Start the game, then F1 > Game > Vooby Mods." Green
if ($auto) { Say "Auto update is on: new builds install by themselves (every 15 minutes, never while the game is open)." }
Wait-Close
exit 0
