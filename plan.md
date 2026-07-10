# AutoDeployFloatingLicense — Project Plan

## Overview
A PowerShell-based automated installer that configures a SpinFire Insight Floating License Manager on a Windows machine. Customers receive a zip file, extract it, and run the script once to go from a bare machine to a fully operational license server.

---

## Deliverables

| File | Status | Description |
|---|---|---|
| `Install-FloatingLicenseServer.ps1` | ✅ Done | Main installer/config script |
| `Run-Setup.bat` | ✅ Done | Double-click launcher (handles execution policy + elevation) |
| `README.txt` | ✅ Done | Customer-facing instructions |

---

## What `SpinFireFloatingLicenseServer.x64.exe` Is
This is the **Floating License Manager (FLM) installer** — NOT SpinFire Insight. It installs:
- `lmgrd.exe` — license manager daemon
- `spinfired.exe` — SpinFire vendor daemon
- `lmtools.exe` -- GUI management utility
- `lmutil.exe` -- command-line utility

Download URL: `https://downloads.spinfire.com/FloatingLicenseServer/SpinFireFloatingLicenseServer.x64.exe`
Confirmed install directory (from test): `C:\Program Files\Tech Soft 3D\Floating License Manager\`

---

## Script Steps & Implementation Status

| # | Step | Status | Notes |
|---|---|---|---|
| 1 | **Admin self-elevation** | ✅ Done | Relaunches with `RunAs` if not already elevated |
| 2 | **Transcript logging** | ✅ Done | Saves `FLM-Install-<timestamp>.log` to Desktop |
| 3 | **Configuration constants** | ✅ Done | Port 27000, service name, filenames, download URL, candidate install paths |
| 4 | **Detect existing FLM** | ✅ Done | Checks Uninstall registry + known `Program Files` paths for `lmgrd.exe` |
| 5 | **Download FLM installer** | ✅ Done | `System.Net.WebClient.DownloadFile()` with error handling |
| 6 | **Silent install** | ✅ Done | Tries `/S`, `/VERYSILENT`, `/quiet` in order; validates exit code |
| 7 | **License file prompt** | ✅ Done | Auto-detects `license.al` + `sfpflv2.dat` in Downloads; prompts if not found |
| 8 | **License file validation** | ✅ Done | Checks for `SERVER` and `VENDOR` lines in `license.al` |
| 9 | **Hostname + MAC check** | ✅ Done | Reads `sfpflv2.dat` line 1 (`SERVER <hostname> <mac>`); checks both against current machine; warns and prompts to continue on mismatch |
| 10 | **Copy license files** | ✅ Done | Copies `license.al` and `sfpflv2.dat` to FLM install directory |
| 11 | **Service registration** | ✅ Done | `lmgrd -install_service`; falls back to `sc.exe create` if needed |
| 12 | **Start service** | ✅ Done | `Start-Service`; polls status; directs to debug log on failure |
| 13 | **Firewall rules** | ✅ Done | Program-based inbound rules for `lmgrd.exe` (SpinFire_LMGRD) and `spinfired.exe` (SpinFire_Vendor); program rules cover all ports — no separate port rules needed; idempotent |
| 14 | **Summary output** | ✅ Done | Prints install path, license files, service status, client connection string |
| 15 | **`Run-Setup.bat` launcher** | ✅ Done | Checks admin, self-elevates via UAC, runs script with execution policy bypass |
| 16 | **`README.txt`** | ✅ Done | Prerequisites, run options (A/B/C), walkthrough, troubleshooting, re-run notes |

---

## Key Design Decisions

- **Port**: 27000 (FlexLM default, hardcoded)
- **SpinFire Insight**: NOT installed on the server machine — only the FLM tools
- **Service startup**: Automatic (starts on boot)
- **License files**: `license.al` + `sfpflv2.dat` (customer-specific, NOT bundled in zip)
- **Idempotency**: Every step checks current state before acting — safe to re-run
- **Error handling**: `try/catch` around every major step with customer-friendly messages
- **Firewall rules**: Added by program path + port; skipped if already exist by name

---

## Client Connection Info (for SpinFire Insight end users)
After setup, clients configure SpinFire Insight to use:
```
27000@<server-hostname>
```

---

## Support Contact
TechSoft3D: spinfiresupport@techsoft3d.com
