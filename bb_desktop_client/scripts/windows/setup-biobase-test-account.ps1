#Requires -Version 5.1
<#
.SYNOPSIS
  Creates local Biobase test admin account, enables OpenSSH Server, optional RDP.

  Right-click setup-biobase-test-account.bat -> Run as administrator
  Or double-click the .bat (UAC prompt should appear).
#>

$ErrorActionPreference = 'Stop'

$TestUser = 'biobasetest'
$TestPassword = 'BioBase2026'

function Write-Step([string]$Message) {
  Write-Host ''
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Require-Admin {
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'ERROR: Run this script as Administrator (right-click the .bat file).' -ForegroundColor Red
    exit 1
  }
}

Require-Admin

Write-Step 'Current Windows session'
Write-Host ("  Logged in as: {0}" -f [Environment]::UserName)
Write-Host ("  Computer:     {0}" -f $env:COMPUTERNAME)
Write-Host ("  Edition:      {0}" -f (Get-ComputerInfo).WindowsProductName)

Write-Step "Creating local admin user '$TestUser' (no Microsoft account)"
$existing = Get-LocalUser -Name $TestUser -ErrorAction SilentlyContinue
if ($existing) {
  Write-Host "  User '$TestUser' already exists — updating password and ensuring admin membership."
  $secure = ConvertTo-SecureString $TestPassword -AsPlainText -Force
  Set-LocalUser -Name $TestUser -Password $secure -PasswordNeverExpires:$true
} else {
  $secure = ConvertTo-SecureString $TestPassword -AsPlainText -Force
  New-LocalUser -Name $TestUser -Password $secure -FullName 'Biobase Test' -Description 'Isolated Biobase client testing account' -PasswordNeverExpires | Out-Null
  Write-Host "  Created user '$TestUser'."
}

$adminGroup = Get-LocalGroup -Name 'Administrators'
$members = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
$memberPath = "{0}\{1}" -f $env:COMPUTERNAME, $TestUser
if ($members -notcontains $memberPath -and $members -notcontains $TestUser) {
  Add-LocalGroupMember -Group 'Administrators' -Member $TestUser
  Write-Host '  Added to Administrators group.'
} else {
  Write-Host '  Already in Administrators group.'
}

Write-Step 'Installing OpenSSH Server (if missing)'
$sshCapability = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }
if ($sshCapability.State -ne 'Installed') {
  Add-WindowsCapability -Online -Name $sshCapability.Name | Out-Null
  Write-Host '  OpenSSH Server installed.'
} else {
  Write-Host '  OpenSSH Server already installed.'
}

Write-Step 'Configuring OpenSSH'
$sshdConfig = 'C:\ProgramData\ssh\sshd_config'
if (Test-Path $sshdConfig) {
  $config = Get-Content $sshdConfig -Raw
  $replacements = @{
    '(?m)^#\s*PasswordAuthentication\s+.*$' = 'PasswordAuthentication yes'
    '(?m)^PasswordAuthentication\s+no\s*$'   = 'PasswordAuthentication yes'
    '(?m)^#\s*PubkeyAuthentication\s+.*$'    = 'PubkeyAuthentication yes'
  }
  foreach ($pattern in $replacements.Keys) {
    if ($config -match $pattern) {
      $config = [regex]::Replace($config, $pattern, $replacements[$pattern])
    } elseif ($pattern -like '*PasswordAuthentication*' -and $config -notmatch '(?m)^PasswordAuthentication\s+') {
      $config += "`nPasswordAuthentication yes`n"
    }
  }
  Set-Content -Path $sshdConfig -Value $config -Encoding ascii
  Write-Host '  sshd_config updated (password + pubkey auth enabled).'
}

Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd
Write-Host '  sshd service started and set to Automatic.'

if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
  Write-Host '  Firewall rule added for TCP 22.'
} else {
  Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' | Out-Null
  Write-Host '  Firewall rule for TCP 22 enabled.'
}

Write-Step 'Enabling Remote Desktop (Windows Pro/Enterprise only)'
$edition = (Get-ComputerInfo).WindowsProductName
if ($edition -match 'Pro|Enterprise|Education|Workstation') {
  Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
  Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue | Out-Null
  Write-Host '  Remote Desktop enabled. Connect with mstsc.exe to this PC IP.'
} else {
  Write-Host '  Skipped — Windows Home cannot host incoming RDP; use Parsec or SSH for remote shell.' -ForegroundColor Yellow
}

Write-Step 'Network addresses (for SSH / RDP from another machine)'
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
  ForEach-Object { Write-Host ("  {0}  ({1})" -f $_.IPAddress, $_.InterfaceAlias) }

Write-Step 'DONE — summary'
Write-Host @"

  Test account
    Username: $TestUser
    Password: $TestPassword
    Type:     Local administrator (no Microsoft account)

  Sign in
    Start -> profile icon -> $TestUser
    Do Biobase / Steam / CS2 testing only in that account.

  SSH from your Linux box (same LAN or VPN)
    ssh ${TestUser}@<WINDOWS-IP>

  Notes
    - SSH gives terminal/PowerShell only, not mouse/GUI clicks.
    - For full desktop remote control, use Parsec or RDP (Pro+).
    - Router must forward port 22 (or use Tailscale) for SSH from the internet.
    - Change the password after setup if this machine stays in use.

"@ -ForegroundColor Green

Read-Host 'Press Enter to close this window'
