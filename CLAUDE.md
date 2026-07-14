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
| Silent install failed — wrong installer type | FLM installer is an **InstallShield bootstrapper** (not NSIS). Changed flags from `/S` to `/s /v"/qn"` — `/s` silences the outer launcher, `/v"/qn"` passes no-UI to the inner MSI |
| Silent install failed — double-elevation error | Script self-elevates at startup; using `-Verb RunAs` again on the installer `Start-Process` call caused "operation canceled". Removed `-Verb RunAs` from installer launch |
| lmtools showed no configuration after install | lmtools reads from `HKLM\SOFTWARE\FLEXlm License Manager\<ServiceName>` (separate from Windows Services). Added Step 6b to write the required registry entries |
| lmtools registry used wrong value names | Confirmed correct names by capturing what lmtools v11.19.8.0 writes on "Save Service": `Lmgrd`, `License`, `LMGRD_LOG_FILE`, `Services`, `start`, `cmdlineparams` |
| Script could interfere with other FlexLM apps | Added pre-flight check: if any other service in `FLEXlm License Manager` registry uses a different lmgrd version, script exits immediately with no changes made |

## What Still Needs Testing
- [x] `New-Service` registration succeeds ✅ confirmed working
- [x] Firewall rules added correctly ✅ confirmed working
- [x] Service starts and lmgrd runs correctly ✅ confirmed (lmgrd_debug.log verified)
- [x] `spinfired.exe` launches ✅ confirmed (pid 6764 in debug log)
- [x] SpinFire Insight client can check out a license ✅ confirmed (`27000@SPINFIRETEST`)

## Script Flow Summary
1. Self-elevate to Administrator (UAC)
2. Start transcript log in script directory (falls back to `$env:TEMP`)
3. **Pre-flight check** — scan `HKLM\SOFTWARE\FLEXlm License Manager` for other services; if any use a different lmgrd version than `11.19.8.0`, exit immediately with no changes made
4. Detect FLM at `C:\Program Files\Tech Soft 3D\Floating License Manager\`
5. If not found (or wrong version): download + silently install with `/s /v"/qn"` (InstallShield bootstrapper flags)
6. Locate license files — auto-detect `sfpflv2.dat` (required) and `license.al` (optional) in script folder
7. Validate `sfpflv2.dat` has SERVER line; check hostname + MAC against current machine; warn if mismatch
8. Copy license files to FLM install directory
9. Register `lmgrd.exe` as Windows Service `"SpinFire License Server"` via `New-Service`
10. Register service in lmtools — write subkey to `HKLM\SOFTWARE\FLEXlm License Manager\SpinFire License Server` with correct value names; only updates parent `Service` pointer if nothing else owns it
11. Start service
12. Add firewall inbound rules: `SpinFire_LMGRD` (lmgrd.exe, all ports), `SpinFire_Vendor` (spinfired.exe, all ports)
13. Print summary including client connection string `27000@<hostname>`

## Key Technical Notes
- **Do not use `lmgrd -install_service`** — this version of the FLM does not support it
- **Do not use `ForEach-Object { return }`** inside functions — `return` exits the scriptblock, not the function; use `foreach` loops
- **Do not use non-ASCII characters** in the script — Windows Server may not use UTF-8 as system code page, causing parse failures before line 1 executes
- **Do not use `-Verb RunAs` when already elevated** — the script self-elevates via UAC at startup; using `-Verb RunAs` again on a child `Start-Process` causes "operation canceled" errors (double-elevation)
- **`$env:USERPROFILE`** after UAC elevation may point to a different profile (e.g., built-in Administrator) — use `$PSScriptRoot` or `$env:PUBLIC` for paths that need to be user-accessible
- The service `BinaryPathName` is: `"<lmgrd.exe path>" -c "<sfpflv2.dat path>" -l "<log path>"`
- **lmtools registry value names** (confirmed for v11.19.8.0 by capturing what lmtools writes on Save Service):
  - `Lmgrd` — path to lmgrd.exe
  - `License` — path to license file
  - `LMGRD_LOG_FILE` — path to debug log
  - `Services` = `"1"` — use Windows service mode
  - `start` = `"1"` — start server at power up
  - `cmdlineparams` = `""` — extra lmgrd arguments (leave blank)
  - `Service` = service name (pointer within the subkey itself)
  - Parent key `Service` value = last-active service name (only write if currently blank or already SpinFire)
- **FLM installer type**: InstallShield bootstrapper (`SpinFireFloatingLicenseServer.x64.exe`, description: "Setup Launcher Unicode"). Silent flags: `/s /v"/qn"`. NOT NSIS — `/S` returns exit code 1602
