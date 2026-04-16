$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptPath = Join-Path $PSScriptRoot "EmergencyBackup.ps1"
$homePath = [Environment]::GetFolderPath("UserProfile")
$candidates = @(
    [Environment]::GetFolderPath("Desktop"),
    [Environment]::GetFolderPath("MyDocuments"),
    [Environment]::GetFolderPath("MyPictures"),
    [Environment]::GetFolderPath("MyVideos"),
    [Environment]::GetFolderPath("MyMusic"),
    (Join-Path $homePath ".ssh"),
    (Join-Path $homePath ".gnupg")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$form = New-Object System.Windows.Forms.Form
$form.Text = "Unique Data Backup"
$form.Size = New-Object System.Drawing.Size(720, 520)
$form.StartPosition = "CenterScreen"

$label = New-Object System.Windows.Forms.Label
$label.Text = "Select important folders to back up. Reproducible files are logged, not copied."
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(12, 12)
$form.Controls.Add($label)

$list = New-Object System.Windows.Forms.CheckedListBox
$list.Location = New-Object System.Drawing.Point(12, 42)
$list.Size = New-Object System.Drawing.Size(680, 310)
$list.CheckOnClick = $true
foreach ($item in $candidates) { [void]$list.Items.Add($item, $true) }
$form.Controls.Add($list)

$destBox = New-Object System.Windows.Forms.TextBox
$destBox.Location = New-Object System.Drawing.Point(12, 370)
$destBox.Size = New-Object System.Drawing.Size(550, 24)
$form.Controls.Add($destBox)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = "Select backup drive/folder"
$browse.Location = New-Object System.Drawing.Point(570, 368)
$browse.Size = New-Object System.Drawing.Size(122, 28)
$browse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select backup destination"
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $destBox.Text = $dialog.SelectedPath
    }
})
$form.Controls.Add($browse)

$run = New-Object System.Windows.Forms.Button
$run.Text = "Run backup now"
$run.Location = New-Object System.Drawing.Point(12, 420)
$run.Size = New-Object System.Drawing.Size(160, 34)
$run.Add_Click({
    if (-not $destBox.Text) {
        [System.Windows.Forms.MessageBox]::Show("Select a destination first.")
        return
    }
    $sources = @()
    foreach ($checked in $list.CheckedItems) { $sources += [string]$checked }
    if ($sources.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select at least one source folder.")
        return
    }
    $sourceList = Join-Path $env:TEMP "software-backup-sources.txt"
    $sources | Out-File -FilePath $sourceList -Encoding UTF8
    $argList = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$scriptPath,"-DestinationRoot",$destBox.Text,"-SourceListFile",$sourceList)
    Start-Process powershell.exe -ArgumentList $argList -Wait
    [System.Windows.Forms.MessageBox]::Show("Backup finished. Check the selected destination for SoftwareBackup-*.")
})
$form.Controls.Add($run)

[void]$form.ShowDialog()
