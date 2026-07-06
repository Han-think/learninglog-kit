@echo off
chcp 65001 >nul
pwsh -ExecutionPolicy Bypass -File "%~dp0dailylog.ps1"
echo.
pause
