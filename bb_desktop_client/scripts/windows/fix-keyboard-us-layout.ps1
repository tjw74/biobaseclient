#Requires -Version 5.1
<#
  Fix slash/backslash typing on Windows (Parsec / wrong layout / hotkey switch).
  Run: double-click fix-keyboard-us-layout.bat as any user; UAC for admin parts.
#>

$ErrorActionPreference = 'Stop'

function Write-Step([string]$m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

Write-Step "User: $env:USERNAME on $env:COMPUTERNAME"

Write-Step 'Set keyboard to English (United States) only'
try {
  $list = New-WinUserLanguageList -Language en-US
  Set-WinUserLanguageList $list -Force
  Write-Host '  Language list set to en-US.'
} catch {
  Write-Host "  Could not Set-WinUserLanguageList: $_" -ForegroundColor Yellow
}

Write-Step 'Disable accidental layout-switch hotkeys (Alt+Shift, Ctrl+Shift)'
$toggle = 'HKCU:\Keyboard Layout\Toggle'
if (-not (Test-Path $toggle)) { New-Item -Path $toggle -Force | Out-Null }
Set-ItemProperty -Path $toggle -Name 'Layout Hotkey' -Value '3' -Type String -Force
Set-ItemProperty -Path $toggle -Name 'Language Hotkey' -Value '3' -Type String -Force
Set-ItemProperty -Path $toggle -Name 'Hotkey' -Value '3' -Type String -Force
Write-Host '  Layout switch hotkeys disabled (value 3 = none).'

Write-Step 'Force US keyboard preload (00000409)'
$preload = 'HKCU:\Keyboard Layout\Preload'
if (-not (Test-Path $preload)) { New-Item -Path $preload -Force | Out-Null }
Get-ChildItem $preload | Where-Object { $_.PSChildName -ne '1' } | ForEach-Object { Remove-Item $_.PsPath -Force -ErrorAction SilentlyContinue }
Set-ItemProperty -Path $preload -Name '1' -Value '00000409' -Type String -Force
Write-Host '  Preload set to US QWERTY.'

Write-Step 'Check for registry key remaps (non-standard)'
$scanPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
$scan = Get-ItemProperty -Path $scanPath -Name 'Scancode Map' -ErrorAction SilentlyContinue
if ($scan.'Scancode Map') {
  Write-Host '  WARNING: Scancode Map is set — custom key remapping is active.' -ForegroundColor Yellow
  Write-Host '  A reboot is required after removing it. Removing now...'
  Remove-ItemProperty -Path $scanPath -Name 'Scancode Map' -ErrorAction SilentlyContinue
  Write-Host '  Scancode Map removed. Reboot when this script finishes.'
} else {
  Write-Host '  No Scancode Map remapping found.'
}

Write-Step 'Parsec (Windows host) — prefer Windows keyboard layout'
$parsecKey = 'HKCU:\Software\Parsec'
if (Test-Path $parsecKey) {
  # 0 = use host (Windows) layout; helps when Mac client sends wrong scancodes
  Set-ItemProperty -Path $parsecKey -Name 'client_side_keyboard' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
  Write-Host '  Parsec registry updated (client_side_keyboard=0).'
} else {
  Write-Host '  Parsec not configured for this user yet (OK).'
}

Write-Step 'Current layouts loaded in this session'
Get-WinUserLanguageList | Format-Table LanguageTag, InputMethodTips -AutoSize

Write-Host @'

DONE — test in Notepad (do not type a URL):

  Type the key to the left of Right Shift — should be:  /
  Type the key below Backspace — should be:  \

If slash is still a dash:

  ON YOUR MAC (Parsec app, not Windows):
    Settings -> Keyboard -> turn OFF "Use Mac keyboard layout"
    Disconnect and reconnect Parsec.

  Then press Win+Space on Windows until taskbar shows ENG US.

  Reboot Windows if this script removed Scancode Map.

'@ -ForegroundColor Green

Read-Host 'Press Enter to close'
