# SpinFire Insight — Floating License Manager Setup

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
4. Both license files saved somewhere accessible on this machine:
   - `license.al`
   - `sfpflv2.dat`

   These are typically emailed from TechSoft3D support. The easiest option is to save them to your **Downloads** folder before running.

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

1. Checks whether the Floating License Manager is already installed. If not, downloads and silently installs it.
2. Asks where your license files are located. Press **Enter** to check your Downloads folder automatically.
3. Validates that the license was issued for this machine by checking the hostname and MAC address in `sfpflv2.dat`. You will be warned (but can continue) if there is a mismatch.
4. Copies the license files to the FLM install directory.
5. Registers `lmgrd` as a Windows Service and starts it.
6. Adds inbound Windows Firewall rules for `lmgrd.exe`, `spinfired.exe`, and TCP port 27000.
7. Displays a summary with your license server connection string.

> A full log is saved to your Desktop as `FLM-Install-YYYYMMDD-HHmmss.log`

---

## Giving Clients the Connection String

After setup completes, configure each SpinFire Insight workstation to use:

```
27000@<this-server-hostname>
```

**Example:** `27000@rh00vmgfps01`

You can find your server hostname in the setup summary, or by running `hostname` in a Command Prompt on this machine.

---

## Troubleshooting

**License server fails to start**
- Check the debug log at:
  `C:\Program Files\TECHSOFT3D\SpinFire Floating License Server\lmgrd_debug.log`
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
