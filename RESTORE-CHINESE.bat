@echo off
rem Restores the original Chinese files from the backups.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Restore.ps1"
if errorlevel 1 pause
