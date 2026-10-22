@echo off
powershell.exe -NoProfile -File "%~dp0Install.ps1" -Mode Video %*
if errorlevel 1 exit /b 1
pause
