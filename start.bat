@echo off
setlocal EnableDelayedExpansion
REM ============================================================
REM  Home Nexus - one-shot launcher (Windows)
REM
REM  Usage:
REM    start.bat            bridge in demo mode (simulated radios)
REM    start.bat zigbee     bridge with the Zigbee2MQTT manager
REM    start.bat app        app only (skip the bridge)
REM
REM  Builds anything that is missing, then launches:
REM    1. Nexus Bridge  (own window - the pairing token is printed there)
REM    2. Home Nexus app
REM ============================================================
cd /d "%~dp0"

set MODE=%1
if "%MODE%"=="" set MODE=demo

REM ---------- Nexus Bridge ----------
if /i "%MODE%"=="app" goto :app

where go >nul 2>nul
if errorlevel 1 (
    echo [!] Go not found on PATH - skipping the bridge.
    echo     Install from https://go.dev/dl/ to enable Zigbee/Matter support.
    goto :app
)

if not exist "bridge\nexus-bridge.exe" (
    echo [*] Building Nexus Bridge...
    pushd bridge
    go build -o nexus-bridge.exe .
    if errorlevel 1 (
        popd
        echo [!] Bridge build failed - continuing with the app only.
        goto :app
    )
    popd
)

if /i "%MODE%"=="zigbee" (
    set BRIDGE_FLAGS=-zigbee
) else (
    set BRIDGE_FLAGS=-demo
)

echo [*] Starting Nexus Bridge (%BRIDGE_FLAGS%)...
echo     The PAIRING TOKEN appears in the bridge window - the app will
echo     ask for it during setup (or use Auto-discover).
start "Nexus Bridge" cmd /k "bridge\nexus-bridge.exe %BRIDGE_FLAGS%"

:app
REM ---------- Home Nexus app ----------
set APP_EXE=home_nexus\build\windows\x64\runner\Debug\home_nexus.exe
if exist "home_nexus\build\windows\x64\runner\Release\home_nexus.exe" (
    set APP_EXE=home_nexus\build\windows\x64\runner\Release\home_nexus.exe
)

if not exist "%APP_EXE%" (
    where flutter >nul 2>nul
    if errorlevel 1 (
        echo [!] Flutter not found on PATH and no built app exists.
        echo     Install from https://docs.flutter.dev/get-started/install
        exit /b 1
    )
    echo [*] Building Home Nexus app - first build takes a few minutes...
    pushd home_nexus
    call flutter build windows --debug
    if errorlevel 1 (
        popd
        echo [!] App build failed.
        exit /b 1
    )
    popd
)

echo [*] Starting Home Nexus...
start "" "%APP_EXE%"

echo.
echo ============================================================
echo  Home Nexus is up.
echo    - Add devices:  + button  ^>  Auto-discover
echo    - Bridge setup: enter the pairing token from the bridge window
echo    - Stop:         close both windows
echo ============================================================
endlocal
