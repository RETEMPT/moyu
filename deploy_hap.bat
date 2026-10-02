@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\deploy-hap.ps1" %*
exit /b %ERRORLEVEL%
