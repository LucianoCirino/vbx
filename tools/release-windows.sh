#!/usr/bin/env bash
# Builds the Windows release zip for one game version on a Windows PC over SSH
# from a source tree prepared here (tools/release-linux.sh makes it; it holds
# the disc-derived translation, so it only ever goes to our own PCs).
#
#   bash tools/release-windows.sh 0.9.107 [build number]
#
# One-time on the Windows PC: C:\MeleeMods\tools (portable MSVC, CMake, Ninja) via
# tools/windows/get-tools.ps1, and C:\MeleeMods\melee.iso. Output: dist/vbx-<ver>-windows.zip.
set -euo pipefail
VER=${1:?give the game version, e.g. 0.9.107}
TAG=v$VER-${2:-0}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$ROOT/tools/local.env" ] && . "$ROOT/tools/local.env"   # DRIVE, WIN, ISO (not in git)
DRIVE=${DRIVE:?set DRIVE in tools/local.env}
TREE=${TREE:-$DRIVE/melee-unlocked-$VER}
WIN=${WIN:?set WIN (user@windows-pc) in tools/local.env}
WORK=$ROOT/work/$VER; mkdir -p "$WORK" "$ROOT/dist"
SSH="ssh -o BatchMode=yes -o LogLevel=ERROR -o ServerAliveInterval=30"
SCP="scp -o BatchMode=yes -o LogLevel=ERROR"
say() { printf '\n== %s\n' "$*"; }
die() { printf '\nSTOPPED: %s\n' "$*" >&2; exit 1; }
[ -d "$TREE/port/generated" ] || die "no prepared tree $TREE (run tools/release-linux.sh $VER first)"

say "Official $VER Windows files (NVIDIA runtime DLLs for the build, game files for the boot test)"
ZIP=$WORK/MeleeUnlocked-$VER-win64.zip
[ -f "$ZIP" ] || gh release download "v$VER" -R hero88go/melee-unlocked -p "MeleeUnlocked-$VER-win64.zip" -D "$WORK"
rm -rf "$WORK/official"; mkdir -p "$WORK/official"
unzip -q -o "$ZIP" "MeleeUnlocked-$VER/sl.*.dll" "MeleeUnlocked-$VER/melee_source.exe" -d "$WORK/official"
mkdir -p "$TREE/port/third_party/streamline/bin/x64"
cp "$WORK/official/MeleeUnlocked-$VER"/sl.*.dll "$TREE/port/third_party/streamline/bin/x64/"
NGX=$ROOT/work/ngx-sdk   # NVIDIA's public DLSS SDK (github.com/NVIDIA/DLSS), for the DLSS 5 helper
if [ ! -f "$NGX/lib/nvsdk_ngx_d.lib" ]; then
  mkdir -p "$NGX/include" "$NGX/lib"
  for f in $(gh api 'repos/NVIDIA/DLSS/git/trees/main?recursive=1' -q '.tree[] | select(.path|test("^include/.*\\.h$")) | .path'); do
    curl -sSfL -o "$NGX/$f" "https://raw.githubusercontent.com/NVIDIA/DLSS/main/$f"; done
  curl -sSfL -o "$NGX/lib/nvsdk_ngx_d.lib" https://raw.githubusercontent.com/NVIDIA/DLSS/main/lib/Windows_x86_64/x64/nvsdk_ngx_d.lib
  head -c 8 "$NGX/lib/nvsdk_ngx_d.lib" | grep -q "!<arch>" || die "the NGX library download is not a library"
fi
mkdir -p "$TREE/port/third_party/ngx"; cp -r "$NGX/include" "$NGX/lib" "$TREE/port/third_party/ngx/"

say "Source to the Windows PC"
tar --exclude-vcs --exclude='build' --exclude='build-*' -czf "$WORK/src.tar.gz" -C "$(dirname "$TREE")" \
    --transform "s|^$(basename "$TREE")|src|" "$(basename "$TREE")"
$SCP "$WORK/src.tar.gz" "$ROOT/tools/windows/build.bat" "$ZIP" "$WIN:C:/MeleeMods/"
$SSH "$WIN" "cd C:\\MeleeMods; Remove-Item -Recurse -Force src,build,game -ErrorAction SilentlyContinue; tar -xzf src.tar.gz; tar -xf MeleeUnlocked-$VER-win64.zip; Rename-Item MeleeUnlocked-$VER game"

say "Build (a few minutes)"
$SSH "$WIN" 'cmd /c C:\MeleeMods\build.bat configure' | grep -q 'exit 0' || die "configure failed (C:\\MeleeMods\\configure.log)"
$SSH "$WIN" 'Select-String -Path C:\MeleeMods\configure.log -Pattern "incomplete"' | grep -q . && die "built without Streamline/DLSS"
$SSH "$WIN" 'cmd /c C:\MeleeMods\build.bat build' | grep -q 'exit 0' || { $SSH "$WIN" 'Get-Content C:\MeleeMods\build.log -Tail 20'; die "build failed"; }

say "Boot test on Windows"
$SSH "$WIN" 'cd C:\MeleeMods\game; Copy-Item ..\build\port\melee_source.exe .\melee_source.exe -Force; $p = Start-Process .\melee_source.exe -ArgumentList "--headless","--frames","300","--iso","C:\MeleeMods\melee.iso","--sys-dir",".\Sys","--settings-path","C:\MeleeMods\smoke.ini","--log-file","C:\MeleeMods\smoke.log" -PassThru -NoNewWindow -Wait; exit $p.ExitCode' \
  || die "did not boot (C:\\MeleeMods\\smoke.log)"

say "Checks and package"
N=vbx-$VER-windows; O=$ROOT/dist/$N; rm -rf "$O"; mkdir -p "$O"
$SCP "$WIN:C:/MeleeMods/build/port/melee_source.exe" "$O/"
imp() { objdump -p "$1" | awk '/DLL Name:/{print $3}' | sort; }
diff <(imp "$WORK/official/MeleeUnlocked-$VER/melee_source.exe") <(imp "$O/melee_source.exe") || die "DLL imports differ from the official program"
python3 -I -c "import re,sys; t=open(sys.argv[1],'rb').read().decode('latin1'); sys.exit(0 if re.findall(r'(?<=\x00)0\.\d+\.\d+(?=\x00)',t)[:1]==[sys.argv[2]] and 'padmod_cstick_up_jump' in t else 1)" "$O/melee_source.exe" "$VER" \
  || die "not version $VER, or the mods are missing"
echo "$VER" > "$O/VERSION"; echo "$TAG" > "$O/TAG"
cp "$ROOT/install/install.ps1" "$ROOT/install/install.bat" "$ROOT/install/uninstall.bat" "$ROOT/install/update.ps1" "$ROOT/install/MODS.md" "$O/"
(cd "$O" && sha256sum melee_source.exe > SHA256SUMS)
(cd "$ROOT/dist" && rm -f "$N.zip" && zip -qr "$N.zip" "$N")
say "Done: dist/$N.zip ($TAG)"
