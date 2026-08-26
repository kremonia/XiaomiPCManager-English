@echo off
rem Turn-key installer: patches the installed Xiaomi PC Manager in place
rem (web UI + native shell strings, tray, clipboard, update dialogs, OSD art).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1" -Language en
if errorlevel 1 pause
