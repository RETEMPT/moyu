@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build-hap.ps1" %*
exit /b %errorlevel%
