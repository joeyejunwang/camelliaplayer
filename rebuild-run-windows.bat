@echo off
setlocal

rem Always run from the project root, even when launched from Explorer.
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Flutter was not found in PATH.
    echo Install Flutter or add its bin directory to PATH, then try again.
    pause
    exit /b 1
)

echo [1/3] Cleaning the previous build...
call flutter clean
if errorlevel 1 goto :failed

echo [2/3] Restoring Flutter packages...
call flutter pub get
if errorlevel 1 goto :failed

echo [3/3] Building and running Camellia Player for Windows...
call flutter run -d windows
if errorlevel 1 goto :failed

exit /b 0

:failed
echo.
echo [ERROR] Rebuild or launch failed.
pause
exit /b 1
