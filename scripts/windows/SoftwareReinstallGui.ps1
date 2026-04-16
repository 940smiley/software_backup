$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-InstalledSoftware {
    $items = @()
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $raw = winget list --accept-source-agreements | Out-String
        foreach ($line in ($raw -split "`r?`n")) {
            if ($line -match "^\S" -and $line -notmatch "^-|Name\s+Id\s+Version|^\s*$") {
                $parts = $line -split "\s{2,}"
                if ($parts.Count -ge 2) {
                    $items += [pscustomobject]@{ Manager="winget"; Name=$parts[0]; Id=$parts[1]; Version=($parts[2] -as [string]) }
                }
            }
        }
    }
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        choco list --local-only | ForEach-Object {
            if ($_ -match "^([^|\s]+)\s+(.+)$") {
                $items += [pscustomobject]@{ Manager="choco"; Name=$matches[1]; Id=$matches[1]; Version=$matches[2] }
            }
        }
    }
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop list | Select-Object -Skip 3 | ForEach-Object {
            $parts = $_ -split "\s+"
            if ($parts.Count -ge 1 -and $parts[0]) {
                $items += [pscustomobject]@{ Manager="scoop"; Name=$parts[0]; Id=$parts[0]; Version=($parts[1] -as [string]) }
            }
        }
    }
    $items | Sort-Object Manager,Name -Unique
}

$software = @(Get-InstalledSoftware)
if ($software.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show("No winget/choco/scoop software inventory found.")
    exit 1
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Create Reinstall Script"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"

$list = New-Object System.Windows.Forms.CheckedListBox
$list.Location = New-Object System.Drawing.Point(12, 12)
$list.Size = New-Object System.Drawing.Size(760, 470)
$list.CheckOnClick = $true
foreach ($app in $software) {
    [void]$list.Items.Add(("{0}: {1} [{2}]" -f $app.Manager,$app.Name,$app.Id), $false)
}
$form.Controls.Add($list)

$button = New-Object System.Windows.Forms.Button
$button.Text = "Generate reinstall script"
$button.Location = New-Object System.Drawing.Point(12, 505)
$button.Size = New-Object System.Drawing.Size(190, 34)
$button.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = "PowerShell Script (*.ps1)|*.ps1"
    $dialog.FileName = "reinstall-selected-software.ps1"
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $lines = @(
        "# Generated reinstall script",
        "Set-StrictMode -Version Latest",
        "`$ErrorActionPreference = 'Continue'"
    )
    foreach ($checked in $list.CheckedItems) {
        $idx = $list.Items.IndexOf($checked)
        $app = $software[$idx]
        if ($app.Manager -eq "winget") {
            $lines += "winget install --id `"$($app.Id)`" --accept-package-agreements --accept-source-agreements"
        } elseif ($app.Manager -eq "choco") {
            $lines += "choco install `"$($app.Id)`" -y"
        } elseif ($app.Manager -eq "scoop") {
            $lines += "scoop install `"$($app.Id)`""
        }
    }
    $lines | Out-File -FilePath $dialog.FileName -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show("Created $($dialog.FileName)")
})
$form.Controls.Add($button)

[void]$form.ShowDialog()
