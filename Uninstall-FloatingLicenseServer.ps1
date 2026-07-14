#Requires -Version 5.1
<#
.SYNOPSIS
    Removes the SpinFire Insight Floating License Manager and all configuration
    applied by Install-FloatingLicenseServer.ps1.

.DESCRIPTION
    This script reverses everything the installer configures:
      1. Stops and kills lmgrd.exe / spinfired.exe processes.
      2. Stops and deletes the "SpinFire License Server" Windows Service.
      3. Removes SpinFire inbound Windows Firewall rules.
      4. Removes the SpinFire service entry from the lmtools (FLEXlm) registry.
      5. Removes license and log files from the FLM install directory.
      6. Uninstalls the SpinFire Floating License Manager software.

    Must be run as Administrator (the script will self-elevate if needed).
    A full log is saved to the script folder as FLM-Uninstall-<timestamp>.log.

.NOTES
    SpinFire Insight Floating License Manager
    TechSoft3D Support: spinfiresupport@techsoft3d.com
#>

# -- SELF-ELEVATION -------------------------------------------------------------
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($PSCommandPath) {
        Write-Host "`n[!] Requesting Administrator privileges - please approve the UAC prompt.`n" -ForegroundColor Yellow
        Start-Process powershell.exe `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`"" `
            -Verb RunAs
    } else {
        Write-Host "[X] This script must be run as Administrator." -ForegroundColor Red
        Read-Host 'Press Enter to exit'
    }
    exit
}

# -- TRANSCRIPT / LOGGING -------------------------------------------------------
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile   = "$PSScriptRoot\FLM-Uninstall-$timestamp.log"
try { Start-Transcript -Path $logFile -Append | Out-Null } catch {
    $logFile = "$env:TEMP\FLM-Uninstall-$timestamp.log"
    try { Start-Transcript -Path $logFile -Append | Out-Null } catch {}
}

# -- GLOBAL ERROR TRAP ----------------------------------------------------------
trap {
    Write-Host "`n`n  !! UNEXPECTED ERROR !!" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  At: $($_.InvocationInfo.PositionMessage)" -ForegroundColor Red
    Write-Host "`n  Full log saved to: $logFile" -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch {}
    Read-Host "`n  Press Enter to close"
    break
}

# -- CONFIGURATION --------------------------------------------------------------
$FLM_SERVICE_NAME = 'SpinFire License Server'
$FLM_INSTALL_DIR  = 'C:\Program Files\Tech Soft 3D\Floating License Manager'
$FLM_PRODUCT_NAME = 'SpinFire Floating License Server'

# -- HELPER FUNCTIONS -----------------------------------------------------------
function Write-Step { param([string]$Msg) Write-Host "`n[>] $Msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!] $Msg"  -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "    [X] $Msg"  -ForegroundColor Red }

# -- BANNER ---------------------------------------------------------------------
Clear-Host
Write-Host ''
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host '    SpinFire Insight - Floating License Manager Removal'    -ForegroundColor Cyan
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host "  Uninstall log will be saved to: $logFile" -ForegroundColor DarkGray
Write-Host ''
Write-Host '  This will remove:' -ForegroundColor White
Write-Host "    - '$FLM_SERVICE_NAME' Windows Service" -ForegroundColor White
Write-Host '    - SpinFire inbound firewall rules' -ForegroundColor White
Write-Host '    - SpinFire lmtools registry entry' -ForegroundColor White
Write-Host '    - License and log files from the FLM install directory' -ForegroundColor White
Write-Host '    - SpinFire Floating License Manager software' -ForegroundColor White
Write-Host ''

$confirm = Read-Host '  Continue? (Y/N) [default: Y]'
if ($confirm -match '^[Nn]') {
    Write-Host "`n  Uninstall cancelled." -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
}

# -- STEP 1: STOP PROCESSES -----------------------------------------------------
Write-Step 'Stopping lmgrd and spinfired processes...'

$stopped = $false
foreach ($procName in @('lmgrd', 'spinfired')) {
    $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($procs) {
        foreach ($p in $procs) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Write-OK "Stopped $procName (PID $($p.Id))."
        }
        $stopped = $true
    }
}
if (-not $stopped) { Write-OK 'No lmgrd or spinfired processes were running.' }
Start-Sleep -Seconds 2

# -- STEP 2: STOP AND REMOVE WINDOWS SERVICE ------------------------------------
Write-Step "Removing Windows Service '$FLM_SERVICE_NAME'..."

$svc = Get-Service -Name $FLM_SERVICE_NAME -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -ne 'Stopped') {
        Stop-Service -Name $FLM_SERVICE_NAME -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    $scResult = sc.exe delete $FLM_SERVICE_NAME 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Service '$FLM_SERVICE_NAME' removed."
    } else {
        Write-Warn "sc.exe returned: $scResult"
        Write-Warn 'Service may already be marked for deletion on next reboot.'
    }
} else {
    Write-OK "Service '$FLM_SERVICE_NAME' was not present."
}

# -- STEP 3: REMOVE FIREWALL RULES ----------------------------------------------
Write-Step 'Removing Windows Firewall rules...'

$ruleNames = @('SpinFire_LMGRD', 'SpinFire_Vendor')
foreach ($rule in $ruleNames) {
    $existing = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
        Write-OK "Removed firewall rule: $rule"
    } else {
        Write-OK "Firewall rule '$rule' was not present."
    }
}

# -- STEP 4: REMOVE LMTOOLS REGISTRY ENTRY --------------------------------------
Write-Step 'Removing lmtools registry entry...'

$lmtoolsRegBase = 'HKLM:\SOFTWARE\FLEXlm License Manager'
$lmtoolsRegPath = "$lmtoolsRegBase\$FLM_SERVICE_NAME"

if (Test-Path $lmtoolsRegPath) {
    Remove-Item $lmtoolsRegPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "Removed registry key: $lmtoolsRegPath"
} else {
    Write-OK 'lmtools registry entry was not present.'
}

# Reset the parent "last active service" pointer only if it still points at SpinFire
$ptr = (Get-ItemProperty $lmtoolsRegBase -Name 'Service' -ErrorAction SilentlyContinue).Service
if ($ptr -eq $FLM_SERVICE_NAME) {
    Remove-ItemProperty $lmtoolsRegBase -Name 'Service' -ErrorAction SilentlyContinue
    Write-OK 'Cleared lmtools active-service pointer.'
}

# -- STEP 5: REMOVE LICENSE AND LOG FILES ---------------------------------------
Write-Step 'Removing license and log files from FLM directory...'

$filesToRemove = @('sfpflv2.dat', 'license.al', 'lmgrd_debug.log')
foreach ($f in $filesToRemove) {
    $p = Join-Path $FLM_INSTALL_DIR $f
    if (Test-Path $p) {
        Remove-Item $p -Force -ErrorAction SilentlyContinue
        Write-OK "Removed: $f"
    }
}

# -- STEP 6: UNINSTALL FLM SOFTWARE --------------------------------------------
Write-Step 'Uninstalling SpinFire Floating License Manager software...'

# Find the uninstall entry dynamically - avoids hardcoding the MSI GUID
$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
$msiGuid = $null
foreach ($root in $uninstallRoots) {
    $entry = Get-ChildItem $root -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
        Where-Object { $_.DisplayName -match [regex]::Escape($FLM_PRODUCT_NAME) } |
        Select-Object -First 1
    if ($entry) {
        # Extract GUID from UninstallString (MsiExec.exe /I{GUID} or /X{GUID})
        if ($entry.UninstallString -match '\{[0-9A-Fa-f\-]{36}\}') {
            $msiGuid = $Matches[0]
        }
        break
    }
}

if ($msiGuid) {
    Write-Host "    Found: $FLM_PRODUCT_NAME (GUID: $msiGuid)" -ForegroundColor DarkGray
    $proc = Start-Process 'MsiExec.exe' -ArgumentList "/x$msiGuid /qn /norestart" -Wait -PassThru
    if ($proc.ExitCode -in @(0, 3010)) {
        Write-OK "Uninstalled successfully (exit code $($proc.ExitCode))."
        if ($proc.ExitCode -eq 3010) {
            Write-Warn 'A reboot is recommended to complete removal.'
        }
    } else {
        Write-Warn "Uninstaller returned exit code $($proc.ExitCode)."
        Write-Warn 'You may need to uninstall manually via Settings > Apps.'
    }
} else {
    Write-OK 'SpinFire Floating License Manager was not found in installed programs.'
}

# -- SUMMARY --------------------------------------------------------------------
Write-Host ''
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host '    Removal Complete - Summary'                              -ForegroundColor Cyan
Write-Host '  ========================================================' -ForegroundColor Cyan

$checks = @(
    @{ Label = 'FLM software removed';      Pass = -not (Test-Path (Join-Path $FLM_INSTALL_DIR 'lmgrd.exe')) }
    @{ Label = 'Windows Service removed';   Pass = $null -eq (Get-Service $FLM_SERVICE_NAME -ErrorAction SilentlyContinue) }
    @{ Label = 'Firewall rules removed';    Pass = (Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'SpinFire_LMGRD|SpinFire_Vendor' }).Count -eq 0 }
    @{ Label = 'lmtools registry removed';  Pass = -not (Test-Path $lmtoolsRegPath) }
)

foreach ($c in $checks) {
    if ($c.Pass) {
        Write-Host "  [OK] $($c.Label)" -ForegroundColor Green
    } else {
        Write-Host "  [!]  $($c.Label) - may need manual attention" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host "  Log saved to: $logFile" -ForegroundColor DarkGray
Write-Host ''
Write-Host '  For support: spinfiresupport@techsoft3d.com' -ForegroundColor Yellow
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host ''

try { Stop-Transcript | Out-Null } catch {}
Read-Host 'Press Enter to close'
