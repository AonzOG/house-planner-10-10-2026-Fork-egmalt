@echo off
setlocal DisableDelayedExpansion
set "HP_SCRIPT=%~dp0HousePlanner-Wizard.ps1"
if not exist "%HP_SCRIPT%" (
  echo HousePlanner-Wizard.ps1 must be beside this installer BAT.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HP_SCRIPT%" -Action Gui
if errorlevel 1 (
  echo Installer could not start. Please check PowerShell and permissions.
  pause
  exit /b 1
)
exit /b 0
