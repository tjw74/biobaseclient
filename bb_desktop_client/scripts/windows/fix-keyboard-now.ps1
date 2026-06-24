#Requires -Version 5.1
$log = Join-Path $env:USERPROFILE 'Desktop\biobase-keyboard-fix.log'
function Log([string]$m) {
  $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  Add-Content -Path $log -Value $line
  Write-Host $line
}

try {
  Log '=== Biobase keyboard fix started ==='
  Log "User: $env:USERNAME  Computer: $env:COMPUTERNAME"

  Log 'Setting en-US keyboard...'
  try {
    Set-WinUserLanguageList (New-WinUserLanguageList -Language en-US) -Force
    Log 'Language list: en-US OK'
  } catch {
    Log "Language list warning: $_"
  }

  $toggle = 'HKCU:\Keyboard Layout\Toggle'
  if (-not (Test-Path $toggle)) { New-Item $toggle -Force | Out-Null }
  'Layout Hotkey', 'Language Hotkey', 'Hotkey' | ForEach-Object {
    Set-ItemProperty $toggle $_ '3' -Force
  }
  $preload = 'HKCU:\Keyboard Layout\Preload'
  if (-not (Test-Path $preload)) { New-Item $preload -Force | Out-Null }
  Set-ItemProperty $preload '1' '00000409' -Force
  Log 'Registry: US layout + hotkeys disabled OK'

  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  Log ("Running as admin: {0}" -f $admin)

  if ($admin) {
    $scanPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
    if (Get-ItemProperty $scanPath -Name 'Scancode Map' -ErrorAction SilentlyContinue) {
      Remove-ItemProperty $scanPath 'Scancode Map' -Force
      Log 'Removed Scancode Map — REBOOT REQUIRED'
      $reboot = $true
    }
  }

  if (Test-Path 'HKCU:\Software\Parsec') {
    $cur = (Get-ItemProperty 'HKCU:\Software\Parsec' -Name 'client_side_keyboard' -ErrorAction SilentlyContinue).client_side_keyboard
    if ($null -eq $cur) { $cur = 0 }
    $next = if ([int]$cur -eq 0) { 1 } else { 0 }
    Set-ItemProperty 'HKCU:\Software\Parsec' 'client_side_keyboard' $next -Type DWord -Force -ErrorAction SilentlyContinue
    Log "Parsec client_side_keyboard toggled $cur -> $next (reconnect Parsec after)"
  }

  Start-Process osk.exe
  Log 'Opened On-Screen Keyboard'

  $msg = @'
Windows part DONE.

1. Notepad -> click / on the ON-SCREEN keyboard.
   If that works, your Mac Parsec keyboard setting is the problem.

2. ON YOUR MAC: Parsec app -> Settings -> Keyboard
   Turn OFF "Use Mac keyboard layout"
   Disconnect and reconnect Parsec.

Log saved on Desktop:
biobase-keyboard-fix.log
'@
  if ($reboot) { $msg += "`n`nREBOOT Windows once." }

  Log 'Finished OK'
  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.MessageBox]::Show($msg, 'Biobase keyboard fix', 'OK', 'Information') | Out-Null
} catch {
  Log "ERROR: $_"
  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.MessageBox]::Show("Failed: $_`n`nSee Desktop\biobase-keyboard-fix.log", 'Biobase keyboard fix', 'OK', 'Error') | Out-Null
  exit 1
}
