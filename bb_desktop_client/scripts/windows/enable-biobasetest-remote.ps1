#Requires -Version 5.1
<#
  Run from klingis (Administrator) while on Parsec.
  Enables SSH for the whole PC — biobasetest can log in over SSH.
  Does NOT complete Parsec login for biobasetest (that needs one switch-user session).
#>

$ErrorActionPreference = 'Stop'
$TestUser = 'biobasetest'

function Require-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Run as Administrator.' -ForegroundColor Red
    exit 1
  }
}

Require-Admin

Write-Host ''
Write-Host "Logged in as: $env:USERNAME" -ForegroundColor Cyan
Write-Host ''

if (-not (Get-LocalUser -Name $TestUser -ErrorAction SilentlyContinue)) {
  Write-Host "ERROR: Local user '$TestUser' not found. Create it first in Settings." -ForegroundColor Red
  exit 1
}

$members = Get-LocalGroupMember -Group 'Administrators' | Select-Object -ExpandProperty Name
$inAdmin = $members | Where-Object { $_ -like "*\$TestUser" }
if (-not $inAdmin) {
  Add-LocalGroupMember -Group 'Administrators' -Member $TestUser
  Write-Host "Added $TestUser to Administrators."
} else {
  Write-Host "$TestUser is already an administrator."
}

Write-Host ''
Write-Host '==> OpenSSH Server' -ForegroundColor Cyan
$cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }
if ($cap.State -ne 'Installed') {
  Add-WindowsCapability -Online -Name $cap.Name | Out-Null
}
$cfg = 'C:\ProgramData\ssh\sshd_config'
if (Test-Path $cfg) {
  $text = Get-Content $cfg -Raw
  if ($text -notmatch '(?m)^PasswordAuthentication\s+yes') {
    $text = $text -replace '(?m)^#\s*PasswordAuthentication.*', 'PasswordAuthentication yes'
    $text = $text -replace '(?m)^PasswordAuthentication\s+no', 'PasswordAuthentication yes'
    if ($text -notmatch '(?m)^PasswordAuthentication') { $text += "`nPasswordAuthentication yes`n" }
    Set-Content $cfg $text -Encoding ascii
  }
}
Set-Service sshd -StartupType Automatic
Start-Service sshd
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
} else {
  Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' | Out-Null
}
Write-Host 'SSH listening on port 22.'

Write-Host ''
Write-Host '==> Parsec (manual step still required)' -ForegroundColor Cyan
$parsecExe = @(
  "$env:ProgramFiles\Parsec\parsecd.exe",
  "$env:ProgramFiles\Parsec\parsecd.exe",
  "$env:LOCALAPPDATA\Programs\Parsec\parsec.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($parsecExe) {
  Write-Host "Parsec found on this PC. Host is tied to whichever Windows user is logged in."
  Write-Host "Switch to $TestUser once, open Parsec, sign in — then Parsec remote = that desktop."
} else {
  Write-Host 'Parsec not found — install from https://parsec.app/downloads while on klingis, then repeat on biobasetest account.'
}

Write-Host ''
Write-Host '==> IP addresses' -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '127.*' } |
  ForEach-Object { Write-Host ("  {0}  ({1})" -f $_.IPAddress, $_.InterfaceAlias) }

Write-Host ''
Write-Host @"
DONE (from klingis admin)

  SSH (works now — test from Linux):
    ssh ${TestUser}@<IP-above>
    password: (the one you set for biobasetest)

  Parsec (one-time on biobasetest):
    1. Start menu -> profile icon -> $TestUser -> sign in
    2. Open Parsec -> log in (same Parsec account as klingis is fine)
    3. Leave PC on biobasetest when doing Biobase testing

  Hybrid workflow:
    Parsec into biobasetest desktop for Steam / CS2 / Biobase clicks
    SSH as biobasetest for scripts and installs without fighting the UI

"@ -ForegroundColor Green

Read-Host 'Press Enter to close'
