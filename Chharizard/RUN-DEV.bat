@echo off
title Chharizard - dev launch
cd /d "%~dp0"

where autohotkey.exe >nul 2>&1
if errorlevel 1 (
    where AutoHotkey64.exe >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] AutoHotkey v2 not installed.
        echo Install from https://www.autohotkey.com/
        echo Then re-run this .bat.
        pause & exit /b 1
    )
    set "AHK=AutoHotkey64.exe"
) else (
    set "AHK=autohotkey.exe"
)

echo Launching Chharizard.ahk via %AHK% ...
%AHK% "src\Chharizard.ahk"
