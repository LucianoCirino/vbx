#!/usr/bin/env bash
# Installer (Linux).
#
#   bash install.sh [game folder]                 install
#   bash install.sh [game folder] --uninstall     put the original program back, auto update off
#   bash install.sh [game folder] --no-auto-update
#
# Run it from the unzipped release folder (it sits next to melee_source, VERSION and SHA256SUMS).
# It only replaces the game program; your settings, replays and disc are not touched. The original
# program is kept as melee_source.release-<version> beside it. It also turns on the background
# updater (update.sh from a systemd user timer every 15 minutes), which installs new builds itself.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
GAME=""; UNINSTALL=0; QUIET=0; AUTO=1
for a in "$@"; do
  case "$a" in
    --uninstall) UNINSTALL=1 ;;
    --quiet) QUIET=1 ;;
    --no-auto-update) AUTO=0 ;;
    *) GAME=$a ;;
  esac
done
HOME_=${XDG_DATA_HOME:-$HOME/.local/share}/vbx
UNITS=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
say() { [ $QUIET = 1 ] || echo "$@"; }

die() { printf '\nSTOPPED: %s\nNothing was changed.\n' "$*" >&2; exit 1; }
version_of() { tr -c '[:print:]' '\n' < "$1" | grep -m1 -xE '0\.[0-9]+\.[0-9]+' || true; }
is_modded() { [ "$(tr -c '[:print:]' '\n' < "$1" | grep -cx 'padmod_cstick_up_jump')" -gt 0 ]; }

[ -z "$GAME" ] && [ -f "$HOME_/game.txt" ] && GAME=$(cat "$HOME_/game.txt")
if [ -z "$GAME" ]; then
  for c in "$HOME/MeleeUnlocked" "$HOME/Games/MeleeUnlocked" "$HOME/.local/share/MeleeUnlocked"; do
    [ -f "$c/melee_source" ] && { GAME=$c; break; }
  done
fi
if [ -z "$GAME" ] && [ $QUIET = 0 ]; then
  read -r -p "Game folder (the one with melee_source in it): " GAME
fi
GAME=${GAME%/}
[ -f "$GAME/melee_source" ] || die "no melee_source in '$GAME'"

INSTALLED=$(version_of "$GAME/melee_source")
[ -n "$INSTALLED" ] || die "could not read the game's version"

if [ "$UNINSTALL" = 1 ]; then
  systemctl --user disable --now vbx-update.timer >/dev/null 2>&1 || true
  rm -f "$UNITS/vbx-update.timer" "$UNITS/vbx-update.service"; rm -rf "$HOME_"
  BAK="$GAME/melee_source.release-$INSTALLED"
  is_modded "$GAME/melee_source" || { echo "The game program is already the original ($INSTALLED). Auto update off."; exit 0; }
  [ -f "$BAK" ] || die "no backup $BAK (update the game in its launcher instead: that puts the original back)"
  cp "$BAK" "$GAME/melee_source.tmp" && mv "$GAME/melee_source.tmp" "$GAME/melee_source"
  [ -f "$GAME/melee_game.snapexcl.release-$INSTALLED" ] && cp "$GAME/melee_game.snapexcl.release-$INSTALLED" "$GAME/melee_game.snapexcl"
  echo "Original $INSTALLED program back, auto update off. Restart the game."
  exit 0
fi

[ -f "$HERE/melee_source" ] && [ -f "$HERE/VERSION" ] || die "run this from the unzipped release folder"
MODVER=$(cat "$HERE/VERSION")
TAG=$(cat "$HERE/TAG" 2>/dev/null || echo "v$MODVER")
[ "$INSTALLED" = "$MODVER" ] || die "your game is $INSTALLED, this build is for $MODVER.
Update the game in its launcher (or wait for a build for $INSTALLED). Playing online
needs everyone on the same game version."
pgrep -x melee_source >/dev/null 2>&1 && die "the game is running; close it first"
(cd "$HERE" && sha256sum -c --quiet SHA256SUMS) || die "the download is damaged (checksum mismatch); download it again"
[ "$(version_of "$HERE/melee_source")" = "$MODVER" ] || die "the modded program is not version $MODVER"

if ! is_modded "$GAME/melee_source"; then
  cp "$GAME/melee_source" "$GAME/melee_source.release-$INSTALLED"
fi

# Linux release bug (reported upstream): melee_game.snapexcl names the library's size before
# packaging, so the game ignores it and online rollback snapshots carry sound state (desyncs).
# Its size line is set to the installed library's size; the original is kept.
if [ -f "$GAME/melee_game.snapexcl" ] && [ -f "$GAME/melee_game.so" ]; then
  [ -f "$GAME/melee_game.snapexcl.release-$INSTALLED" ] || cp "$GAME/melee_game.snapexcl" "$GAME/melee_game.snapexcl.release-$INSTALLED"
  SIZE=$(stat -c%s "$GAME/melee_game.so")
  sed -i -E "1s/^# dll_size [0-9]+/# dll_size $SIZE/" "$GAME/melee_game.snapexcl"
fi
rm -f "$GAME/melee_gam.snapexcl"

cp "$HERE/melee_source" "$GAME/melee_source.tmp"
chmod +x "$GAME/melee_source.tmp"
mv "$GAME/melee_source.tmp" "$GAME/melee_source"

mkdir -p "$HOME_"
echo "$GAME" > "$HOME_/game.txt"
echo "$TAG $(sha256sum "$GAME/melee_source" | cut -d' ' -f1)" > "$HOME_/installed.txt"
AUTO_ON=0
if [ $AUTO = 1 ] && [ -f "$HERE/update.sh" ] && command -v systemctl >/dev/null 2>&1; then
  cp "$HERE/update.sh" "$HOME_/update.sh"
  mkdir -p "$UNITS"
  printf '[Unit]\nDescription=Keeps the game control mods up to date\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/env bash %s/update.sh\n' "$HOME_" > "$UNITS/vbx-update.service"
  printf '[Unit]\nDescription=Check for new game control mod builds\n\n[Timer]\nOnBootSec=2min\nOnUnitActiveSec=15min\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' > "$UNITS/vbx-update.timer"
  systemctl --user daemon-reload >/dev/null 2>&1 && systemctl --user enable --now vbx-update.timer >/dev/null 2>&1 && AUTO_ON=1
fi
say
say "Installed $TAG on game $INSTALLED. Restart the game, then F1 > Game > Vooby Mods."
[ $AUTO_ON = 1 ] && say "Auto update is on: new builds install by themselves (every 15 minutes, never while the game is open)."
exit 0
