@echo off
title Chharizard - move out of Program Files
cd /d "%~dp0"

set "DEST=%USERPROFILE%\Documents\Chharizard"

echo.
echo ============================================================
echo   Chharizard - relocate to Documents
echo ============================================================
echo From: %CD%
echo To:   %DEST%
echo.

if exist "%DEST%\" (
    echo [WARN] Destination already exists: %DEST%
    echo        Existing files will be OVERWRITTEN by new copies.
    echo.
    choice /c YN /m "Continue and overwrite"
    if errorlevel 2 goto CANCEL
)

echo.
echo [RUN] Copying files to %DEST% ...
xcopy "%CD%\*" "%DEST%\" /E /I /H /Y /C
if errorlevel 1 goto COPYFAIL

echo.
echo ============================================================
echo   COPY COMPLETE
echo ============================================================
echo.
echo New location: %DEST%
echo.
echo Next steps:
echo   1. Open File Explorer
echo   2. Navigate to:  %DEST%
echo   3. Double-click  INIT.bat  (from the NEW location)
echo.
echo The old copy at %CD% is still there. You can delete it later.
echo.
goto DONE

:COPYFAIL
echo.
echo [ERROR] Copy failed. xcopy returned error.
goto DONE

:CANCEL
echo.
echo Cancelled. No changes made.
goto DONE

:DONE
echo Press any key to close...
pause >nul
