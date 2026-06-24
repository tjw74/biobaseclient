@echo off
title Biobase keyboard fix
echo.
echo Starting keyboard fix...
echo.

if not exist "%~dp0fix-keyboard-now.ps1" (
  msg * "ERROR: fix-keyboard-now.ps1 must be in the same folder as this bat file. Download both from cs2.clarionlab.dev/client"
  exit /b 1
)

net session >nul 2>&1
if %errorLevel% neq 0 (
  echo Asking for Administrator...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-keyboard-now.ps1"
if %errorLevel% neq 0 (
  msg * "Keyboard fix failed. Check Desktop for biobase-keyboard-fix.log"
) else (
  echo Done. Check Desktop for biobase-keyboard-fix.log
)
pause
