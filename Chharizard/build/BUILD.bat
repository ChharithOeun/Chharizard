@echo off
title Chharizard - compile to .exe
cd /d "%~dp0..\src"

REM Find Ahk2Exe (usually installed alongside AutoHotkey)
set "AHK2EXE="
for %%P in (
    "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
    "C:\Program Files (x86)\AutoHotkey\Compiler\Ahk2Exe.exe"
    "%LocalAppData%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
) do (
    if exist %%P set "AHK2EXE=%%~P"
)

if "%AHK2EXE%"=="" (
    echo [ERROR] Ahk2Exe.exe not found.
    echo Install AutoHotkey v2 with the compiler option.
    pause & exit /b 1
)

echo Using: %AHK2EXE%
echo.

"%AHK2EXE%" /in "Chharizard.ahk" /out "..\build\Chharizard.exe"
if errorlevel 1 (
    echo [ERROR] Compilation failed.
    pause & exit /b 1
)

echo.
echo === Compiled to ..\build\Chharizard.exe ===
pause
