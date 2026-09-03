@echo off
:: Silent auto-sync — no user prompts. Meant to be called by Windows Task
:: Scheduler every N minutes, or manually if you want a quick "ship it now".
::
:: - Skips if no changes
:: - Uses ISO-like timestamped commit message
:: - Never opens a window when run by scheduler (see /F flag in task install)
:: - Logs to AUTO-SYNC.log
cd /d "%~dp0"

set "LOG=%~dp0AUTO-SYNC.log"

for /f "tokens=1-3 delims=/ " %%a in ("%date%") do set "D=%%c-%%a-%%b"
for /f "tokens=1-2 delims=: " %%a in ("%time%") do set "T=%%a:%%b"
set "TS=%D% %T%"

echo. >> "%LOG%"
echo === %TS% === >> "%LOG%"

git status --porcelain > "%TEMP%\chz_status.txt" 2>&1
for %%A in ("%TEMP%\chz_status.txt") do set "SIZE=%%~zA"
if "%SIZE%"=="0" (
    echo No changes to sync. >> "%LOG%"
    del "%TEMP%\chz_status.txt"
    exit /b 0
)
del "%TEMP%\chz_status.txt"

echo [add]    git add . >> "%LOG%"
git add . >> "%LOG%" 2>&1

echo [commit] auto-sync %TS% >> "%LOG%"
git commit -m "auto-sync %TS%" >> "%LOG%" 2>&1

echo [push]   git push >> "%LOG%"
git push >> "%LOG%" 2>&1

echo Done. >> "%LOG%"
exit /b 0
