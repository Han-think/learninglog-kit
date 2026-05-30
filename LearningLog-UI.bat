@echo off
chcp 65001 >nul
cd /d "%~dp0workspace"
echo.
echo   Starting LearningLog Web UI...
echo   Browser will open at http://127.0.0.1:8765
echo   Press Ctrl+C in this window to stop.
echo.
learninglog ui
pause
