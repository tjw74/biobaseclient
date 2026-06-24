# Windows test machine setup

One-click script for a shared Windows PC: isolated local admin test account + OpenSSH Server.

## Download (Windows test PC)

1. Download both files into the same folder (e.g. Downloads):
   - https://cs2.clarionlab.dev/client/setup/setup-biobase-test-account.bat
   - https://cs2.clarionlab.dev/client/setup/setup-biobase-test-account.ps1
2. Double-click **`setup-biobase-test-account.bat`**
3. Click **Yes** on the UAC (Administrator) prompt
4. Read the summary at the end (IP address, username, password)
5. Sign out → sign in as **`biobasetest`**

Default password: **`BioBase2026`** (change after setup if needed).

## What it does

- Creates local user **`biobasetest`** (no Microsoft email)
- Adds user to **Administrators**
- Installs and starts **OpenSSH Server** on port 22
- Enables **Remote Desktop** on Windows Pro/Enterprise (skipped on Home)

## SSH from Linux

```bash
ssh biobasetest@<windows-lan-ip>
```

SSH is shell-only. For GUI (Steam, CS2, Biobase clicks), use **Parsec** or **RDP** on the test account.

## Republish to download URL

From ClarionCore:

```bash
cp bb_desktop_client/scripts/windows/setup-biobase-test-account.* \
  /home/clearmined/code/prod/cc_caddy/static/biobase-client/setup/
docker exec cc_monitor_caddy caddy reload --config /etc/caddy/Caddyfile
```
