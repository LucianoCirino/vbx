@echo off
rem Vooby Mods Windows build: melee_source.exe only. %1 = configure | build
call C:\MeleeMods\tools\msvc\setup_x64.bat
set PATH=C:\MeleeMods\tools\cmake\bin;C:\MeleeMods\tools;%PATH%
cd /d C:\MeleeMods
if "%1"=="configure" cmake -S src -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -DMELEE_BUILD_EXPERIMENTAL_PORT=ON -DMELEE_ENABLE_DLSS5=ON > configure.log 2>&1
if "%1"=="build" cmake --build build --target melee_source --parallel 8 > build.log 2>&1
echo exit %ERRORLEVEL%
