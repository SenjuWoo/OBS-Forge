@echo off
rem Double-click to run Install.ps1 without changing the PowerShell execution policy.
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" -Menu %*
set "rc=%ERRORLEVEL%"
echo.
pause
exit /b %rc%
