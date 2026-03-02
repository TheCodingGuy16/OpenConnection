@echo off
chcp 65001 >nul 2>&1
setlocal

set "DIR=%~dp0"
set "DIR=%DIR:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%\oc_launcher.ps1" -ScriptDir "%DIR%"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  Script exited with error code %ERRORLEVEL%
    pause
)