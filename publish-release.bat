@echo off
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\publish-release.ps1" %*
if errorlevel 1 (
    echo.
    echo [ERROR] Release publishing encountered an error.
    pause
    exit /b 1
)

pause
