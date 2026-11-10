#!/usr/bin/env bash
# Background updater (Linux). install.sh copies this to ~/.local/share/vbx and runs it from a
# systemd user timer every 15 minutes (vbx-update.timer). Same rules as update.ps1: the newest
# release for the installed game version, installed when newer or when the game program is no
# longer the modded one; never while the game is running. Log: ~/.local/share/vbx/update.log
#   bash update.sh --now    run once in the terminal and say what it did
set -uo pipefail
REPO=LucianoCirino/vbx
HOME_=${XDG_DATA_HOME:-$HOME/.local/share}/vbx
LOG=$HOME_/update.log
NOW=0; [ "${1:-}" = "--now" ] && NOW=1
say() { printf '%s  %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; [ $NOW = 1 ] && echo "$*"; return 0; }
quiet() { [ $NOW = 1 ] && say "$*"; return 0; }

GAME=$(cat "$HOME_/game.txt" 2>/dev/null) || { say "not installed"; exit 0; }
[ -f "$GAME/melee_source" ] || { say "no game at $GAME"; exit 0; }
pgrep -x melee_source >/dev/null 2>&1 && { quiet "game open: later"; exit 0; }
VER=$(tr -c '[:print:]' '\n' < "$GAME/melee_source" | grep -m1 -xE '0\.[0-9]+\.[0-9]+')
[ -n "$VER" ] || { say "could not read the game version"; exit 0; }

JSON=$(curl -fsSL --max-time 30 -H 'User-Agent: vbx-updater' "https://api.github.com/repos/$REPO/releases?per_page=40") \
  || { say "error: could not reach GitHub"; exit 1; }
read -r TAG URL < <(printf '%s' "$JSON" | python3 -I -c '
import json, sys
ver = sys.argv[1]
for r in json.load(sys.stdin):
    if r["draft"] or r["prerelease"] or not r["tag_name"].startswith("v" + ver + "-"): continue
    for a in r["assets"]:
        if a["name"].endswith("-linux.zip"):
            print(r["tag_name"], a["browser_download_url"]); sys.exit()
' "$VER")
[ -n "${TAG:-}" ] || { quiet "no build for game $VER yet"; exit 0; }

HASH=$(sha256sum "$GAME/melee_source" | cut -d' ' -f1)
read -r ITAG IHASH < "$HOME_/installed.txt" 2>/dev/null || true
[ "${ITAG:-}" = "$TAG" ] && [ "${IHASH:-}" = "$HASH" ] && { quiet "up to date ($TAG)"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
curl -fsSL --max-time 300 -H 'User-Agent: vbx-updater' -o "$TMP/b.zip" "$URL" || { say "error: download failed"; exit 1; }
(cd "$TMP" && unzip -q b.zip) || { say "error: bad zip"; exit 1; }
INST=$(find "$TMP" -name install.sh | head -1)
[ -n "$INST" ] || { say "error: no install.sh in the zip"; exit 1; }
if OUT=$(bash "$INST" "$GAME" --quiet 2>&1); then say "installed $TAG on game $VER"
else say "error: install failed: $OUT"; exit 1; fi
