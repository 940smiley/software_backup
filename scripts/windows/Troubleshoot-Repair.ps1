[CmdletBinding()]
param(
    [ValidateSet("Auto","Gui","Assisted")]
    [string]$Mode = "Assisted",
    [switch]$SkipUpdates
)

$ErrorActionPreference = "Continue"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "Run this script as Administrator for full repair capability."
    }
}

function Step {
    param([string]$Title, [scriptblock]$Action)
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
    if ($Mode -eq "Assisted") {
        Read-Host "Press Enter to run this step"
    }
    try { & $Action } catch { Write-Warning $_.Exception.Message }
}

Assert-Admin
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path $env:TEMP "WindowsRepair-$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

Step "System file check" { sfc /scannow | Tee-Object (Join-Path $out "sfc.txt") }
Step "Component store repair" { DISM /Online /Cleanup-Image /RestoreHealth | Tee-Object (Join-Path $out "dism_restorehealth.txt") }
Step "Disk and volume health inventory" {
    Get-Disk | Format-List * | Out-File (Join-Path $out "disks.txt")
    Get-Volume | Format-Table -AutoSize | Out-File (Join-Path $out "volumes.txt")
    Get-PhysicalDisk | Format-List * | Out-File (Join-Path $out "physical_disks.txt")
}
Step "Driver inventory" { driverquery /v /fo csv | Out-File (Join-Path $out "drivers.csv") -Encoding UTF8 }
if (-not $SkipUpdates) {
    Step "Winget application upgrades when available" {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements | Tee-Object (Join-Path $out "winget_upgrade.txt")
        } else {
            "winget not installed" | Tee-Object (Join-Path $out "winget_upgrade.txt")
        }
    }
    Step "Windows Update module hint" {
        "For full Windows Update automation install PSWindowsUpdate, then run: Install-WindowsUpdate -AcceptAll -AutoReboot" |
            Tee-Object (Join-Path $out "windows_update_next_step.txt")
    }
}
Step "Network stack report and repair commands" {
    ipconfig /all | Out-File (Join-Path $out "ipconfig_all.txt")
    "Optional manual repair commands:" | Tee-Object (Join-Path $out "network_repair_commands.txt")
    "netsh winsock reset" | Tee-Object (Join-Path $out "network_repair_commands.txt") -Append
    "netsh int ip reset" | Tee-Object (Join-Path $out "network_repair_commands.txt") -Append
}

Write-Host "`nRepair run complete. Logs: $out" -ForegroundColor Green
