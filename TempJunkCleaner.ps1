param(
    [switch]$IncludeSystemTemp,
    [switch]$WhatIf,
    [int]$MaxAgeDays = 7,
    [string]$LogPath = "$PSScriptRoot\TempJunkCleaner.log"
)

# Safe temp/junk cleaner for Windows PowerShell
# - Elevates to admin when needed
# - Works only on known temp locations
# - Supports -WhatIf and age filtering
# - Does not delete system-critical folders by default

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] $Message"
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TargetPaths {
    param([switch]$IncludeSystemTemp)

    $paths = @()

    $userTemp = $env:TEMP
    if ($userTemp) { $paths += $userTemp }

    $userTmp = $env:TMP
    if ($userTmp -and $userTmp -ne $userTemp) { $paths += $userTmp }

    $localAppData = [System.Environment]::GetEnvironmentVariable('LOCALAPPDATA', 'User')
    if ($localAppData) {
        $paths += Join-Path $localAppData 'Temp'
        $paths += Join-Path $localAppData 'Microsoft\Windows\Temporary Internet Files'
    }

    $shell = New-Object -ComObject Shell.Application
    $desktopFolder = $shell.NameSpace(0x10)  # CSIDL_DESKTOP
    $profilePath = $desktopFolder.Self.Path
    $userProfile = Split-Path -Parent $profilePath

    if ($userProfile) {
        $paths += Join-Path $userProfile 'AppData\Local\Temp'
    }

    if ($IncludeSystemTemp) {
        $paths += 'C:\Windows\Temp'
        $paths += 'C:\Windows\Temp\*'
    }

    # Deduplicate and filter to valid temp-like folders only
    $paths = $paths |
        Where-Object { $_ -and $_.Trim() } |
        Select-Object -Unique |
        Where-Object {
            $_ -notmatch 'System32' -and
            $_ -notmatch 'Windows\\System' -and
            $_ -notmatch 'Program Files' -and
            $_ -notmatch 'ProgramData\\Microsoft'
        }

    return $paths
}

function Remove-TempItems {
    param(
        [string[]]$Paths,
        [int]$MaxAgeDays,
        [switch]$WhatIf
    )

    $cutoff = (Get-Date).AddDays(-$MaxAgeDays)
    $deletedCount = 0
    $skippedCount = 0

    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Log "Skipping missing path: $path"
            continue
        }

        try {
            $items = Get-ChildItem -LiteralPath $path -Force -Recurse -ErrorAction Stop | Where-Object {
                (-not $_.PSIsContainer) -and ($_.LastWriteTime -lt $cutoff)
            }
        }
        catch {
            Write-Log "Could not access $path : $($_.Exception.Message)"
            $skippedCount++
            continue
        }

        foreach ($item in $items) {
            try {
                if ($WhatIf) {
                    Write-Log "WhatIf: would delete $($item.FullName)"
                    $deletedCount++
                    continue
                }

                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                Write-Log "Deleted $($item.FullName)"
                $deletedCount++
            }
            catch {
                Write-Log "Failed to delete $($item.FullName): $($_.Exception.Message)"
                $skippedCount++
            }
        }
    }

    [pscustomobject]@{
        Deleted = $deletedCount
        Skipped = $skippedCount
    }
}

# Create a log file if missing
if (-not (Test-Path -LiteralPath $LogPath)) {
    New-Item -Path $LogPath -ItemType File -Force | Out-Null
}

Write-Log "Starting Temp Junk Cleaner"
Write-Log "Max age: $MaxAgeDays days"
Write-Log "IncludeSystemTemp: $IncludeSystemTemp"
Write-Log "WhatIf: $WhatIf"

if (-not (Test-IsAdmin)) {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        throw 'Could not determine script path. Please run as Administrator.'
    }

    Write-Log 'Not running as Administrator; attempting to relaunch with elevation.'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', `"$scriptPath`")
    if ($IncludeSystemTemp) { $arguments += '-IncludeSystemTemp' }
    if ($WhatIf) { $arguments += '-WhatIf' }
    if ($MaxAgeDays -ne 7) { $arguments += '-MaxAgeDays'; $arguments += $MaxAgeDays }

    Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments
    Write-Log 'Elevated process launched. Exiting current session.'
    exit 0
}

$targetPaths = Get-TargetPaths -IncludeSystemTemp:$IncludeSystemTemp

if (-not $targetPaths -or $targetPaths.Count -eq 0) {
    Write-Log 'No valid temp paths found.'
    exit 0
}

Write-Log "Target paths:"
foreach ($p in $targetPaths) { Write-Log "  $p" }

$result = Remove-TempItems -Paths $targetPaths -MaxAgeDays $MaxAgeDays -WhatIf:$WhatIf
Write-Log "Finished. Deleted: $($result.Deleted) | Skipped: $($result.Skipped)"
Write-Log 'Temp Junk Cleaner complete.'

if ($WhatIf) {
    Write-Host "`nWhatIf mode active. No files were removed.`n" -ForegroundColor Yellow
}

Write-Host "`nCleanup summary: Deleted $($result.Deleted), Skipped $($result.Skipped)`n" -ForegroundColor Green

# End of script
