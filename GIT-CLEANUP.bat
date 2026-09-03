@echo off
title Chharizard - git cleanup
cd /d "%~dp0"

echo.
echo ============================================================
echo   Cleaning stale git state left by sandbox commit attempt
echo ============================================================
echo.

if exist ".git\index.lock" (
    echo [RUN] delete .git\index.lock
    del /q ".git\index.lock"
) else (
    echo [SKIP] no index.lock
)

echo [RUN] delete orphan tmp_obj_* files
del /q /s ".git\objects\*\tmp_obj_*" 2>nul
echo.

echo [RUN] git gc --auto
git gc --auto
echo.

echo [RUN] git status
git status --short
echo.

echo Cleanup complete. You can now run PUSH-UPDATE.bat or AUTO-SYNC.bat.
echo.
pause
