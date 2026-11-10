#!/usr/bin/env bash
# Builds the Linux release zip for one game version from versions/<ver>/vooby.patch.
#
#   bash tools/release-linux.sh 0.9.106 [build number]     (tools/publish.sh passes the number)
#
# Needs: a clone of the Melee Unlocked source (UPSTREAM, it gets a worktree per version), your
# Melee NTSC 1.02 disc (ISO), an installed Melee Unlocked of that version (GAME, for the boot test),
# and the Linux build dependencies of Melee Unlocked. Output: dist/vbx-<ver>-linux.zip.
set -euo pipefail

VER=${1:?give the game version, e.g. 0.9.106}
TAG=v$VER-${2:-0}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$ROOT/tools/local.env" ] && . "$ROOT/tools/local.env"   # DRIVE, WIN, ISO (not in git)
DRIVE=${DRIVE:?set DRIVE in tools/local.env}
UPSTREAM=${UPSTREAM:-$DRIVE/melee-unlocked-blocklist}
GAME=${GAME:-$DRIVE/MeleeUnlocked}
ISO=${ISO:?set ISO in tools/local.env}
TREE=${TREE:-$DRIVE/melee-unlocked-$VER}
JOBS=${JOBS:-12}
PATCH=$ROOT/versions/$VER/vooby.patch
OUT=$ROOT/dist/vbx-$VER-linux
say() { printf '\n== %s\n' "$*"; }
die() { printf '\nSTOPPED: %s\n' "$*" >&2; exit 1; }
[ -f "$PATCH" ] || die "no $PATCH (port the previous version's patch first)"

if [ ! -d "$TREE" ]; then
  say "Source $VER"
  git -C "$UPSTREAM" fetch --quiet origin "refs/tags/v$VER:refs/tags/v$VER" 2>/dev/null || git -C "$UPSTREAM" fetch --quiet origin --tags
  git -C "$UPSTREAM" worktree add -q "$TREE" "v$VER"
  git -C "$TREE" apply --3way "$PATCH" || die "the patch does not apply to $VER; delete $TREE and port it"
  PIN=$(git -C "$TREE" ls-tree HEAD sourceport/extern/melee | awk '{print $3}')
  rm -rf "$TREE/sourceport/extern/melee"
  git clone -q --no-checkout "$UPSTREAM/sourceport/extern/melee" "$TREE/sourceport/extern/melee"
  git -C "$TREE/sourceport/extern/melee" checkout -q "$PIN" 2>/dev/null \
    || { git -C "$TREE/sourceport/extern/melee" fetch -q --depth 1 https://github.com/doldecomp/melee.git "$PIN" \
         && git -C "$TREE/sourceport/extern/melee" checkout -q "$PIN"; }
  (cd "$TREE" && python3 tools/prepare_native_sources.py)
fi

say "Mod tests"
(cd "$TREE/port" && g++-14 -std=c++17 -O1 -DNOMINMAX -Iruntime/host -Iruntime/ppc -Iruntime/hle -Iruntime/gx -Iruntime/abi \
   tests/pad_mods_test.cpp runtime/host/pad_mods.cpp runtime/host/lcancel.cpp -o "$TREE/padmods-test" && "$TREE/padmods-test")

say "Build"
mkdir -p "$ROOT/dist"
(cd "$TREE" && python3 tools/build_linux.py --jobs "$JOBS" --host-only > "$ROOT/dist/build-$VER.log" 2>&1) \
  || { tail -20 "$ROOT/dist/build-$VER.log"; die "build failed"; }

say "Link without the bundled-library path"
# With $ORIGIN/lib the program loads the game's old bundled crypto library next to the system's
# newer one and dies at start (symbol lookup error, launcher code 127).
rm -rf "$OUT"; mkdir -p "$OUT"
LINK=$(cd "$TREE/build-linux" && ninja -t commands port/linux/full/melee_source | tail -1)
LINK=$(printf '%s' "$LINK" | sed -E 's/"?-Wl,-rpath,\\?\$ORIGIN\/lib"?//g')
case "$LINK" in *'-o port/linux/full/melee_source '*) ;; *) die "unexpected link command";; esac
LINK=${LINK/ -o port\/linux\/full\/melee_source / -o $OUT/melee_source }
(cd "$TREE/build-linux" && eval "$LINK")
[ "$(readelf -d "$OUT/melee_source" | grep -ci runpath)" = 0 ] || die "bundled-library path still in"
[ "$(tr -c '[:print:]' '\n' < "$OUT/melee_source" | grep -m1 -xE '0\.[0-9]+\.[0-9]+')" = "$VER" ] || die "not version $VER"

say "Boot test from the game folder"
[ "$(tr -c '[:print:]' '\n' < "$GAME/melee_source" | grep -m1 -xE '0\.[0-9]+\.[0-9]+')" = "$VER" ] || die "installed game is not $VER"
cp "$OUT/melee_source" "$GAME/melee_source.vooby-test"
(cd "$GAME" && timeout 180 ./melee_source.vooby-test --headless --frames 300 --iso "$ISO" --sys-dir ./Sys \
   --settings-path "$ROOT/dist/smoke.ini" --log-file "$ROOT/dist/smoke.log" > "$ROOT/dist/smoke.out" 2>&1) \
  || { rm -f "$GAME/melee_source.vooby-test"; tail -5 "$ROOT/dist/smoke.out"; die "did not boot"; }
rm -f "$GAME/melee_source.vooby-test"

say "Package"
echo "$VER" > "$OUT/VERSION"; echo "$TAG" > "$OUT/TAG"
cp "$ROOT/install/install.sh" "$ROOT/install/update.sh" "$ROOT/install/MODS.md" "$OUT/"
(cd "$OUT" && sha256sum melee_source > SHA256SUMS)
(cd "$ROOT/dist" && rm -f "vbx-$VER-linux.zip" && zip -qr "vbx-$VER-linux.zip" "vbx-$VER-linux")
say "Done: dist/vbx-$VER-linux.zip ($TAG)"
