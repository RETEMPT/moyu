@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo       HarmonyOS HAP Build and One-Click Deploy Script
echo ========================================================

set "STUDIO_DIR=E:\devecostudio-windows-26.0.0.821\devecostudio-windows-26.0.0.821\DevEco Studio"
set "PATH=%STUDIO_DIR%\jbr\bin;%STUDIO_DIR%\sdk\default\openharmony\toolchains;%PATH%"
set "DEVECO_SDK_HOME=%STUDIO_DIR%\sdk"
set "HVIGOR_BIN=%STUDIO_DIR%\tools\hvigor\bin\hvigorw.bat"
set "HDC_BIN=%STUDIO_DIR%\sdk\default\openharmony\toolchains\hdc.exe"

set "HAP_PATH=e:\apps\entry\build\default\outputs\default\entry-default-unsigned.hap"
set "BUNDLE_NAME=com.example.myapplication"
set "ABILITY_NAME=EntryAbility"

echo [1/4] Checking connected target devices...
"%HDC_BIN%" list targets
for /f "tokens=*" %%i in ('"%HDC_BIN%" list targets') do (
    set "TARGET_DEV=%%i"
    goto :found_target
)

:found_target
if "%TARGET_DEV%"=="" (
    echo [ERROR] No HarmonyOS device or emulator found. Please start an emulator or connect a device.
    exit /b 1
)
if "%TARGET_DEV%"=="[Empty]" (
    echo [ERROR] No HarmonyOS device or emulator found.
    exit /b 1
)
echo Found target device: %TARGET_DEV%

echo.
echo [2/4] Assembling HAP package with Hvigor...
call "%HVIGOR_BIN%" --stop-daemon
call "%HVIGOR_BIN%" assembleHap --mode module -p module=entry@default -p product=default
if errorlevel 1 (
    echo [ERROR] HAP build failed.
    exit /b 1
)

if not exist "%HAP_PATH%" (
    echo [ERROR] HAP file not found at: %HAP_PATH%
    exit /b 1
)
echo Built HAP package successfully: %HAP_PATH%

echo.
echo [3/4] Installing HAP onto target (%TARGET_DEV%)...
"%HDC_BIN%" -t %TARGET_DEV% install -r "%HAP_PATH%"
if errorlevel 1 (
    echo [ERROR] Installation failed.
    exit /b 1
)
echo HAP installation succeeded!

echo.
echo [4/4] Starting %ABILITY_NAME% (%BUNDLE_NAME%)...
"%HDC_BIN%" -t %TARGET_DEV% shell aa start -a %ABILITY_NAME% -b %BUNDLE_NAME% -m entry
if errorlevel 1 (
    echo [ERROR] Failed to start ability.
    exit /b 1
)

echo.
echo ========================================================
echo [SUCCESS] App deployed and launched successfully on %TARGET_DEV%!
echo ========================================================
