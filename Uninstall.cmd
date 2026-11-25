@echo off
rem Double-click to run Uninstall.ps1 without changing the PowerShell execution policy.
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" %*
set "rc=%ERRORLEVEL%"
echo.
pause
exit /b %rc%
