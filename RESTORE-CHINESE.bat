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
echo Restoring original Chinese files in %TARGET%
taskkill /f /im XiaomiPcManager.exe >nul 2>&1
taskkill /f /im XiaomiPcHost.exe >nul 2>&1
timeout /t 2 /nobreak >nul

for %%F in ("%TARGET%\dist\static\js\main.js" "%TARGET%\Search\dist\assets\index.js" "%TARGET%\Search\dist\assets\index-legacy.js") do (
  if exist "%%~F.zh-CN.bak" (
    copy /y "%%~F.zh-CN.bak" "%%~F" >nul
    echo Restored: %%~F
  )
)
echo.
echo Done. Starting Xiaomi PC Manager...
start "" "%TARGET%\XiaomiPcManager.exe"
pause
