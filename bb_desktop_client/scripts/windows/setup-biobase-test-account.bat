@echo off
title Biobase Windows test account setup
echo.
echo Biobase setup — needs Administrator (UAC prompt next).
echo.

net session >nul 2>&1
if %errorLevel% neq 0 (
  echo Requesting Administrator...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-biobase-test-account.ps1"
exit /b %errorLevel%
