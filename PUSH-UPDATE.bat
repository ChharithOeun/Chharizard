@echo off
title Chharizard - push update
cd /d "%~dp0"

echo.
echo ============================================================
echo   Chharizard - push update to GitHub
echo ============================================================
echo Folder: %CD%
echo.

where git >nul 2>&1
if errorlevel 1 goto NOGIT

if not exist ".git\" (
    echo [ERROR] No .git folder here. Run INIT.bat first.
    goto DONE
)

echo [1/4] git status
git status --short
echo.

echo [2/4] git add .
git add .
echo.

echo [3/4] git commit
set /p MSG=Commit message (default: v5.0.1 - modularized Chharbar + banner): 
if "%MSG%"=="" set "MSG=v5.0.1 - modularized Chharbar + banner"
git commit -m "%MSG%"
if errorlevel 1 (
    echo [INFO] Nothing to commit or commit failed. Pushing anyway to be safe.
)
echo.

echo [4/4] git push
git push
if errorlevel 1 goto PUSHFAIL

echo.
echo ============================================================
echo   SUCCESS - https://github.com/ChharithOeun/Chharizard
echo ============================================================
goto DONE

:NOGIT
echo [ERROR] Git not installed. https://git-scm.com/download/win
goto DONE

:PUSHFAIL
echo.
echo [ERROR] Push failed. Common causes:
echo   - Not signed in. When prompted use ChharithOeun + Personal Access Token.
echo   - Remote not set. Run INIT.bat once first.
echo.

:DONE
echo.
echo Press any key to close...
pause >nul
