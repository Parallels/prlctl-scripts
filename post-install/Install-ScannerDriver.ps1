<#
.SYNOPSIS
    App Delivery post-install script: silent installation of PaperStream IP
    (TWAIN) scanner driver for Fujitsu/Ricoh fi-series scanners.

.DESCRIPTION
    Target device: fi-7160 / fi-7180 (served by filx5.inf / filx5-x64.inf).

    Verified on Windows 11 guest (2026-10-16):
      * msiexec /qn returns 0, no reboot required
      * INFs staged into the driver store, incl. filx5-x64.inf
      * TWAIN data sources registered under C:\Windows\twain_32\Fjicube
    The package ships WIA user-mode minidrivers only (no .sys), which is why
    x86/x64 INFs stage successfully under ARM64 emulation.

.NOTES
    Authoring rules for App Delivery transport - the file travels as
    base64/JSON, so keep it robust:
      * no backtick-escaped quotes (use [char]34)
      * never shadow automatic variables ($args, $input, $error)
      * no if/switch inside hashtable literals (PowerShell 5.1 parse error)
      * plain ASCII, save as UTF-8 without BOM
    Always validate before upload:
      [Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$err)

    32-bit vs 64-bit: this is the 32-bit TWAIN build, so twain_64 stays empty.
    Switch $DriverUrl to PSIPTWAIN64-3_40_2.exe if the scanning application
    is 64-bit - TWAIN cannot cross the bitness boundary.
#>

# --- breadcrumb: proves the file parsed and started executing ----------------
# If this file exists but install.log does not, the failure was at runtime.
# If neither exists, the script never parsed or never ran.
try {
    $bcFile = 'C:\Windows\Temp\prl_postinstall_started.txt'
    $bcMsg  = (Get-Date -Format o) + ' pid=' + $PID + ' ps=' + $PSVersionTable.PSVersion
    Out-File -FilePath $bcFile -InputObject $bcMsg -Append -Encoding utf8
} catch { }
#------------------------------------------------------------------------------

#============================== CONFIG ========================================

# Mirrored vendor package. The PFU download page is session-bound and cannot be
# fetched non-interactively, hence the internal mirror.
$DriverUrl      = 'PASS_URL_TO_DRIVER_HERE'
$DriverChecksum = 'PASS_CHECKSUM_HERE'

# PsipUpdater.exe self-extractor switches.
# WARNING: /D does NOT suppress the "File already exists. Overwrite?(Yes/No/All)"
# prompt - it blocks forever under -NonInteractive. The target folder is always
# removed from PowerShell beforehand instead.
$ExtractArgs    = @('/X')
$ExtractDirName = 'Disk1'
$InnerMsiRel    = 'Disk1\PSTWAIN\ext\PSIP_TWAIN.msi'

# Direct MSI install. Returns 1625 (ERROR_INSTALL_PACKAGE_REJECTED) when the
# process is not elevated - not an issue under SYSTEM.
$MsiArgs          = @('/qn', '/norestart', 'REBOOT=ReallySuppress')
$SuccessExitCodes = @(0, 1641, 3010)

# Verification targets
$TwainDsRoot = "$env:SystemRoot\twain_32\Fjicube"
$ExpectedInf = 'filx5'
$ProductName = 'PaperStream IP|PFU|Ricoh'

$InstallTimeoutMin      = 30
$SkipIfAlreadyInstalled = $true

#==============================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$WorkDir = Join-Path $env:ProgramData 'Parallels\PostInstall\ScannerDriver'
$LogFile = Join-Path $WorkDir 'install.log'

#------------------------------- helpers --------------------------------------

function Write-Log {
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('INFO','WARN','ERROR')][string] $Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($Level -eq 'ERROR') { [Console]::Error.WriteLine($line) } else { Write-Host $line }
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding utf8 } catch { }
}

function Fail {
    param([string] $Message, [int] $Code = 1)
    Write-Log $Message -Level ERROR
    Write-Log ('Aborting with exit code ' + $Code) -Level ERROR
    exit $Code
}

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DriverPackage {
    param(
        [Parameter(Mandatory)][string] $Url,
        [Parameter(Mandatory)][string] $Destination,
        [string] $Checksum
    )

    $expected = $null
    if ($Checksum -match '^(?i)\s*sha256:(.+)$') {
        $expected = $Matches[1].Replace(' ', '').ToUpperInvariant()
    }

    if (Test-Path -LiteralPath $Destination) {
        $reuse = $false
        if ($expected) {
            $h = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
            if ($h -eq $expected) { $reuse = $true }
        }
        if ($reuse) {
            Write-Log 'Cached package is valid, skipping download.'
            return
        }
        Write-Log 'Discarding stale/invalid cached package.'
        Remove-Item -LiteralPath $Destination -Force
    }

    Write-Log ('Downloading from ' + $Url)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch { }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 900
    } catch {
        Fail ('Download failed: ' + $_.Exception.Message) 2
    }
    $sw.Stop()

    $size = (Get-Item -LiteralPath $Destination).Length
    Write-Log ('Downloaded {0:N1} MB in {1:N0}s' -f ($size / 1MB), $sw.Elapsed.TotalSeconds)

    if ($size -lt 100MB) {
        Fail ('Downloaded file is only ' + $size + ' bytes - the mirror likely returned an error page.') 2
    }

    if ($expected) {
        $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
        if ($actual -ne $expected) {
            Write-Log ('Expected SHA256: ' + $expected) -Level ERROR
            Write-Log ('Actual   SHA256: ' + $actual)   -Level ERROR
            Fail 'Checksum mismatch.' 3
        }
        Write-Log 'SHA256 verified.'
    } else {
        Write-Log 'No checksum configured - integrity NOT verified.' -Level WARN
    }
}

function Expand-DriverPackage {
    param(
        [Parameter(Mandatory)][string] $Exe,
        [Parameter(Mandatory)][string] $ExtractRoot
    )

    if (Test-Path -LiteralPath $ExtractRoot) {
        Write-Log ('Removing previous extraction: ' + $ExtractRoot)
        Remove-Item -LiteralPath $ExtractRoot -Recurse -Force
    }

    Write-Log 'Extracting package (this takes a while for 246 MB)...'
    $workDirForExe = Split-Path -Parent $Exe
    $proc = Start-Process -FilePath $Exe -ArgumentList $ExtractArgs -PassThru -WindowStyle Hidden -WorkingDirectory $workDirForExe

    $timeoutMs = $InstallTimeoutMin * 60 * 1000
    if (-not $proc.WaitForExit($timeoutMs)) {
        try { $proc.Kill() } catch { }
        Fail ('Self-extractor timed out after ' + $InstallTimeoutMin + ' minute(s) - it may be waiting for input.') 4
    }
    if ($proc.ExitCode -ne 0) {
        Fail ('Self-extractor failed with exit code ' + $proc.ExitCode) 4
    }
    Write-Log 'Extraction complete.'
}

function Install-Msi {
    param([Parameter(Mandatory)][string] $MsiPath)

    $msiLog = Join-Path $WorkDir 'msi.log'

    # Quotes built via [char]34 - backticks are fragile when the script is
    # transported as base64/JSON through App Delivery.
    $q = [char]34
    $msiArgList = @()
    $msiArgList += '/i'
    $msiArgList += ($q + $MsiPath + $q)
    $msiArgList += $MsiArgs
    $msiArgList += '/L*v'
    $msiArgList += ($q + $msiLog + $q)

    Write-Log ('Running: msiexec.exe ' + ($msiArgList -join ' '))
    $proc = Start-Process msiexec.exe -ArgumentList $msiArgList -PassThru -WindowStyle Hidden

    $timeoutMs = $InstallTimeoutMin * 60 * 1000
    if (-not $proc.WaitForExit($timeoutMs)) {
        try { $proc.Kill() } catch { }
        Fail ('msiexec timed out after ' + $InstallTimeoutMin + ' minute(s).') 5
    }

    $code = $proc.ExitCode
    Write-Log ('msiexec exit code: ' + $code)

    if ($SuccessExitCodes -notcontains $code) {
        if ($code -eq 1625) { Write-Log '1625 = forbidden by system policy (not elevated?).' -Level ERROR }
        if ($code -eq 1603) { Write-Log '1603 = fatal error during installation.' -Level ERROR }
        if ($code -eq 1618) { Write-Log '1618 = another installation is already in progress.' -Level ERROR }

        if (Test-Path -LiteralPath $msiLog) {
            $lines = @(Select-String -LiteralPath $msiLog -Pattern 'value 3|Note: 1:')
            $tail  = @($lines | Select-Object -Last 15)
            foreach ($l in $tail) {
                Write-Log ('  msi: ' + $l.Line.Trim()) -Level ERROR
            }
        }
        Fail 'MSI installation failed.' $code
    }

    if (($code -eq 1641) -or ($code -eq 3010)) {
        Write-Log ('Installer requested a reboot (' + $code + ') - deferred to the VM lifecycle.') -Level WARN
    }
}

function Test-ScannerDriverInstalled {
    $uninstallKeys = 'HKLM:\SOFTWARE\*\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $product = @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -match $ProductName })

    $ds = @(Get-ChildItem -LiteralPath $TwainDsRoot -Recurse -Include *.ds -ErrorAction SilentlyContinue)

    $inf = @(Get-WindowsDriver -Online -All -ErrorAction SilentlyContinue |
             Where-Object { $_.OriginalFileName -match $ExpectedInf })

    # PowerShell 5.1 forbids statements inside hashtable literals, so every
    # value is computed before the object is built.
    $productText = $null
    if ($product.Count -gt 0) {
        $productText = '{0} {1}' -f $product[0].DisplayName, $product[0].DisplayVersion
    }

    $infText = $null
    if ($inf.Count -gt 0) {
        $infText = $inf[0].Driver
    }

    $allOk = $false
    if (($null -ne $productText) -and ($ds.Count -gt 0) -and ($inf.Count -gt 0)) {
        $allOk = $true
    }

    $result = New-Object psobject
    $result | Add-Member NoteProperty Product      $productText
    $result | Add-Member NoteProperty TwainDsCount $ds.Count
    $result | Add-Member NoteProperty InfStaged    $infText
    $result | Add-Member NoteProperty AllOk        $allOk
    return $result
}

#-------------------------------- main ----------------------------------------

try {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

    Write-Log '=============================================================='
    Write-Log 'PaperStream IP (TWAIN) post-install started.'
    Write-Log ('Host     : ' + $env:COMPUTERNAME)
    Write-Log ('User     : ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
    Write-Log ('Elevated : ' + (Test-Elevated))
    Write-Log ('OS       : ' + (Get-CimInstance Win32_OperatingSystem).Caption)
    Write-Log ('Arch     : ' + $env:PROCESSOR_ARCHITECTURE)
    Write-Log ('PS       : ' + $PSVersionTable.PSVersion)
    Write-Log ('WorkDir  : ' + $WorkDir)

    if (-not (Test-Elevated)) {
        Fail 'Administrative privileges are required (msiexec /qn returns 1625 otherwise).' 6
    }

    $pre = Test-ScannerDriverInstalled
    if ($pre.AllOk -and $SkipIfAlreadyInstalled) {
        Write-Log ('Already installed: ' + $pre.Product + '; TWAIN DS: ' + $pre.TwainDsCount + '; INF: ' + $pre.InfStaged)
        Write-Log 'Nothing to do.'
        exit 0
    }

    $uri = New-Object System.Uri($DriverUrl)
    $exeName = [IO.Path]::GetFileName($uri.LocalPath)
    if (-not $exeName) { $exeName = 'PSIPTWAIN.exe' }
    $exePath = Join-Path $WorkDir $exeName

    Get-DriverPackage -Url $DriverUrl -Destination $exePath -Checksum $DriverChecksum

    $extractRoot = Join-Path $WorkDir $ExtractDirName
    Expand-DriverPackage -Exe $exePath -ExtractRoot $extractRoot

    $msiPath = Join-Path $WorkDir $InnerMsiRel
    if (-not (Test-Path -LiteralPath $msiPath)) {
        Write-Log ('Expected MSI not found at ' + $msiPath) -Level ERROR
        $found = @(Get-ChildItem -LiteralPath $extractRoot -Recurse -Filter *.msi -ErrorAction SilentlyContinue)
        foreach ($f in $found) {
            Write-Log ('  found instead: ' + $f.FullName) -Level ERROR
        }
        Fail 'Package layout changed - update the InnerMsiRel setting.' 7
    }

    Install-Msi -MsiPath $msiPath

    Start-Sleep -Seconds 5
    $post = Test-ScannerDriverInstalled

    Write-Log '--- verification ---'
    Write-Log ('Product       : ' + $post.Product)
    Write-Log ('TWAIN sources : ' + $post.TwainDsCount + ' under ' + $TwainDsRoot)
    Write-Log ('INF staged    : ' + $post.InfStaged + " (match '" + $ExpectedInf + "')")

    if (-not $post.AllOk) {
        Fail 'Installer reported success but verification failed.' 8
    }

    Write-Log 'Scanner driver post-install completed successfully.'
    Write-Log 'NOTE: PnP binding can only be confirmed with the scanner attached.'
    exit 0
}
catch {
    Write-Log ('Unhandled error: ' + $_.Exception.Message) -Level ERROR
    Write-Log ($_.ScriptStackTrace) -Level ERROR
    exit 1
}
