# Project Context for AI Agent

## What This Project Does
Automates the installation and configuration of the **SpinFire Insight Floating License Manager (FLM)** on a Windows server. A customer receives a zip file, extracts it, and double-clicks `Run-Setup.bat` — the script handles everything from download through firewall configuration.

## File Structure
```
AutoDeployFloatingLicense/
  Install-FloatingLicenseServer.ps1  # Main setup script
  Run-Setup.bat                      # Launcher (handles UAC + execution policy)
  README.md                          # Customer-facing instructions
  plan.md                            # Implementation plan with status tracking
  .gitignore                         # Excludes license files and logs
  CLAUDE.md                          # This file
```

The following files exist locally for reference but are gitignored (customer-specific):
- `license.al` — Actify XML license wrapper (for SpinFire Insight clients)
- `sfpflv2.dat` — FlexLM license file (what lmgrd actually reads)

## License File Details (Critical)
Two files are distributed per customer:

**`sfpflv2.dat`** — The real FlexLM license file. Format:
```
SERVER <hostname> <MAC-no-separators>
VENDOR spinfired
FEATURE <name> spinfired 1.0 <expiry> <seats> SIGN="..."
...
```
- Line 1 is `SERVER <hostname> <MAC>` — no port means FlexLM defaults to **27000**
- This is the file passed to `lmgrd -c`
- This is the file the script validates and parses for hostname/MAC matching

**`license.al`** — An XML wrapper (Actify format). Contains the same FlexLM content inside `<al:FLEXLMFILE>` tags. Used by SpinFire Insight **client** machines, not by lmgrd directly. Treated as **optional** by the script — it copies it if present but won't fail if missing.

## Confirmed Environment (from testing)
- **OS**: Windows Server 2022 (PSVersion 5.1.20348.4294)
- **FLM install path**: `C:\Program Files\Tech Soft 3D\Floating License Manager\`
- **Vendor daemon**: `spinfired.exe` (not `actifyd.exe` — that was the old version)
- **lmgrd**: Does **NOT** support `-install_service` flag — use `New-Service` PowerShell cmdlet instead
- **FLM installer silent switch**: `/s /v"/qn"` (InstallShield bootstrapper — `/s` silences the outer launcher, `/v"/qn"` passes no-UI flag to the inner MSI)
- **FLM download URL**: `https://downloads.spinfire.com/FloatingLicenseServer/SpinFireFloatingLicenseServer.x64.exe`

## What Has Been Tested and Fixed
| Issue | Fix Applied |
|---|---|
| Script failed to parse on Windows Server (non-UTF8 code page) | All non-ASCII chars replaced with ASCII equivalents |
| FLM install path not found after install | Added `C:\Program Files\Tech Soft 3D\Floating License Manager` as first candidate; broadened registry detection; added recursive fallback search |
| Registry scan returned array instead of string | Replaced `ForEach-Object { return }` with `foreach` loops (PowerShell scoping bug) |
| `license.al` was validated for SERVER line but doesn't have one | Validation moved to `sfpflv2.dat` |
| `lmgrd -install_service` unrecognized flag | Replaced with `New-Service` cmdlet (primary) + `sc.exe` (fallback) |
| Service failed to start ("already running") | Added orphaned process kill step before `Start-Service` — stale lmgrd/spinfired from prior runs conflict with new service start |
| Service passed `license.al` to `-c` flag | Fixed to pass `sfpflv2.dat` |
| Port-specific firewall rules were redundant | Removed `SpinFire_Port27000` and vendor port rules — program-based rules (`lmgrd.exe`, `spinfired.exe`) already allow all ports those executables use |
| Log went to wrong Desktop after UAC elevation | Log now writes to `$PSScriptRoot` (script folder); falls back to `$env:TEMP` |
| Window closed instantly on crash (no log) | Added global `trap {}`, `-NoExit` on RunAs relaunch, `pause` in bat on error |

## What Still Needs Testing
- [x] `New-Service` registration succeeds ✅ confirmed working
- [x] Firewall rules added correctly ✅ confirmed working
- [x] Service starts and lmgrd runs correctly ✅ confirmed (lmgrd_debug.log verified)
- [x] `spinfired.exe` launches ✅ confirmed (pid 6764 in debug log)
- [x] SpinFire Insight client can check out a license ✅ confirmed (`27000@SPINFIRETEST`)

## Script Flow Summary
1. Self-elevate to Administrator (UAC)
2. Start transcript log in script directory
3. Detect FLM at `C:\Program Files\Tech Soft 3D\Floating License Manager\` (registry → known paths → recursive search)
4. If not found: download + silently install with `/S`
5. Prompt for license files — auto-detect `sfpflv2.dat` (+ optional `license.al`) in Downloads folder
6. Validate `sfpflv2.dat` has SERVER line; check hostname + MAC against current machine
7. Copy files to FLM install directory
8. Register `lmgrd.exe` as Windows Service `"SpinFire License Server"` via `New-Service`
9. Start service
10. Add firewall inbound rules: `SpinFire_LMGRD` (lmgrd.exe, all ports), `SpinFire_Vendor` (spinfired.exe, all ports) — program-based rules cover all ports used by each executable, no separate port rules needed
11. Print summary including client connection string `27000@<hostname>`

## Key Technical Notes
- **Do not use `lmgrd -install_service`** — this version of the FLM does not support it
- **Do not use `ForEach-Object { return }`** inside functions — `return` exits the scriptblock, not the function; use `foreach` loops
- **Do not use non-ASCII characters** in the script — Windows Server may not use UTF-8 as system code page, causing parse failures before line 1 executes
- **`$env:USERPROFILE`** after UAC elevation may point to a different profile (e.g., built-in Administrator) — use `$PSScriptRoot` or `$env:PUBLIC` for paths that need to be user-accessible
- The service `BinaryPathName` is: `"<lmgrd.exe path>" -c "<sfpflv2.dat path>" -l "<log path>"`
