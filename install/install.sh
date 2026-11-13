#!/usr/bin/env bash
# Installer (Linux).
#
#   bash install.sh [game folder]                 install
#   bash install.sh [game folder] --uninstall     put the original program back
#   bash install.sh [game folder] --offline       no online check for a newer build
#   bash install.sh [game folder] --no-proai      skip downloading the Pro AI models
#
# Run it from the unzipped release folder (it sits next to melee_source, VERSION and SHA256SUMS).
# It only replaces the game program; your settings, replays and disc are not touched. The original
# program is kept as melee_source.release-<version> beside it. To update, run it again: it installs
# the newest build online for the installed game version (also after the game updated itself).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
GAME=""; UNINSTALL=0; QUIET=0; OFFLINE=0; PROAI=1
for a in "$@"; do
  case "$a" in
    --uninstall) UNINSTALL=1 ;;
    --quiet) QUIET=1 ;;
    --offline) OFFLINE=1 ;;
    --no-proai) PROAI=0 ;;
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

# builds 1-2 set up a background timer: gone with any run
if [ -f "$UNITS/vbx-update.timer" ]; then
  systemctl --user disable --now vbx-update.timer >/dev/null 2>&1 || true
  rm -f "$UNITS/vbx-update.timer" "$UNITS/vbx-update.service" "$HOME_/update.sh" "$HOME_/update.log"
fi
rm -f "$HOME_/installed.txt"

if [ "$UNINSTALL" = 1 ]; then
  rm -rf "$HOME_"
  BAK="$GAME/melee_source.release-$INSTALLED"
  is_modded "$GAME/melee_source" || { echo "The game program is already the original ($INSTALLED)."; exit 0; }
  [ -f "$BAK" ] || die "no backup $BAK (update the game in its launcher instead: that puts the original back)"
  cp "$BAK" "$GAME/melee_source.tmp" && mv "$GAME/melee_source.tmp" "$GAME/melee_source"
  [ -f "$GAME/melee_game.snapexcl.release-$INSTALLED" ] && cp "$GAME/melee_game.snapexcl.release-$INSTALLED" "$GAME/melee_game.snapexcl"
  echo "Original $INSTALLED program back. Restart the game."
  exit 0
fi

[ -f "$HERE/melee_source" ] && [ -f "$HERE/VERSION" ] || die "run this from the unzipped release folder"
MODVER=$(cat "$HERE/VERSION")
TAG=$(cat "$HERE/TAG" 2>/dev/null || echo "v$MODVER")

# A newer build online for this game version (or any, when this zip is for another version):
# download it and let its own installer do the rest.
if [ $OFFLINE = 0 ] && command -v curl >/dev/null && command -v python3 >/dev/null; then
  if JSON=$(curl -fsSL --max-time 20 -H 'User-Agent: vbx-installer' "https://api.github.com/repos/LucianoCirino/vbx/releases?per_page=40"); then
    read -r RTAG RURL < <(printf '%s' "$JSON" | python3 -I -c '
import json, sys
ver = sys.argv[1]
for r in json.load(sys.stdin):
    if r["draft"] or r["prerelease"] or not r["tag_name"].startswith("v" + ver + "-"): continue
    for a in r["assets"]:
        if a["name"].endswith("-linux.zip"):
            print(r["tag_name"], a["browser_download_url"]); sys.exit()
' "$INSTALLED") || true
    num() { case "$1" in *-[0-9]*) echo "${1##*-}" ;; *) echo 0 ;; esac; }
    if [ -n "${RTAG:-}" ] && { [ "$MODVER" != "$INSTALLED" ] || [ "$(num "$RTAG")" -gt "$(num "$TAG")" ]; }; then
      say "Newer build online: $RTAG. Downloading..."
      TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
      curl -fsSL --max-time 300 -H 'User-Agent: vbx-installer' -o "$TMP/b.zip" "$RURL" && (cd "$TMP" && unzip -q b.zip) \
        || die "the download failed"
      ARGS=("$GAME" --offline); [ $QUIET = 1 ] && ARGS+=(--quiet); [ $PROAI = 0 ] && ARGS+=(--no-proai)
      bash "$(find "$TMP" -name install.sh | head -1)" "${ARGS[@]}"; exit $?
    fi
  else
    say "Could not check for a newer build; installing this one."
  fi
fi
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

# Every Pro AI model in the game's own catalog (ProAI/catalog.json), the ones not there yet, each
# checked against the catalog's sha256 before it is put in place. A failure only warns.
if [ $PROAI = 1 ] && [ -f "$GAME/ProAI/catalog.json" ]; then
  if command -v python3 >/dev/null; then
    say ""; say "Pro AI models (the AI takeover's pro AIs): fetching the missing ones..."
    python3 -I - "$GAME/ProAI" <<'PY' || say "Some Pro AI models did not download; run install.sh again later."
import json, os, sys, hashlib, shutil, tempfile, urllib.request
d = sys.argv[1]
models = json.load(open(os.path.join(d, "catalog.json")))["models"]
miss = [m for m in models if not os.path.exists(os.path.join(d, m["file"]))]
if not miss:
    print("  all %d already here." % len(models)); sys.exit(0)
print("  %d to download, %d MB." % (len(miss), sum(m.get("size", 0) for m in miss) // 1000000), flush=True)
bad = 0
for i, m in enumerate(miss, 1):
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".part"); os.close(fd)
    try:
        req = urllib.request.Request(m["source"], headers={"User-Agent": "vbx-installer"})
        with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
            shutil.copyfileobj(r, f, 1 << 20)
        h = hashlib.sha256()
        with open(tmp, "rb") as f:
            for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
        if h.hexdigest() != m["sha256"]: raise ValueError("checksum mismatch")
        os.replace(tmp, os.path.join(d, m["file"]))
        print("  [%d/%d] %s" % (i, len(miss), m["file"]), flush=True)
    except Exception as e:
        bad += 1; print("  [%d/%d] %s FAILED (%s)" % (i, len(miss), m["file"], e), flush=True)
        if os.path.exists(tmp): os.remove(tmp)
sys.exit(1 if bad else 0)
PY
  else
    say "Pro AI models: python3 not found, skipped."
  fi
fi
say
say "Installed $TAG on game $INSTALLED. Restart the game, then F1 > Game > Vooby Mods."
say "To update later (also after the game updates itself), run install.sh again."
exit 0
