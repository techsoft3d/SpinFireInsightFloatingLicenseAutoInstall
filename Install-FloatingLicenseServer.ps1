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

# -- SELF-ELEVATION -------------------------------------------------------------
# Relaunch as Administrator if not already elevated.
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($PSCommandPath) {
        Write-Host "`n[!] Requesting Administrator privileges - please approve the UAC prompt.`n" -ForegroundColor Yellow
        # -NoExit keeps the elevated window open if the script crashes before its own pause
        Start-Process powershell.exe `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`"" `
            -Verb RunAs
    } else {
        Write-Host "[X] This script must be run as Administrator." -ForegroundColor Red
        Write-Host "    Right-click the script and choose 'Run as Administrator', or use Run-Setup.bat." -ForegroundColor Yellow
        Read-Host 'Press Enter to exit'
    }
    exit
}

# -- TRANSCRIPT / LOGGING -------------------------------------------------------
# Write log to the same folder as the script so it's easy to find and share.
# Falls back to $env:TEMP if the script directory isn't writable.
$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile    = "$PSScriptRoot\FLM-Install-$timestamp.log"
try { Start-Transcript -Path $logFile -Append | Out-Null } catch {
    $logFile = "$env:TEMP\FLM-Install-$timestamp.log"
    try { Start-Transcript -Path $logFile -Append | Out-Null } catch {}
}

# -- GLOBAL ERROR TRAP ---------------------------------------------------------
# Catches any unhandled terminating error so the window never vanishes silently.
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
$FLM_DOWNLOAD_URL   = 'https://downloads.spinfire.com/FloatingLicenseServer/SpinFireFloatingLicenseServer.x64.exe'
$FLM_SERVICE_NAME   = 'SpinFire License Server'
$FLM_PORT           = 27000
$FLM_LICENSE_FILE   = 'license.al'
$FLM_DATA_FILE      = 'sfpflv2.dat'
$FLM_LMGRD          = 'lmgrd.exe'
$FLM_VENDOR_DAEMON  = 'spinfired.exe'

# Candidate install paths (checked in order)
$FLM_CANDIDATE_DIRS = @(
    'C:\Program Files\Tech Soft 3D\Floating License Manager',
    'C:\Program Files (x86)\Tech Soft 3D\Floating License Manager',
    'C:\Program Files\TECHSOFT3D\SpinFire Floating License Server',
    'C:\Program Files (x86)\TECHSOFT3D\SpinFire Floating License Server',
    'C:\Program Files\Actify\FLM',
    'C:\Program Files (x86)\Actify\FLM'
)

# -- HELPER FUNCTIONS -----------------------------------------------------------
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
        foreach ($key in (Get-ChildItem $base -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if ($props.DisplayName -like '*SpinFire*License*' -or
                $props.DisplayName -like '*Floating License Manager*' -or
                $props.DisplayName -like '*Tech Soft 3D*' -or
                $props.DisplayName -like '*Actify*FLM*') {
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

    # 3. Last resort: search Program Files for lmgrd.exe
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        $found = Get-ChildItem -Path $root -Filter 'lmgrd.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.DirectoryName }
    }

    return $null
}

# -- BANNER ---------------------------------------------------------------------
Clear-Host
Write-Host ''
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host '    SpinFire Insight - Floating License Manager Setup'      -ForegroundColor Cyan
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host "  Setup log will be saved to: $logFile" -ForegroundColor DarkGray
Write-Host ''

# -- STEP 1: DETECT EXISTING FLM INSTALLATION ----------------------------------
Write-Step 'Checking for existing Floating License Manager installation...'

$flmInstallDir = Find-FLMInstallDir

if ($flmInstallDir) {
    Write-OK "FLM already installed at: $flmInstallDir"
    Write-OK "Skipping download and installation."
} else {
    Write-Warn 'Floating License Manager not found. Proceeding with download and install.'
}

# -- STEP 2: DOWNLOAD AND INSTALL FLM (if needed) ------------------------------
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

# -- STEP 3: LOCATE LICENSE FILES ----------------------------------------------
Write-Step "Locating license files ($FLM_DATA_FILE required, $FLM_LICENSE_FILE optional)..."

$licSourceFile = $null
$datSourceFile = $null

# Auto-detect in Downloads folder
$downloadsDir = "$env:USERPROFILE\Downloads"
$autoLic = Join-Path $downloadsDir $FLM_LICENSE_FILE
$autoDat = Join-Path $downloadsDir $FLM_DATA_FILE

if (Test-Path $autoDat) {
    $foundMsg = "    Found $FLM_DATA_FILE in your Downloads folder:`n      $autoDat"
    if (Test-Path $autoLic) { $foundMsg += "`n      $autoLic (also found)" }
    Write-Host "`n$foundMsg" -ForegroundColor White
    $answer = Read-Host "`n    Use these files? (Y/N) [default: Y]"
    if ($answer -eq '' -or $answer -match '^[Yy]') {
        $datSourceFile = $autoDat
        if (Test-Path $autoLic) { $licSourceFile = $autoLic }
    }
}

# Manual selection loop - only sfpflv2.dat is required
while (-not $datSourceFile) {
    Write-Host ''
    $userInput = Read-Host "    Enter the FOLDER PATH containing $FLM_DATA_FILE`n    (press Enter to use Downloads folder)"

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        $searchDir = $downloadsDir
    } else {
        $searchDir = $userInput.Trim().Trim('"')
    }

    $tryDat = Join-Path $searchDir $FLM_DATA_FILE
    $tryLic = Join-Path $searchDir $FLM_LICENSE_FILE

    if (-not (Test-Path $tryDat)) {
        Write-Warn "$FLM_DATA_FILE not found in '$searchDir'. Please try again."
        continue
    }

    $datSourceFile = $tryDat
    if (Test-Path $tryLic) {
        $licSourceFile = $tryLic
        Write-OK "Found $FLM_LICENSE_FILE as well."
    } else {
        Write-Warn "$FLM_LICENSE_FILE not found in '$searchDir' - it will be skipped (not required for the server)."
    }
}

# Validate sfpflv2.dat content (this is the file with the SERVER line)
$datValidation = Get-Content -Path $datSourceFile -Raw -ErrorAction Stop
if ($datValidation -notmatch '(?im)^SERVER\s+') {
    Write-Fail "$FLM_DATA_FILE does not appear to be a valid license file (missing SERVER line)."
    Write-Host "    Please contact TechSoft3D support: spinfiresupport@techsoft3d.com" -ForegroundColor Yellow
    Read-Host "`nPress Enter to exit"
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

Write-OK "License files validated."

# -- STEP 4: CHECK HOSTNAME AND MAC ADDRESS (from sfpflv2.dat line 1) ----------
# sfpflv2.dat first line format: SERVER <hostname> <macaddress>
# e.g.:  SERVER rh00vmgfps01 0050569321d2
$currentHostname = $env:COMPUTERNAME

$datContent  = Get-Content -Path $datSourceFile -TotalCount 1 -ErrorAction SilentlyContinue
$hostnameOk  = $false
$macOk       = $false
$licHostname = $null
$licMac      = $null

if ($datContent -match '^\s*SERVER\s+(\S+)\s+(\S+)(?:\s+(\d+))?') {
    $licHostname = $Matches[1]
    $licMac      = $Matches[2].ToLower() -replace '[:\-]', ''

    # Override default lmgrd port if specified on SERVER line
    if ($Matches[3]) {
        $FLM_PORT = [int]$Matches[3]
        Write-OK "Detected lmgrd port from license file: $FLM_PORT"
    }

    # Normalize current machine MAC addresses (strip separators, lowercase)
    $currentMacs = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' } |
        ForEach-Object { $_.MacAddress.ToLower() -replace '[:\-]', '' }

    $hostnameOk = ($licHostname -eq 'ANY' -or $licHostname -eq $currentHostname)
    $macOk      = ($currentMacs -contains $licMac)

    Write-Host ''
    Write-Host '    License file binding:' -ForegroundColor White
    Write-Host "      Hostname : $licHostname  $(if ($hostnameOk) { '[OK] matches' } else { '[!!] MISMATCH' })" -ForegroundColor $(if ($hostnameOk) { 'Green' } else { 'Yellow' })
    Write-Host "      MAC addr : $licMac  $(if ($macOk) { '[OK] matches' } else { '[!!] MISMATCH' })" -ForegroundColor $(if ($macOk) { 'Green' } else { 'Yellow' })
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
    Write-Warn "Could not parse SERVER line from $FLM_DATA_FILE - skipping binding check."
}

# Parse VENDOR line for optional fixed port (e.g. "VENDOR spinfired PORT=65000")
$vendorPort = $null
$datAllLines = Get-Content -Path $datSourceFile -ErrorAction SilentlyContinue
foreach ($line in $datAllLines) {
    if ($line -match '^\s*VENDOR\s+\S+\s+.*PORT\s*=\s*(\d+)') {
        $vendorPort = [int]$Matches[1]
        Write-OK "Detected vendor daemon fixed port: $vendorPort"
        break
    }
}

# -- STEP 5: COPY LICENSE FILES ------------------------------------------------
Write-Step 'Copying license files to FLM install directory...'

$destLicFile  = Join-Path $flmInstallDir $FLM_LICENSE_FILE
$destDatFile  = Join-Path $flmInstallDir $FLM_DATA_FILE
$debugLogPath = Join-Path $flmInstallDir 'lmgrd_debug.log'

try {
    Copy-Item -Path $datSourceFile -Destination $destDatFile -Force -ErrorAction Stop
    Write-OK "Copied $FLM_DATA_FILE -> $destDatFile"
    if ($licSourceFile) {
        Copy-Item -Path $licSourceFile -Destination $destLicFile -Force -ErrorAction Stop
        Write-OK "Copied $FLM_LICENSE_FILE -> $destLicFile"
    } else {
        Write-Warn "$FLM_LICENSE_FILE not provided - skipping (not required for license server)."
    }
} catch {
    Write-Fail "Failed to copy license files: $($_.Exception.Message)"
    Read-Host "`nPress Enter to exit"
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

# -- STEP 6: REGISTER LMGRD AS WINDOWS SERVICE --------------------------------
Write-Step "Registering '$FLM_SERVICE_NAME' as a Windows Service..."

$existingSvc = Get-Service -Name $FLM_SERVICE_NAME -ErrorAction SilentlyContinue

if ($existingSvc) {
    Write-Warn "Service '$FLM_SERVICE_NAME' already exists. Removing for re-registration..."
    try {
        if ($existingSvc.Status -ne 'Stopped') {
            Stop-Service -Name $FLM_SERVICE_NAME -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
        & sc.exe delete $FLM_SERVICE_NAME | Out-Null
        Start-Sleep -Seconds 2
        Write-OK "Existing service removed."
    } catch {
        Write-Warn "Could not cleanly remove existing service: $($_.Exception.Message)"
    }
}

# Build the service binary path: quoted exe + arguments
$svcBinPath = "`"$lmgrdExe`" -c `"$destDatFile`" -l `"$debugLogPath`""

try {
    # New-Service passes BinaryPathName directly to SCM - most reliable quoting
    New-Service `
        -Name          $FLM_SERVICE_NAME `
        -BinaryPathName $svcBinPath `
        -DisplayName   $FLM_SERVICE_NAME `
        -StartupType   Automatic `
        -Description   'SpinFire Insight Floating License Manager' `
        -ErrorAction   Stop | Out-Null
    Write-OK "Service '$FLM_SERVICE_NAME' registered."
} catch {
    Write-Warn "New-Service failed: $($_.Exception.Message). Trying sc.exe..."
    try {
        # sc.exe requires the binPath value as a single argument with inner escaped quotes
        $proc = Start-Process 'sc.exe' `
            -ArgumentList "create `"$FLM_SERVICE_NAME`" binPath= `"$svcBinPath`" start= auto DisplayName= `"$FLM_SERVICE_NAME`"" `
            -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($proc.ExitCode -ne 0) { throw "sc.exe exited with code $($proc.ExitCode)" }
        Write-OK "Service registered via sc.exe."
    } catch {
        Write-Fail "Service registration failed: $($_.Exception.Message)"
        Write-Host "`n    Manual alternative:" -ForegroundColor Yellow
        Write-Host "    Open lmtools.exe, go to 'Service/License File' tab, and configure manually." -ForegroundColor Yellow
        Read-Host "`nPress Enter to exit"
        try { Stop-Transcript | Out-Null } catch {}
        exit 1
    }
}

# -- STEP 7: START THE SERVICE -------------------------------------------------
Write-Step "Starting service '$FLM_SERVICE_NAME'..."

# Kill any orphaned lmgrd/spinfired processes before starting - a leftover process
# from a previous run will cause lmgrd to detect a conflict and exit immediately.
foreach ($procName in @('lmgrd', 'spinfired')) {
    $running = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($running) {
        Write-Warn "Found running $procName.exe from a previous session - stopping it..."
        $running | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
        Write-OK "Stopped orphaned $procName.exe."
    }
}
Start-Sleep -Seconds 2

try {
    Start-Service -Name $FLM_SERVICE_NAME -ErrorAction Stop
    Start-Sleep -Seconds 5
    $svcStatus = (Get-Service -Name $FLM_SERVICE_NAME).Status
    if ($svcStatus -eq 'Running') {
        Write-OK "Service is running."
    } else {
        Write-Warn "Service status is '$svcStatus' - it may still be starting."
        Write-Warn "Check the debug log for details: $debugLogPath"
    }
} catch {
    Write-Warn "Could not start service: $($_.Exception.Message)"
    Write-Warn "Check the debug log for details: $debugLogPath"
}

# -- STEP 8: CONFIGURE WINDOWS FIREWALL ----------------------------------------
Write-Step 'Configuring Windows Firewall inbound rules...'

# Rules for program executables
$programRules = @(
    [pscustomobject]@{ Name = 'SpinFire_LMGRD';  Path = $lmgrdExe;     Desc = 'SpinFire lmgrd license daemon' }
    [pscustomobject]@{ Name = 'SpinFire_Vendor'; Path = $spinfiredExe; Desc = 'SpinFire vendor daemon (spinfired)' }
)

foreach ($rule in $programRules) {
    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-OK "Firewall rule '$($rule.Name)' already exists - skipping."
        continue
    }
    if (-not (Test-Path $rule.Path)) {
        Write-Warn "'$($rule.Path)' not found - skipping firewall rule."
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
            -Description  "SpinFire Floating License Manager - TCP port $FLM_PORT" `
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
    Write-OK "Firewall rule '$portRuleName' already exists - skipping."
}

# Vendor daemon port rule (only if PORT= was specified in sfpflv2.dat)
if ($vendorPort) {
    $vendorPortRuleName = "SpinFire_VendorPort$vendorPort"
    if (-not (Get-NetFirewallRule -DisplayName $vendorPortRuleName -ErrorAction SilentlyContinue)) {
        try {
            New-NetFirewallRule `
                -DisplayName  $vendorPortRuleName `
                -Description  "SpinFire vendor daemon (spinfired) - TCP port $vendorPort" `
                -Direction    Inbound `
                -Action       Allow `
                -Protocol     TCP `
                -LocalPort    $vendorPort `
                -Profile      Any `
                -ErrorAction  Stop | Out-Null
            Write-OK "Firewall rule added: $vendorPortRuleName (TCP $vendorPort inbound)"
        } catch {
            Write-Warn "Could not add vendor port rule: $($_.Exception.Message)"
        }
    } else {
        Write-OK "Firewall rule '$vendorPortRuleName' already exists - skipping."
    }
} else {
    Write-Warn "No fixed vendor daemon port found in $FLM_DATA_FILE."
    Write-Host "    spinfired will use a random port - remote clients may be blocked by firewalls." -ForegroundColor Yellow
    Write-Host "    To fix: add 'PORT=<number>' to the VENDOR line in $FLM_DATA_FILE and re-run." -ForegroundColor Yellow
}

# -- SUMMARY --------------------------------------------------------------------
$finalStatus = (Get-Service -Name $FLM_SERVICE_NAME -ErrorAction SilentlyContinue).Status

Write-Host ''
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host '    Setup Complete - Summary'                               -ForegroundColor Cyan
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host "  Install directory  : $flmInstallDir"
Write-Host "  License file       : $destLicFile"
Write-Host "  Data file          : $destDatFile"
Write-Host "  Debug log          : $debugLogPath"
Write-Host "  Service name       : $FLM_SERVICE_NAME"
Write-Host "  Service status     : $finalStatus"
Write-Host "  Port               : $FLM_PORT (TCP)"
if ($vendorPort) {
    Write-Host "  Vendor daemon port : $vendorPort (TCP)"
} else {
    Write-Host "  Vendor daemon port : dynamic (WARNING: may block remote clients)" -ForegroundColor Yellow
}
Write-Host ''
Write-Host "  Clients connect to : $FLM_PORT@$currentHostname"
Write-Host ''
Write-Host '  Firewall rules added:'
Write-Host "    - SpinFire_LMGRD   (lmgrd.exe)"
Write-Host "    - SpinFire_Vendor  (spinfired.exe)"
Write-Host "    - SpinFire_Port$FLM_PORT (TCP $FLM_PORT)"
if ($vendorPort) {
    Write-Host "    - SpinFire_VendorPort$vendorPort (TCP $vendorPort)"
}
Write-Host ''
Write-Host "  Setup log          : $logFile"
Write-Host ''
Write-Host '  For support: spinfiresupport@techsoft3d.com' -ForegroundColor Yellow
Write-Host '  ========================================================' -ForegroundColor Cyan
Write-Host ''

try { Stop-Transcript | Out-Null } catch {}
Read-Host 'Press Enter to close'
