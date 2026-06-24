#Requires -Version 5.1
# Run as Administrator — fixes keyboard for ALL users + welcome screen default.
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Write-Host "`nKeyboard reset for: $env:COMPUTERNAME (admin: $env:USERNAME)`n" -ForegroundColor Cyan

Write-Host '==> System locale / region -> United States' -ForegroundColor Cyan
Set-WinSystemLocale -SystemLocale en-US
Set-Culture -CultureInfo en-US
Set-WinHomeLocation -GeoId 244 | Out-Null

Write-Host '==> Default input method (system) -> US keyboard 0409:00000409' -ForegroundColor Cyan
$inputPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language'
Set-ItemProperty -Path $inputPath -Name 'Default' -Value '0409' -Force
Set-ItemProperty -Path $inputPath -Name 'InstallLanguage' -Value '0409' -Force -ErrorAction SilentlyContinue

Write-Host '==> Current logged-in user -> en-US only' -ForegroundColor Cyan
$list = New-WinUserLanguageList -Language en-US
Set-WinUserLanguageList $list -Force

Write-Host '==> Disable layout-switch hotkeys (all users template via .DEFAULT)' -ForegroundColor Cyan
foreach ($hive in @('HKCU', 'Registry::HKEY_USERS\.DEFAULT')) {
  $toggle = Join-Path $hive 'Keyboard Layout\Toggle'
  if (-not (Test-Path $toggle)) { New-Item -Path $toggle -Force | Out-Null }
  Set-ItemProperty -Path $toggle -Name 'Layout Hotkey' -Value '3' -Force
  Set-ItemProperty -Path $toggle -Name 'Language Hotkey' -Value '3' -Force
  Set-ItemProperty -Path $toggle -Name 'Hotkey' -Value '3' -Force
  $preload = Join-Path $hive 'Keyboard Layout\Preload'
  if (-not (Test-Path $preload)) { New-Item -Path $preload -Force | Out-Null }
  Set-ItemProperty -Path $preload -Name '1' -Value '00000409' -Force
}

Write-Host '==> Remove machine-wide Scancode Map (custom remaps)' -ForegroundColor Cyan
$scanPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
if (Get-ItemProperty -Path $scanPath -Name 'Scancode Map' -ErrorAction SilentlyContinue) {
  Remove-ItemProperty -Path $scanPath -Name 'Scancode Map' -Force
  Write-Host '  Removed. REBOOT required for this part.'
} else {
  Write-Host '  None found.'
}

Write-Host '==> Open On-Screen Keyboard for slash test' -ForegroundColor Cyan
Start-Process osk.exe

Write-Host @'

NEXT — 30 second test (On-Screen Keyboard just opened):

  1. Click the  /  key ON SCREEN with the mouse.
     - If Notepad gets  /  -> Windows is FINE; Parsec or your Mac keyboard is the problem.
     - If Notepad still gets  -  -> reboot, run this script again, tell support.

  2. ON YOUR MAC (Parsec app -> Settings -> Keyboard):
     Turn OFF "Use Mac keyboard layout"
     Disconnect Parsec completely and reconnect.

  3. If still broken ON MAC PARSEC ONLY:
     Turn that setting ON instead (opposite), reconnect.
     One of the two states fixes Mac->Windows slash.

  4. Reboot this Windows PC after this script if it removed Scancode Map.

  5. Plug a real USB keyboard into the Windows PC (if you can) — if slash works
     locally but not via Parsec, it is 100% Parsec Mac client settings.

'@ -ForegroundColor Green

Read-Host 'Press Enter to close'
