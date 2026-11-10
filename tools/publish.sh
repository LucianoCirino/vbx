#!/usr/bin/env bash
# Builds both zips for a game version and publishes them as the next build of that version
# (tag v<ver>-<n>). Friends get it by running install.bat / install.sh again.
#
#   bash tools/publish.sh 0.9.107 "what changed, one line per change"
set -euo pipefail
VER=${1:?game version}; NOTES=${2:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
LAST=$(gh release list -L 100 --json tagName -q '.[].tagName' | sed -n "s/^v$VER-\([0-9]*\)$/\1/p" | sort -n | tail -1)
N=$(( ${LAST:-0} + 1 )); TAG=v$VER-$N
echo "== $TAG"
bash tools/release-linux.sh "$VER" "$N"
bash tools/release-windows.sh "$VER" "$N"
git add -A versions install tools; git commit -qm "$TAG" || true; git push -q
gh release create "$TAG" "dist/vbx-$VER-windows.zip" "dist/vbx-$VER-linux.zip" --title "$VER build $N" --notes "$NOTES" --latest
echo "== published $TAG"
