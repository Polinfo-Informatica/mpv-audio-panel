@echo off
powershell.exe -NoProfile -File "%~dp0Restore.ps1" %*
if errorlevel 1 exit /b 1
pause
