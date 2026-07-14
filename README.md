# SpinFire Insight — Floating License Manager Setup
## ⚠️ For SpinFire Insight 2026.1.0 and Later Only

> **This setup is NOT backward compatible.**
> It installs Floating License Manager **v11.19.8.0**, which is required for **SpinFire Insight 2026.1.0+**.
> If you are running an earlier version of SpinFire Insight, do **not** use this installer — it will not work with your version. Contact [spinfiresupport@techsoft3d.com](mailto:spinfiresupport@techsoft3d.com) for the appropriate license manager for your version.

---

## What This Does

This script automatically:
- Downloads and installs the SpinFire Floating License Manager (if not already installed)
- Validates and copies your license files to the correct location
- Registers `lmgrd` as a Windows Service that starts automatically on boot
- Opens the required Windows Firewall rules for `lmgrd.exe` and `spinfired.exe`

---

## Prerequisites

1. Windows 10 / Windows Server 2016 or later (64-bit)
2. Administrator access on this machine
3. Internet access *(only needed if the FLM is not yet installed)*
4. `sfpflv2.dat` copied into this folder *(required)*
   - `license.al` is optional — copy it too if provided
   - These are typically emailed from TechSoft3D support. Simply drop them into the same folder as `Run-Setup.bat` before running.

> **Note:** If another application on this machine already uses a **different version** of the FlexLM license manager, the script will stop and tell you what to uninstall before proceeding. It will not make any changes until that is resolved.

---

## How to Run

### Option A — Easiest (recommended)
Double-click **`Run-Setup.bat`** and approve the Administrator (UAC) prompt when it appears.

### Option B — Manual
1. Right-click `Install-FloatingLicenseServer.ps1`
2. Select **Run with PowerShell**
3. Approve the Administrator (UAC) prompt if it appears

### Option C — PowerShell console *(if Options A/B are blocked by policy)*
1. Open PowerShell as Administrator
2. Run: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`
3. Run: `.\Install-FloatingLicenseServer.ps1`

---

## What to Expect

The script walks you through the following automatically:

1. **Pre-flight check** — Scans for other FlexLM license servers already installed on this machine. If a conflicting version is detected, the script exits immediately with no changes made and tells you what to uninstall first.
2. Checks whether the Floating License Manager v11.19.8.0 is already installed. If not, downloads and silently installs it.
3. Looks for your license files (`sfpflv2.dat` required, `license.al` optional) in the setup folder. If not found, the script exits with instructions to place the files there and re-run.
4. Validates that the license was issued for this machine by checking the hostname and MAC address in `sfpflv2.dat`. You will be warned (but can continue) if there is a mismatch.
5. Copies the license files to the FLM install directory.
6. Registers `lmgrd` as a Windows Service (`SpinFire License Server`) that starts automatically on boot.
7. Configures the service in **lmtools** (the FlexLM management GUI) so it appears pre-populated in the Config Services tab.
8. Adds inbound Windows Firewall rules for `lmgrd.exe` and `spinfired.exe`.
9. Displays a summary with your license server connection string.

> A full setup log is saved to the **setup folder** as `FLM-Install-YYYYMMDD-HHmmss.log`

---

## Connecting the client

After setup is complete, navigate to SpinFire Insight on your client machine. Then go to settings -> manage, change server parameters. Enter your servername, mac address, and a port (if one was specified). Click okay, then you should hopefully be greated by a connection successful message. 

---

## Troubleshooting

**Conflicting FlexLM version detected**
- The script found another application on this machine using a different version of the FlexLM license manager.
- Uninstall that application's license server, then re-run this script. No changes were made to your machine.
- Contact [spinfiresupport@techsoft3d.com](mailto:spinfiresupport@techsoft3d.com) if you need help identifying what to uninstall.

**License server fails to start**
- Check the debug log at:
  `C:\Program Files\Tech Soft 3D\Floating License Manager\lmgrd_debug.log`
- Also check the setup log saved to your Desktop.

**Hostname or MAC address mismatch warning**
- The license files were generated for a specific server (hostname + MAC address).
- If the server was renamed or this is a different machine, a new license file must be requested from TechSoft3D.
- Contact: [spinfiresupport@techsoft3d.com](mailto:spinfiresupport@techsoft3d.com)

**Firewall / connectivity issues from client machines**
- Ensure TCP port 27000 is open inbound on this server.
- Confirm no other firewall (e.g., third-party AV) is blocking `lmgrd.exe` or `spinfired.exe`.
- Verify clients can reach this server by hostname (DNS resolution).

**Script blocked by execution policy**
- Use Option C above, or double-click `Run-Setup.bat` which bypasses this automatically.

---

## Re-Running the Script

This script is safe to re-run at any time. It will:
- Skip re-downloading/installing if the FLM is already present
- Remove and re-register the Windows Service with updated settings
- Skip firewall rules that already exist

---

## Support

**TechSoft3D SpinFire Support**
- Email: [spinfiresupport@techsoft3d.com](mailto:spinfiresupport@techsoft3d.com)
- Docs: [Floating License Manager Setup Guide](https://docs.techsoft3d.com/spinfire/insight/setting_up_spinfire/floating_license_manager/)
