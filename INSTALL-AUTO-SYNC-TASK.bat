@echo off
title Chharizard - install auto-sync scheduled task
cd /d "%~dp0"

echo.
echo ============================================================
echo   Install Windows Task Scheduler auto-sync
echo ============================================================
echo.
echo This creates a scheduled task named "Chharizard-AutoSync" that
echo runs AUTO-SYNC.bat every 5 minutes. It uses your existing cached
echo GitHub credentials — no prompts once installed.
echo.
echo Location: %CD%
echo Task cmd: %CD%\AUTO-SYNC.bat
echo Interval: every 5 minutes
echo Runs as:  your current Windows user (not SYSTEM)
echo.
choice /c YN /m "Install this scheduled task"
if errorlevel 2 goto CANCEL

echo.
echo [RUN] schtasks /Create
schtasks /Create /F /SC MINUTE /MO 5 ^
    /TN "Chharizard-AutoSync" ^
    /TR "\"%CD%\AUTO-SYNC.bat\"" ^
    /IT
if errorlevel 1 goto FAIL

echo.
echo ============================================================
echo   SUCCESS
echo ============================================================
echo.
echo Task created. It will run every 5 minutes starting now.
echo.
echo Manual controls:
echo   schtasks /Query /TN Chharizard-AutoSync      -- check status
echo   schtasks /Run   /TN Chharizard-AutoSync      -- run immediately
echo   schtasks /Delete /TN Chharizard-AutoSync /F  -- uninstall
echo.
echo Log:  %CD%\AUTO-SYNC.log
echo.
goto DONE

:FAIL
echo.
echo [ERROR] schtasks command failed. Try running this .bat as Administrator
echo         if the task creation was refused.
goto DONE

:CANCEL
echo.
echo Cancelled. No task installed.

:DONE
echo.
pause
