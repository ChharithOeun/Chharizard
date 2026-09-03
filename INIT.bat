@echo off
title Chharizard - git init + push
cd /d "%~dp0"

echo.
echo ============================================================
echo   Chharizard - git init + first push
echo ============================================================
echo Folder: %CD%
echo.

where git >nul 2>&1
if errorlevel 1 goto NOGIT

if exist ".git\" (
    echo [SKIP] .git already exists
) else (
    echo [RUN] git init
    git init
    if errorlevel 1 goto FAIL
    git branch -M main
)
echo.

echo [RUN] git config user.name Chharbot
git config user.name "Chharbot"
echo [RUN] git config user.email
git config user.email "ChharithOeun@users.noreply.github.com"
echo.

echo [RUN] git add .
git add .
if errorlevel 1 goto FAIL
echo.

echo [RUN] git commit
git commit -m "v5.0.0 - Chharizard monorepo skeleton"
echo.

git remote get-url origin >nul 2>&1
if errorlevel 1 (
    echo [RUN] add remote origin
    git remote add origin https://github.com/ChharithOeun/Chharizard.git
)
echo.

echo ============================================================
echo   Pushing to GitHub
echo ============================================================
echo Username: ChharithOeun
echo Password: paste a Personal Access Token from
echo           https://github.com/settings/tokens
echo           (scope: repo)
echo.
git push -u origin main
if errorlevel 1 goto PUSHFAIL

echo.
echo ============================================================
echo   SUCCESS - https://github.com/ChharithOeun/Chharizard
echo ============================================================
goto DONE

:NOGIT
echo [ERROR] Git not installed. Install from https://git-scm.com/download/win
goto DONE

:FAIL
echo.
echo [ERROR] A git command failed. See messages above.
goto DONE

:PUSHFAIL
echo.
echo [ERROR] Push failed. Common causes:
echo   - Repo not created yet. Create at https://github.com/new
echo     (name: Chharizard, PUBLIC, do not init with README/gitignore/license)
echo   - Wrong credentials. Use a Personal Access Token, not your password.
echo.
goto DONE

:DONE
echo.
echo Press any key to close...
pause >nul
