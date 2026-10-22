@echo off
setlocal
echo MPV Audio Panel setup
echo Starting setup. Administrator privileges are not required for your user configuration.
echo.
if not exist "%~dp0Install.ps1" (
    echo ERROR: Install.ps1 was not found. Extract the entire ZIP before running Install.cmd.
    pause
    exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" -Menu %*
set "setup_exit=%errorlevel%"
echo.
if not "%setup_exit%"=="0" echo ERROR: Setup failed with exit code %setup_exit%. Read the message above.
pause
exit /b %setup_exit%
