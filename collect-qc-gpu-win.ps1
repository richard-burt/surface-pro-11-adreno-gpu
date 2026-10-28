# collect-qc-gpu-win.ps1
# ---------------------------------------------------------------------------
# STANDALONE collector - runs under Windows 11 (ARM64, Windows PowerShell 5.1
# compatible). Collects every aspect of the Qualcomm graphics stack (Adreno,
# qcdx8380 driver package) for offline analysis on Linux.
# Standalone payload rules honored: no param block, no CLI switches, no
# interactivity; all identity/settings are hardcoded constants below.
# ---------------------------------------------------------------------------
#Requires -Version 5.1

$OutputRoot  = 'C:\QC-GPU-Collect'
$Stamp       = Get-Date -Format 'yyyyMMdd-HHmmss'
$Out         = Join-Path $OutputRoot ('qc-gpu-' + $Stamp)
$SystemRoot  = $env:SystemRoot
$FileRepo    = Join-Path $SystemRoot 'System32\DriverStore\FileRepository'
$InfFamily   = 'qcdx8380.inf_arm64_*'          # Adreno graphics driver packages
$GfxSiblings = 'qcd*8380.inf_arm64_*'          # graphics-adjacent package families
$MaxFullCopyMB = 2000                          # size guard for full binary copy
$LogPath     = Join-Path $Out 'collect.log'

function Write-CollectLog {
    param([string]$Message)
    $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    Write-Output $line
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
}

function Save-CimJson {
    param([string]$Name, [object]$Data)
    $file = Join-Path $Out ('{0}.json' -f $Name)
    try {
        $Data | ConvertTo-Json -Depth 6 | Out-File -FilePath $file -Encoding UTF8
        Write-CollectLog ('{0}: {1} object(s) -> {2}' -f $Name, @($Data).Count, $file)
    } catch {
        Write-CollectLog ('{0}: JSON export FAILED: {1}' -f $Name, $_.Exception.Message)
    }
}

# --- Prep output tree -------------------------------------------------------
foreach ($d in '00-system','01-devices','02-display','03-driver-packages-infs',
                '04-registry','05-logs','06-driverstore-active','07-firmware',
                '08-dxdiag','09-services') {
    New-Item -ItemType Directory -Path (Join-Path $Out $d) -Force | Out-Null
}
Start-Transcript -Path (Join-Path $Out 'transcript.log') | Out-Null
Write-CollectLog "Collection started. Output: $Out"
$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { $isAdmin = $false }
Write-CollectLog ('Elevated session: ' + $isAdmin + ' (wevtutil System/Application export may require elevation)')

# --- S1 System inventory ----------------------------------------------------
try {
    Save-CimJson 'system-computer'    (Get-CimInstance Win32_ComputerSystem)
    Save-CimJson 'system-os'          (Get-CimInstance Win32_OperatingSystem)
    Save-CimJson 'system-cpu'         (Get-CimInstance Win32_Processor)
    Save-CimJson 'system-bios'        (Get-CimInstance Win32_BIOS)
    Save-CimJson 'system-board'       (Get-CimInstance Win32_BaseBoard)
    Write-CollectLog 'S1 system inventory OK'
} catch { Write-CollectLog ('S1 FAILED: ' + $_.Exception.Message) }

# --- S2 Full PnP device inventory -------------------------------------------
try {
    Get-CimInstance Win32_PnPEntity |
        Select-Object Name, DeviceID, PNPClass, Status, ConfigManagerErrorCode |
        ConvertTo-Json -Depth 4 |
        Out-File -FilePath (Join-Path $Out '01-devices\all-pnp-devices.json') -Encoding UTF8
    Write-CollectLog 'S2 PnP inventory OK'
} catch { Write-CollectLog ('S2 FAILED: ' + $_.Exception.Message) }

# --- S3 Display / GPU focused -----------------------------------------------
try {
    Save-CimJson '02-display\videocontrollers' (Get-CimInstance Win32_VideoController)
    $displayDevices = Get-CimInstance Win32_PnPEntity |
        Where-Object { $_.PNPClass -in 'Display','Monitor','SoftwareComponents' }
    Save-CimJson '02-display\display-pnp' $displayDevices
    Save-CimJson '02-display\monitors'    (Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
    Write-CollectLog 'S3 display/GPU focused OK'
} catch { Write-CollectLog ('S3 FAILED: ' + $_.Exception.Message) }

# --- S4 Driver store / driver queries ---------------------------------------
try {
    & pnputil.exe /enum-drivers  |
        Out-File (Join-Path $Out '01-devices\pnputil-enum-drivers.txt') -Encoding UTF8
    & pnputil.exe /enum-devices /extended |
        Out-File (Join-Path $Out '01-devices\pnputil-enum-devices.txt') -Encoding UTF8
    & driverquery.exe /v /fo csv |
        Out-File (Join-Path $Out '01-devices\driverquery.csv') -Encoding UTF8
    Write-CollectLog 'S4 pnputil/driverquery OK'
} catch { Write-CollectLog ('S4 FAILED: ' + $_.Exception.Message) }

# --- S5 Discover qcdx graphics driver packages + pick newest ----------------
$gfxPkgs = @()
$pkgInfo = @()
try {
    $gfxPkgs = Get-ChildItem -Path $FileRepo -Directory -Filter $InfFamily -ErrorAction SilentlyContinue
    $pkgInfo = foreach ($p in $gfxPkgs) {
        $inf = Join-Path $p.FullName 'qcdx8380.inf'
        $ver = $null; $date = $null
        if (Test-Path $inf) {
            $m = Select-String -Path $inf -Pattern 'DriverVer\s*=\s*(\d{1,2}/\d{1,2}/\d{4})\s*,\s*([\d.]+)' -Encoding Unicode |
                Select-Object -First 1
            if ($m) {
                $date = $m.Matches[0].Groups[1].Value
                try { $ver = [version]$m.Matches[0].Groups[2].Value } catch { $ver = $null }
            }
        }
        $sizeMB = [math]::Round((Get-ChildItem $p.FullName -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)
        [pscustomobject]@{ Path = $p.FullName; Version = $ver; Date = $date; SizeMB = $sizeMB }
    }
    $pkgInfo | ConvertTo-Json -Depth 3 | Out-File (Join-Path $Out '03-driver-packages-infs\package-manifest.json') -Encoding UTF8
    Write-CollectLog ('S5 found {0} qcdx package(s): {1}' -f $gfxPkgs.Count, (($pkgInfo | ForEach-Object { $_.Version }) -join ', '))
} catch { Write-CollectLog ('S5 FAILED: ' + $_.Exception.Message) }

# --- S6 Copy full active (newest) package -----------------------------------
try {
    $active = $pkgInfo | Sort-Object Version -Descending | Select-Object -First 1
    if ($active -and (Test-Path $active.Path)) {
        if ($active.SizeMB -le $MaxFullCopyMB) {
            Copy-Item -Path $active.Path -Destination (Join-Path $Out '06-driverstore-active') -Recurse -Force
            Write-CollectLog ('S6 active package copied: {0} ({1} MB)' -f $active.Version, $active.SizeMB)
        } else {
            Write-CollectLog ('S6 SKIP full copy, {0} MB exceeds guard {1} MB' -f $active.SizeMB, $MaxFullCopyMB)
        }
    } else { Write-CollectLog 'S6 no active package identified' }
} catch { Write-CollectLog ('S6 FAILED: ' + $_.Exception.Message) }

# --- S7 Firmware blobs + INFs/CATs/INIs of ALL versions & adjacent families --
try {
    foreach ($p in $gfxPkgs) {
        $dest = Join-Path $Out ('07-firmware\' + $p.Name)
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Copy-Item -Path (Join-Path $p.FullName '*.mbn') -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $p.FullName 'qcdxkmbase*.bin') -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $p.FullName 'qcdx8380.inf')   -Destination $dest -Force -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $p.FullName 'qcdx8380.cat')   -Destination $dest -Force -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $p.FullName '*.ini')          -Destination $dest -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem -Path $FileRepo -Filter $GfxSiblings -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $Out '03-driver-packages-infs') -Force -ErrorAction SilentlyContinue
        }
    Write-CollectLog 'S7 firmware + INF/CAT/INI collection OK'
} catch { Write-CollectLog ('S7 FAILED: ' + $_.Exception.Message) }

# --- S8 Registry exports (services, class, enum, Qualcomm software) ---------
try {
    $svcKeys = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -Name -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^qcdx|^qcgpu' }
    foreach ($k in $svcKeys) {
        & reg.exe export ('HKLM\SYSTEM\CurrentControlSet\Services\' + $k) (Join-Path $Out ('04-registry\services-' + $k + '.reg')) /y | Out-Null
    }
    $classRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    if (Test-Path $classRoot) {
        foreach ($sub in (Get-ChildItem $classRoot -Name)) {
            & reg.exe export ('HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\' + $sub) (Join-Path $Out ('04-registry\displayclass-' + $sub + '.reg')) /y | Out-Null
        }
    }
    foreach ($dev in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI' -Name -ErrorAction SilentlyContinue | Where-Object { $_ -match '^VEN_QCOM' })) {
        & reg.exe export ('HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\' + $dev) (Join-Path $Out ('04-registry\enum-acpi-' + ($dev -replace '[&\\]','_') + '.reg')) /y | Out-Null
    }
    foreach ($root in 'HKLM\SOFTWARE\Qualcomm','HKLM\SOFTWARE\WOW6432Node\Qualcomm') {
        if (Test-Path ('Registry::' + $root)) {
            & reg.exe export $root (Join-Path $Out ('04-registry\' + ($root -replace '[\\\s]','-') + '.reg')) /y | Out-Null
        }
    }
    $dbPkgs = Get-ChildItem 'HKLM:\SYSTEM\DriverDatabase\DriverPackages' -Name -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^qcdx8380' }
    foreach ($p in $dbPkgs) {
        & reg.exe export ('HKLM\SYSTEM\DriverDatabase\DriverPackages\' + $p) (Join-Path $Out ('04-registry\driverdb-' + $p + '.reg')) /y | Out-Null
    }
    Write-CollectLog ('S8 registry exports OK ({0} service keys)' -f @($svcKeys).Count)
} catch { Write-CollectLog ('S8 FAILED: ' + $_.Exception.Message) }

# --- S9 Services -------------------------------------------------------------
try {
    $gsvc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^qcdx|^qcgpu' }
    $gsvc | ConvertTo-Json -Depth 3 | Out-File (Join-Path $Out '09-services\gfx-services.json') -Encoding UTF8
    foreach ($s in $gsvc) {
        & sc.exe qc $s.Name | Out-File (Join-Path $Out ('09-services\sc-qc-' + $s.Name + '.txt')) -Encoding UTF8
    }
    Write-CollectLog 'S9 services OK'
} catch { Write-CollectLog ('S9 FAILED: ' + $_.Exception.Message) }

# --- S10 Event logs (EVTX + QC-filtered CSV) --------------------------------
try {
    foreach ($ch in @('System','Application','Microsoft-Windows-Kernel-PnP/Configuration')) {
        $name = $ch -replace '[/\\]','-'
        $evtx = Join-Path $Out ('05-logs\' + $name + '.evtx')
        & wevtutil.exe epl $ch $evtx | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-CollectLog ('wevtutil export FAILED for {0} (exit {1})' -f $ch, $LASTEXITCODE)
        }
    }
    $since = (Get-Date).AddDays(-30)
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since } -MaxEvents 3000 -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match 'qcdx|qcom|display|dxgkrnl' } |
        Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
        ConvertTo-Json -Depth 4 |
        Out-File (Join-Path $Out '05-logs\qc-filtered-events.json') -Encoding UTF8
    Write-CollectLog 'S10 event logs OK'
} catch { Write-CollectLog ('S10 FAILED: ' + $_.Exception.Message) }

# --- S11 SetupAPI logs -------------------------------------------------------
try {
    Get-ChildItem (Join-Path $SystemRoot 'INF\setupapi.dev*.log') -ErrorAction SilentlyContinue |
        Copy-Item -Destination (Join-Path $Out '05-logs') -Force -ErrorAction SilentlyContinue
    Write-CollectLog 'S11 setupapi logs OK'
} catch { Write-CollectLog ('S11 FAILED: ' + $_.Exception.Message) }

# --- S12 dxdiag --------------------------------------------------------------
try {
    $dxPath = Join-Path $Out '08-dxdiag\dxdiag.txt'
    & dxdiag.exe /t $dxPath
    $prev = -1
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 5
        if (Test-Path $dxPath) {
            $len = (Get-Item $dxPath).Length
            if ($len -gt 0 -and $len -eq $prev) { break }
            $prev = $len
        }
    }
    Write-CollectLog ('S12 dxdiag OK ({0} bytes)' -f ((Get-Item $dxPath -ErrorAction SilentlyContinue).Length))
} catch { Write-CollectLog ('S12 FAILED: ' + $_.Exception.Message) }

# --- S13 Manifest, hashes, versions, zip ------------------------------------
try {
    $files = Get-ChildItem $Out -Recurse -File
    $files | Get-FileHash -Algorithm SHA256 -ErrorAction SilentlyContinue |
        Select-Object @{n='Path';e={$_.Path -replace [regex]::Escape($Out), '.'}}, Hash |
        Export-Csv (Join-Path $Out 'checksums.csv') -NoTypeInformation
    $files | ForEach-Object {
        [pscustomobject]@{
            Path    = $_.FullName.Replace($Out, '.')
            Size    = $_.Length
            FileVer = $_.VersionInfo.FileVersion
            ProdVer = $_.VersionInfo.ProductVersion
        }
    } | Export-Csv (Join-Path $Out 'file-versions.csv') -NoTypeInformation
    Stop-Transcript | Out-Null
    $zip = Join-Path $OutputRoot ('qc-gpu-collect-' + $Stamp + '.zip')
    Compress-Archive -Path (Join-Path $Out '*') -DestinationPath $zip -CompressionLevel Optimal -ErrorAction Stop
    Write-CollectLog ('S13 zip created: {0}' -f $zip)
} catch {
    Write-CollectLog ('S13 zip/hash step FAILED: ' + $_.Exception.Message + ' - raw folder retained.')
    try { Stop-Transcript | Out-Null } catch { Write-CollectLog ('transcript stop FAILED: ' + $_.Exception.Message) }
}

Write-CollectLog 'Collection finished.'