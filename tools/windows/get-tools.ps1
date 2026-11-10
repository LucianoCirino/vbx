# Portable build tools for the Vooby Mods Windows build. Everything lands in C:\MeleeMods\tools;
# nothing is installed. Delete C:\MeleeMods to remove it all.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-Location C:\MeleeMods\tools
if (-not (Test-Path msvc\setup_x64.bat)) {
  "== Microsoft C++ compiler + Windows SDK (VS 2022 Build Tools packages, about 1 GB)"
  python portable-msvc.py --vs 2022 --accept-license | Select-String -NotMatch "\.\.\. [0-9]+%"
}
if (-not (Test-Path cmake\bin\cmake.exe)) {
  "== CMake 3.31.6"
  Invoke-WebRequest https://github.com/Kitware/CMake/releases/download/v3.31.6/cmake-3.31.6-windows-x86_64.zip -OutFile cmake.zip
  Expand-Archive cmake.zip -DestinationPath . -Force; Rename-Item cmake-3.31.6-windows-x86_64 cmake; Remove-Item cmake.zip
}
if (-not (Test-Path ninja.exe)) {
  "== Ninja 1.12.1"
  Invoke-WebRequest https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-win.zip -OutFile ninja.zip
  Expand-Archive ninja.zip -DestinationPath . -Force; Remove-Item ninja.zip
}
"== Done"
& .\cmake\bin\cmake.exe --version | Select-Object -First 1
& .\ninja.exe --version
Test-Path msvc\setup_x64.bat
