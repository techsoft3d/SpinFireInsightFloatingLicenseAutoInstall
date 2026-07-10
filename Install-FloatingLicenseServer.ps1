#Requires -Version 5.1
<#
.SYNOPSIS
    Automated setup for SpinFire Insight Floating License Manager (FLM).

.DESCRIPTION
    This script:
      1. Downloads and installs the SpinFire Floating License Manager if not already present.
      2. Prompts for the customer license files (license.al + sfpflv2.dat).
      3. Copies license files into the FLM install directory.
      4. Registers lmgrd as a Windows Service (auto-start on boot).
      5. Configures Windows Firewall inbound rules for lmgrd.exe and spinfired.exe.
      6. Starts the license server service.

    Must be run as Administrator (the script will self-elevate if needed).
    A full setup log is saved to the Desktop as FLM-Install-<timestamp>.log.

.NOTES
    SpinFire Insight Floating License Manager
    TechSoft3D Support: spinfiresupport@techsoft3d.com
#>

# ── SELF-ELEVATION ─────────────────────────────────────────────────────────────
# Relaunch as Administrator if not already elevated.
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($PSCommandPath) {
        Write-Host "`n[!] Requesting Administrator privileges — please approve the UAC prompt.`n" -ForegroundColor Yellow
        Start-Process powershell.exe `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
            -Verb RunAs
    } else {
        Write-Host "[X] This script must be run as Administrator." -ForegroundColor Red
        Write-Host "    Right-click the script and choose 'Run as Administrator', or use Run-Setup.bat." -ForegroundColor Yellow
        Read-Host 'Press Enter to exit'
    }
    exit
}

# ── TRANSCRIPT / LOGGING ───────────────────────────────────────────────────────
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile   = "$env:USERPROFILE\Desktop\FLM-Install-$timestamp.log"
try { Start-Transcript -Path $logFile -Append | Out-Null } catch {}

# ── CONFIGURATION ──────────────────────────────────────────────────────────────
$FLM_DOWNLOAD_URL   = 'https://downloads.spinfire.com/FloatingLicenseServer/SpinFireFloatingLicenseServer.x64.exe'
$FLM_SERVICE_NAME   = 'SpinFire License Server'
$FLM_PORT           = 27000
$FLM_LICENSE_FILE   = 'license.al'
$FLM_DATA_FILE      = 'sfpflv2.dat'
$FLM_LMGRD          = 'lmgrd.exe'
$FLM_VENDOR_DAEMON  = 'spinfired.exe'

# Candidate install paths (checked in order)
$FLM_CANDIDATE_DIRS = @(
    'C:\Program Files\TECHSOFT3D\SpinFire Floating License Server',
    'C:\Program Files (x86)\TECHSOFT3D\SpinFire Floating License Server',
    'C:\Program Files\Actify\FLM',
    'C:\Program Files (x86)\Actify\FLM'
)

# ── HELPER FUNCTIONS ───────────────────────────────────────────────────────────
function Write-Step  { param([string]$Msg) Write-Host "`n[>] $Msg" -ForegroundColor Cyan }
function Write-OK    { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "    [!] $Msg"  -ForegroundColor Yellow }
function Write-Fail  { param([string]$Msg) Write-Host "    [X] $Msg"  -ForegroundColor Red }

function Find-FLMInstallDir {
    # 1. Check Windows Uninstall registry (most reliable after install)
    $regBases = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($base in $regBases) {
        if (-not (Test-Path $base)) { continue }
        Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($props.DisplayName -like '*SpinFire*License*' -or $props.DisplayName -like '*Actify*FLM*') {
                $loc = $props.InstallLocation
                if ($loc -and (Test-Path (Join-Path $loc $FLM_LMGRD))) {
                    return $loc.TrimEnd('\')
                }
            }
        }
    }

    # 2. Check known candidate directories
    foreach ($dir in $FLM_CANDIDATE_DIRS) {
        if (Test-Path (Join-Path $dir $FLM_LMGRD)) {
            return $dir
        }
    }

    return $null
}

# ── BANNER ─────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host ''
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host '    SpinFire Insight — Floating License Manager Setup'      -ForegroundColor Cyan
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host "  Setup log will be saved to: $logFile" -ForegroundColor DarkGray
Write-Host ''

# ── STEP 1: DETECT EXISTING FLM INSTALLATION ──────────────────────────────────
Write-Step 'Checking for existing Floating License Manager installation...'

$flmInstallDir = Find-FLMInstallDir

if ($flmInstallDir) {
    Write-OK "FLM already installed at: $flmInstallDir"
    Write-OK "Skipping download and installation."
} else {
    Write-Warn 'Floating License Manager not found. Proceeding with download and install.'
}

# ── STEP 2: DOWNLOAD AND INSTALL FLM (if needed) ──────────────────────────────
if (-not $flmInstallDir) {
    Write-Step 'Downloading Floating License Manager installer...'

    $installerPath = Join-Path $env:TEMP 'SpinFireFloatingLicenseServer.x64.exe'

    try {
        Write-Host "    Source: $FLM_DOWNLOAD_URL" -ForegroundColor DarkGray
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($FLM_DOWNLOAD_URL, $installerPath)
        Write-OK "Download complete."
    } catch {
        Write-Fail "Download failed: $($_.Exception.Message)"
        Write-Host "`n    Manual download: $FLM_DOWNLOAD_URL" -ForegroundColor Yellow
        Write-Host "    Download the installer, run it manually, then re-run this script." -ForegroundColor Yellow
        Read-Host "`nPress Enter to exit"
        try { Stop-Transcript | Out-Null } catch {}
        exit 1
    }

    Write-Step 'Installing Floating License Manager (silent)...'

    $installed = $false
    # Try NSIS silent switch (/S), then Inno Setup (/VERYSILENT)
    foreach ($switch in @('/S', '/VERYSILENT', '/quiet')) {
        try {
            Write-Host "    Trying install switch: $switch" -ForegroundColor DarkGray
            $proc = Start-Process -FilePath $installerPath -ArgumentList $switch -Wait -PassThru -ErrorAction Stop
            if ($proc.ExitCode -in @(0, 1, 3010)) {
                Write-OK "Installer completed (exit code $($proc.ExitCode))."
                $installed = $true
                break
            }
            Write-Warn "Switch '$switch' returned exit code $($proc.ExitCode). Trying next..."
        } catch {
            Write-Warn "Switch '$switch' failed: $($_.Exception.Message). Trying next..."
        }
    }

    Remove-Item $installerPath -ErrorAction SilentlyContinue

    if (-not $installed) {
        Write-Fail 'Silent installation failed with all attempted switches.'
        Write-Host "`n    Manual steps:" -ForegroundColor Yellow
        Write-Host "    1. Download: $FLM_DOWNLOAD_URL" -ForegroundColor Yellow
        Write-Host "    2. Run the installer manually." -ForegroundColor Yellow
        Write-Host "    3. Re-run this script to complete configuration." -ForegroundColor Yellow
        Read-Host "`nPress Enter to exit"
        try { Stop-Transcript | Out-Null } catch {}
        exit 1
    }

    # Wait for install to settle, then re-scan
    Start-Sleep -Seconds 3
    $flmInstallDir = Find-FLMInstallDir

    if (-not $flmInstallDir) {
        Write-Fail 'Could not locate FLM install directory after installation.'
        Write-Host "`n    Please enter the install path manually and re-run the script." -ForegroundColor Yellow
        Read-Host "`nPress Enter to exit"
        try { Stop-Transcript | Out-Null } catch {}
        exit 1
    }

    Write-OK "FLM installed at: $flmInstallDir"
}

$lmgrdExe     = Join-Path $flmInstallDir $FLM_LMGRD
$spinfiredExe = Join-Path $flmInstallDir $FLM_VENDOR_DAEMON

if (-not (Test-Path $lmgrdExe)) {
    Write-Fail "lmgrd.exe not found at: $lmgrdExe"
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

# ── STEP 3: LOCATE LICENSE FILES ──────────────────────────────────────────────
Write-Step "Locating license files ($FLM_LICENSE_FILE and $FLM_DATA_FILE)..."

$licSourceFile = $null
$datSourceFile = $null

# Auto-detect in Downloads folder
$downloadsDir = "$env:USERPROFILE\Downloads"
$autoLic = Join-Path $downloadsDir $FLM_LICENSE_FILE
$autoDat = Join-Path $downloadsDir $FLM_DATA_FILE

if ((Test-Path $autoLic) -and (Test-Path $autoDat)) {
    Write-Host "`n    Found both license files in your Downloads folder:" -ForegroundColor White
    Write-Host "      $autoLic" -ForegroundColor White
    Write-Host "      $autoDat" -ForegroundColor White
    $answer = Read-Host "`n    Use these files? (Y/N) [default: Y]"
    if ($answer -eq '' -or $answer -match '^[Yy]') {
        $licSourceFile = $autoLic
        $datSourceFile = $autoDat
    }
}

# Manual selection loop
while (-not ($licSourceFile -and $datSourceFile)) {
    Write-Host ''
    $userInput = Read-Host "    Enter the FOLDER PATH containing $FLM_LICENSE_FILE and $FLM_DATA_FILE`n    (press Enter to use Downloads folder)"

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        $searchDir = $downloadsDir
    } else {
        $searchDir = $userInput.Trim().Trim('"')
    }

    $tryLic = Join-Path $searchDir $FLM_LICENSE_FILE
    $tryDat = Join-Path $searchDir $FLM_DATA_FILE
    $missing = @()

    if (-not (Test-Path $tryLic)) { $missing += $FLM_LICENSE_FILE }
    if (-not (Test-Path $tryDat)) { $missing += $FLM_DATA_FILE }

    if ($missing.Count -gt 0) {
        Write-Warn "The following file(s) were not found in '$searchDir':"
        $missing | ForEach-Object { Write-Warn "  - $_" }
        Write-Host "    Please check that both files are in the folder and try again." -ForegroundColor Yellow
        continue
    }

    $licSourceFile = $tryLic
    $datSourceFile = $tryDat
}

# Validate license.al content
$licContent = Get-Content -Path $licSourceFile -Raw -ErrorAction Stop
if ($licContent -notmatch '(?im)^SERVER\s+') {
    Write-Fail "$FLM_LICENSE_FILE does not appear to be a valid license file (missing SERVER line)."
    Write-Host "    Please contact TechSoft3D support: spinfiresupport@techsoft3d.com" -ForegroundColor Yellow
    Read-Host "`nPress Enter to exit"
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
if ($licContent -notmatch '(?im)^VENDOR\s+') {
    Write-Fail "$FLM_LICENSE_FILE does not appear to be a valid license file (missing VENDOR line)."
    Write-Host "    Please contact TechSoft3D support: spinfiresupport@techsoft3d.com" -ForegroundColor Yellow
    Read-Host "`nPress Enter to exit"
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

Write-OK "License files validated."

# ── STEP 4: CHECK HOSTNAME AND MAC ADDRESS (from sfpflv2.dat line 1) ──────────
# sfpflv2.dat first line format: SERVER <hostname> <macaddress>
# e.g.:  SERVER rh00vmgfps01 0050569321d2
$currentHostname = $env:COMPUTERNAME

$datContent  = Get-Content -Path $datSourceFile -TotalCount 1 -ErrorAction SilentlyContinue
$hostnameOk  = $false
$macOk       = $false
$licHostname = $null
$licMac      = $null

if ($datContent -match '^\s*SERVER\s+(\S+)\s+(\S+)') {
    $licHostname = $Matches[1]
    $licMac      = $Matches[2].ToLower() -replace '[:\-]', ''

    # Normalize current machine MAC addresses (strip separators, lowercase)
    $currentMacs = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' } |
        ForEach-Object { $_.MacAddress.ToLower() -replace '[:\-]', '' }

    $hostnameOk = ($licHostname -eq 'ANY' -or $licHostname -eq $currentHostname)
    $macOk      = ($currentMacs -contains $licMac)

    Write-Host ''
    Write-Host '    License file binding:' -ForegroundColor White
    Write-Host "      Hostname : $licHostname  $(if ($hostnameOk) { '✓ matches' } else { '✗ MISMATCH' })" -ForegroundColor $(if ($hostnameOk) { 'Green' } else { 'Yellow' })
    Write-Host "      MAC addr : $licMac  $(if ($macOk) { '✓ matches' } else { '✗ MISMATCH' })" -ForegroundColor $(if ($macOk) { 'Green' } else { 'Yellow' })
    Write-Host "      This machine: $currentHostname" -ForegroundColor White

    if (-not $hostnameOk -or -not $macOk) {
        Write-Host ''
        Write-Warn 'One or more license bindings do not match this machine.'
        Write-Host '    The license file was generated for a specific hostname and MAC address.' -ForegroundColor Yellow
        Write-Host '    If the license server fails to start, the license file needs to be' -ForegroundColor Yellow
        Write-Host '    re-issued for this machine. Contact TechSoft3D support:' -ForegroundColor Yellow
        Write-Host '    spinfiresupport@techsoft3d.com' -ForegroundColor Yellow
        Write-Host ''
        $proceed = Read-Host '    Continue anyway? (Y/N) [default: Y]'
        if ($proceed -match '^[Nn]') {
            Write-Host '    Setup cancelled. Please request a new license file and re-run.' -ForegroundColor Yellow
            try { Stop-Transcript | Out-Null } catch {}
            exit 0
        }
    }
} else {
    Write-Warn "Could not parse SERVER line from $FLM_DATA_FILE — skipping binding check."
}

# ── STEP 5: COPY LICENSE FILES ────────────────────────────────────────────────
Write-Step 'Copying license files to FLM install directory...'

$destLicFile  = Join-Path $flmInstallDir $FLM_LICENSE_FILE
$destDatFile  = Join-Path $flmInstallDir $FLM_DATA_FILE
$debugLogPath = Join-Path $flmInstallDir 'lmgrd_debug.log'

try {
    Copy-Item -Path $licSourceFile -Destination $destLicFile -Force -ErrorAction Stop
    Copy-Item -Path $datSourceFile -Destination $destDatFile -Force -ErrorAction Stop
    Write-OK "Copied $FLM_LICENSE_FILE  → $destLicFile"
    Write-OK "Copied $FLM_DATA_FILE → $destDatFile"
} catch {
    Write-Fail "Failed to copy license files: $($_.Exception.Message)"
    Read-Host "`nPress Enter to exit"
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

# ── STEP 6: REGISTER LMGRD AS WINDOWS SERVICE ────────────────────────────────
Write-Step "Registering '$FLM_SERVICE_NAME' as a Windows Service..."

$existingSvc = Get-Service -Name $FLM_SERVICE_NAME -ErrorAction SilentlyContinue

if ($existingSvc) {
    Write-Warn "Service '$FLM_SERVICE_NAME' already exists. Removing for re-registration..."
    try {
        if ($existingSvc.Status -ne 'Stopped') {
            Stop-Service -Name $FLM_SERVICE_NAME -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
        # Try lmgrd native removal first
        $removeProc = Start-Process -FilePath $lmgrdExe `
            -ArgumentList "-remove_service -service_name `"$FLM_SERVICE_NAME`"" `
            -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Fall back to sc.exe if service still registered
        if (Get-Service -Name $FLM_SERVICE_NAME -ErrorAction SilentlyContinue) {
            & sc.exe delete $FLM_SERVICE_NAME | Out-Null
            Start-Sleep -Seconds 2
        }
        Write-OK "Existing service removed."
    } catch {
        Write-Warn "Could not cleanly remove existing service: $($_.Exception.Message)"
    }
}

try {
    $installArgs = "-install_service -service_name `"$FLM_SERVICE_NAME`" -c `"$destLicFile`" -l `"$debugLogPath`""
    $installProc = Start-Process -FilePath $lmgrdExe -ArgumentList $installArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
    if ($installProc.ExitCode -ne 0) {
        throw "lmgrd returned exit code $($installProc.ExitCode)"
    }
    Write-OK "Service '$FLM_SERVICE_NAME' registered."
} catch {
    Write-Fail "Service registration via lmgrd failed: $($_.Exception.Message)"
    Write-Host "`n    Attempting fallback: registering service directly with sc.exe..." -ForegroundColor Yellow
    try {
        $binPath = "`"$lmgrdExe`" -c `"$destLicFile`" -l+ `"$debugLogPath`""
        $scResult = & sc.exe create $FLM_SERVICE_NAME binPath= $binPath start= auto DisplayName= $FLM_SERVICE_NAME
        if ($LASTEXITCODE -ne 0) { throw "sc.exe create failed: $scResult" }
        Write-OK "Service registered via sc.exe fallback."
    } catch {
        Write-Fail "Fallback service registration failed: $($_.Exception.Message)"
        Write-Host "`n    Manual alternative:" -ForegroundColor Yellow
        Write-Host "    Open lmtools.exe, go to 'Service/License File' tab, and configure manually." -ForegroundColor Yellow
        Read-Host "`nPress Enter to exit"
        try { Stop-Transcript | Out-Null } catch {}
        exit 1
    }
}

# Ensure auto-start
try {
    Set-Service -Name $FLM_SERVICE_NAME -StartupType Automatic -ErrorAction SilentlyContinue
    Write-OK "Service startup type: Automatic."
} catch {
    Write-Warn "Could not set startup type (service will still run): $($_.Exception.Message)"
}

# ── STEP 7: START THE SERVICE ─────────────────────────────────────────────────
Write-Step "Starting service '$FLM_SERVICE_NAME'..."

try {
    Start-Service -Name $FLM_SERVICE_NAME -ErrorAction Stop
    Start-Sleep -Seconds 5
    $svcStatus = (Get-Service -Name $FLM_SERVICE_NAME).Status
    if ($svcStatus -eq 'Running') {
        Write-OK "Service is running."
    } else {
        Write-Warn "Service status is '$svcStatus' — it may still be starting."
        Write-Warn "Check the debug log for details: $debugLogPath"
    }
} catch {
    Write-Warn "Could not start service: $($_.Exception.Message)"
    Write-Warn "Check the debug log for details: $debugLogPath"
}

# ── STEP 8: CONFIGURE WINDOWS FIREWALL ────────────────────────────────────────
Write-Step 'Configuring Windows Firewall inbound rules...'

# Rules for program executables
$programRules = @(
    [pscustomobject]@{ Name = 'SpinFire_LMGRD';  Path = $lmgrdExe;     Desc = 'SpinFire lmgrd license daemon' }
    [pscustomobject]@{ Name = 'SpinFire_Vendor'; Path = $spinfiredExe; Desc = 'SpinFire vendor daemon (spinfired)' }
)

foreach ($rule in $programRules) {
    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-OK "Firewall rule '$($rule.Name)' already exists — skipping."
        continue
    }
    if (-not (Test-Path $rule.Path)) {
        Write-Warn "'$($rule.Path)' not found — skipping firewall rule."
        continue
    }
    try {
        New-NetFirewallRule `
            -DisplayName  $rule.Name `
            -Description  $rule.Desc `
            -Direction    Inbound `
            -Action       Allow `
            -Program      $rule.Path `
            -Profile      Any `
            -ErrorAction  Stop | Out-Null
        Write-OK "Firewall rule added: $($rule.Name)"
    } catch {
        Write-Warn "Could not add rule '$($rule.Name)': $($_.Exception.Message)"
    }
}

# Port rule
$portRuleName = "SpinFire_Port$FLM_PORT"
if (-not (Get-NetFirewallRule -DisplayName $portRuleName -ErrorAction SilentlyContinue)) {
    try {
        New-NetFirewallRule `
            -DisplayName  $portRuleName `
            -Description  "SpinFire Floating License Manager — TCP port $FLM_PORT" `
            -Direction    Inbound `
            -Action       Allow `
            -Protocol     TCP `
            -LocalPort    $FLM_PORT `
            -Profile      Any `
            -ErrorAction  Stop | Out-Null
        Write-OK "Firewall rule added: $portRuleName (TCP $FLM_PORT inbound)"
    } catch {
        Write-Warn "Could not add port rule: $($_.Exception.Message)"
    }
} else {
    Write-OK "Firewall rule '$portRuleName' already exists — skipping."
}

# ── SUMMARY ────────────────────────────────────────────────────────────────────
$finalStatus = (Get-Service -Name $FLM_SERVICE_NAME -ErrorAction SilentlyContinue).Status

Write-Host ''
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host '    Setup Complete — Summary'                               -ForegroundColor Cyan
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host "  Install directory  : $flmInstallDir"
Write-Host "  License file       : $destLicFile"
Write-Host "  Data file          : $destDatFile"
Write-Host "  Debug log          : $debugLogPath"
Write-Host "  Service name       : $FLM_SERVICE_NAME"
Write-Host "  Service status     : $finalStatus"
Write-Host "  Port               : $FLM_PORT (TCP)"
Write-Host ''
Write-Host "  Clients connect to : $FLM_PORT@$currentHostname"
Write-Host ''
Write-Host '  Firewall rules added:'
Write-Host "    - SpinFire_LMGRD   (lmgrd.exe)"
Write-Host "    - SpinFire_Vendor  (spinfired.exe)"
Write-Host "    - SpinFire_Port$FLM_PORT (TCP $FLM_PORT)"
Write-Host ''
Write-Host "  Full setup log     : $logFile"
Write-Host ''
Write-Host '  For support: spinfiresupport@techsoft3d.com' -ForegroundColor Yellow
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host ''

Read-Host 'Press Enter to close'
try { Stop-Transcript | Out-Null } catch {}
