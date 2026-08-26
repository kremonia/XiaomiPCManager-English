@echo off
setlocal enableextensions
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
set BASE=C:\Program Files\MI\XiaomiPCManager
set VER=
for /f "delims=" %%D in ('dir /b /ad /o-n "%BASE%" 2^>nul') do (
  if not defined VER set VER=%%D
)
if not defined VER (
  echo Could not find the Xiaomi PC Manager install folder under %BASE%.
  pause
  exit /b 1
)
set TARGET=%BASE%\%VER%
echo Found version folder: %TARGET%
echo.
echo Closing Xiaomi PC Manager...
taskkill /f /im XiaomiPcManager.exe >nul 2>&1
taskkill /f /im XiaomiPcHost.exe >nul 2>&1
timeout /t 2 /nobreak >nul

set JS=%TARGET%\dist\static\js\main.js
if exist "%JS%" (
  if not exist "%JS%.zh-CN.bak" copy /y "%JS%" "%JS%.zh-CN.bak" >nul
  copy /y "%~dp0dist\static\js\main.js" "%JS%" >nul
  echo Patched: main.js
) else (
  echo WARNING: main.js not found - version layout changed?
)

set S1=%TARGET%\Search\dist\assets\index.js
set S2=%TARGET%\Search\dist\assets\index-legacy.js
if exist "%S1%" (
  if not exist "%S1%.zh-CN.bak" copy /y "%S1%" "%S1%.zh-CN.bak" >nul
  copy /y "%~dp0Search\dist\assets\index.js" "%S1%" >nul
  echo Patched: Search index.js
)
if exist "%S2%" (
  if not exist "%S2%.zh-CN.bak" copy /y "%S2%" "%S2%.zh-CN.bak" >nul
  copy /y "%~dp0Search\dist\assets\index-legacy.js" "%S2%" >nul
  echo Patched: Search index-legacy.js
)

echo.
echo English UI installed. Starting Xiaomi PC Manager...
start "" "%TARGET%\XiaomiPcManager.exe"
echo.
echo NOTE: some parts of the app (tray menu, driver pages, privacy texts)
echo remain in Chinese. See README.md for details.
pause
