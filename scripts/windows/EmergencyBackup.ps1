[CmdletBinding()]
param(
    [string]$DestinationRoot,
    [string[]]$SourceRoots,
    [string]$SourceListFile
)

$ErrorActionPreference = "Stop"

function Select-BackupDestination {
    param([string]$Initial)
    if ($Initial) { return $Initial }
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the drive or folder where the emergency backup should be written"
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    throw "No destination selected."
}

function Write-TextLog {
    param([string]$Path, [scriptblock]$Block)
    try {
        & $Block | Out-File -FilePath $Path -Encoding UTF8
    } catch {
        "ERROR: $($_.Exception.Message)" | Out-File -FilePath $Path -Encoding UTF8
    }
}

function Get-DefaultSourceRoots {
    $homePath = [Environment]::GetFolderPath("UserProfile")
    @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("MyDocuments"),
        [Environment]::GetFolderPath("MyPictures"),
        [Environment]::GetFolderPath("MyVideos"),
        [Environment]::GetFolderPath("MyMusic"),
        (Join-Path $homePath "Favorites"),
        (Join-Path $homePath ".ssh"),
        (Join-Path $homePath ".gnupg"),
        (Join-Path $homePath "AppData\Roaming\Microsoft\Windows\Start Menu"),
        (Join-Path $homePath "AppData\Roaming\Microsoft\Signatures")
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
}

function Test-ReproduciblePath {
    param([string]$Path)
    $patterns = @(
        "\\node_modules(\\|$)", "\\.git(\\|$)", "\\.svn(\\|$)", "\\.hg(\\|$)",
        "\\bin(\\|$)", "\\obj(\\|$)", "\\target(\\|$)", "\\dist(\\|$)", "\\build(\\|$)",
        "\\.cache(\\|$)", "\\Cache(\\|$)", "\\Code Cache(\\|$)", "\\__pycache__(\\|$)",
        "\\.venv(\\|$)", "\\venv(\\|$)", "\\Downloads(\\|$)", "\\OneDriveTemp(\\|$)",
        "\\AppData\\Local\\Temp(\\|$)", "\\AppData\\Local\\Packages(\\|$)",
        "\\AppData\\Local\\Microsoft\\WindowsApps(\\|$)"
    )
    foreach ($pattern in $patterns) {
        if ($Path -match $pattern) { return $true }
    }
    return $false
}

function Copy-UniqueFiles {
    param(
        [string[]]$Roots,
        [string]$DataDir,
        [string]$ManifestPath,
        [string]$SkippedPath,
        [string]$DuplicatePath
    )

    $hashes = @{}
    "Hash,Source,Destination,Bytes,ModifiedUtc" | Out-File $ManifestPath -Encoding UTF8
    "Reason,Path" | Out-File $SkippedPath -Encoding UTF8
    "Hash,DuplicateSource,KeptDestination" | Out-File $DuplicatePath -Encoding UTF8

    foreach ($root in $Roots) {
        if (-not (Test-Path $root)) { continue }
        $rootName = ($root -replace "^[A-Za-z]:\\?", "" -replace "[\\/:*?`"<>|]", "_")
        Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $file = $_
            if (Test-ReproduciblePath -Path $file.FullName) {
                "reproducible_or_cache,""$($file.FullName)""" | Out-File $SkippedPath -Append -Encoding UTF8
                return
            }
            try {
                $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                if ($hashes.ContainsKey($hash)) {
                    "$hash,""$($file.FullName)"",""$($hashes[$hash])""" | Out-File $DuplicatePath -Append -Encoding UTF8
                    return
                }
                $relative = $file.FullName.Substring($root.Length).TrimStart("\")
                $dest = Join-Path $DataDir (Join-Path $rootName $relative)
                New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
                Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
                $hashes[$hash] = $dest
                "$hash,""$($file.FullName)"",""$dest"",$($file.Length),$($file.LastWriteTimeUtc.ToString("o"))" | Out-File $ManifestPath -Append -Encoding UTF8
            } catch {
                "error_$($_.Exception.GetType().Name),""$($file.FullName)""" | Out-File $SkippedPath -Append -Encoding UTF8
            }
        }
    }
}

$destination = Select-BackupDestination -Initial $DestinationRoot
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $destination "SoftwareBackup-$stamp"
$dataDir = Join-Path $backupRoot "data"
$logsDir = Join-Path $backupRoot "logs"
$manifestDir = Join-Path $backupRoot "manifests"
$generatedDir = Join-Path $backupRoot "generated"
New-Item -ItemType Directory -Force -Path $dataDir,$logsDir,$manifestDir,$generatedDir | Out-Null

$sources = if ($SourceListFile -and (Test-Path $SourceListFile)) {
    Get-Content -LiteralPath $SourceListFile | Where-Object { $_ }
} elseif ($SourceRoots) {
    $SourceRoots
} else {
    Get-DefaultSourceRoots
}
$sources | Out-File (Join-Path $logsDir "selected_sources.txt") -Encoding UTF8

Write-TextLog (Join-Path $logsDir "system_info.txt") { systeminfo }
Write-TextLog (Join-Path $logsDir "drivers.csv") { driverquery /v /fo csv }
Write-TextLog (Join-Path $logsDir "volumes.txt") { Get-Volume | Format-Table -AutoSize | Out-String }
Write-TextLog (Join-Path $logsDir "disks.txt") { Get-Disk | Format-Table -AutoSize | Out-String }
Write-TextLog (Join-Path $logsDir "installed_programs_registry.csv") {
    $keys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object DisplayName |
        Select-Object DisplayName,DisplayVersion,Publisher,InstallDate,InstallLocation,UninstallString |
        Sort-Object DisplayName |
        ConvertTo-Csv -NoTypeInformation
}
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-TextLog (Join-Path $logsDir "winget_list.txt") { winget list --accept-source-agreements }
    $wingetExport = Join-Path $generatedDir "winget_export.json"
    winget export --accept-source-agreements --output $wingetExport | Out-Null
}
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-TextLog (Join-Path $logsDir "choco_list.txt") { choco list --local-only }
}
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-TextLog (Join-Path $logsDir "scoop_export.json") { scoop export }
}

Copy-UniqueFiles -Roots $sources -DataDir $dataDir `
    -ManifestPath (Join-Path $manifestDir "copied_unique_files.csv") `
    -SkippedPath (Join-Path $manifestDir "skipped_reproducible_or_errors.csv") `
    -DuplicatePath (Join-Path $manifestDir "duplicates_logged_not_copied.csv")

"Backup complete: $backupRoot" | Tee-Object -FilePath (Join-Path $backupRoot "BACKUP_COMPLETE.txt")
