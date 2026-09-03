@echo off
echo.
echo ================================
echo   Hello from cmd.exe
echo ================================
echo.
echo If you can read this, .bat files work on your system.
echo Current directory: %CD%
echo Script directory:  %~dp0
echo.
echo Checking for git...
where git
if errorlevel 1 (
    echo [X] Git is NOT installed.
    echo     Install: https://git-scm.com/download/win
) else (
    echo [OK] Git is installed.
)
echo.
echo Press any key to close.
pause >nul
