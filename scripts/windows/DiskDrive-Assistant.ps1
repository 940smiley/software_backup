[CmdletBinding()]
param(
    [ValidateSet("Auto","Gui","Assisted")]
    [string]$Mode = "Assisted",
    [string]$OutputRoot = (Join-Path $env:USERPROFILE "Desktop")
)

$ErrorActionPreference = "Continue"

if ($Mode -eq "Gui") {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select where the disk/drive plan should be created"
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $OutputRoot = $dialog.SelectedPath
    } else {
        throw "No output folder selected."
    }
}

if ($Mode -eq "Assisted") {
    Write-Host "This workflow inventories disks, checks health signals, and generates reviewable scripts." -ForegroundColor Cyan
    Write-Host "It will not repartition or format anything during diagnosis." -ForegroundColor Cyan
    Read-Host "Press Enter to collect disk and volume information"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path $OutputRoot "DiskDrivePlan-$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$disks = Get-Disk
$physical = Get-PhysicalDisk -ErrorAction SilentlyContinue
$volumes = Get-Volume -ErrorAction SilentlyContinue
$partitions = Get-Partition -ErrorAction SilentlyContinue

$disks | Format-List * | Out-File (Join-Path $out "disks.txt")
$physical | Format-List * | Out-File (Join-Path $out "physical_disks.txt")
$volumes | Format-List * | Out-File (Join-Path $out "volumes.txt")
$partitions | Format-List * | Out-File (Join-Path $out "partitions.txt")

$recommendations = New-Object System.Collections.Generic.List[string]
foreach ($disk in $disks) {
    if ($disk.HealthStatus -and $disk.HealthStatus -ne "Healthy") {
        $recommendations.Add("Disk $($disk.Number) reports $($disk.HealthStatus). Prefer replacement before repartitioning.")
    }
    if ($disk.OperationalStatus -contains "Offline") {
        $recommendations.Add("Disk $($disk.Number) is offline. Inspect cabling, enclosure, or SAN policy before writes.")
    }
    if ($disk.PartitionStyle -eq "RAW") {
        $recommendations.Add("Disk $($disk.Number) is RAW. It may need partitioning after backup/recovery review.")
    }
}
if ($recommendations.Count -eq 0) {
    $recommendations.Add("No obvious disk health failure detected from Windows storage APIs.")
}
$recommendations | Out-File (Join-Path $out "recommendations.txt") -Encoding UTF8

if ($Mode -eq "Assisted") {
    Write-Host "`nRecommendations:" -ForegroundColor Cyan
    $recommendations | ForEach-Object { Write-Host "- $_" }
    Read-Host "Press Enter to generate backup, mount, and repartition helper scripts"
}

$backupScript = @'
# Review and edit before running.
param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$DestinationPath
)
robocopy $SourcePath $DestinationPath /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /XJ /LOG+:backup-before-disk-change.log
'@
$backupScript | Out-File (Join-Path $out "01_backup_before_disk_change.ps1") -Encoding UTF8

$mountScript = @'
# Review disk and partition numbers before running.
param(
    [Parameter(Mandatory=$true)][int]$DiskNumber,
    [Parameter(Mandatory=$true)][int]$PartitionNumber,
    [Parameter(Mandatory=$true)][string]$DriveLetter
)
Set-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -NewDriveLetter $DriveLetter.TrimEnd(":")
'@
$mountScript | Out-File (Join-Path $out "02_assign_drive_letter.ps1") -Encoding UTF8

$repartScript = @'
# DESTRUCTIVE. This wipes the selected disk. Review recommendations.txt first.
param(
    [Parameter(Mandatory=$true)][int]$DiskNumber,
    [string]$Label = "Data"
)
$confirm = Read-Host "Type WIPE-DISK-$DiskNumber to erase disk $DiskNumber"
if ($confirm -ne "WIPE-DISK-$DiskNumber") { throw "Confirmation failed." }
Initialize-Disk -Number $DiskNumber -PartitionStyle GPT -PassThru |
    New-Partition -UseMaximumSize -AssignDriveLetter |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel $Label -Confirm:$false
'@
$repartScript | Out-File (Join-Path $out "03_DESTRUCTIVE_repartition_gpt_ntfs.ps1") -Encoding UTF8

Write-Host "Disk/drive plan created: $out" -ForegroundColor Green
Get-Content (Join-Path $out "recommendations.txt")
