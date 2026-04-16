# Software Backup Toolkit

Cross-platform launch scripts for fast personal-data backups, software inventory,
reinstall script generation, repair workflows, and disk/drive diagnostics.

This toolkit is designed for emergency use:

- Back up important user data only.
- Avoid copying caches, downloads that can be redownloaded, build artifacts,
  package stores, virtual machines, and other reproducible bulk data.
- Log reproducible state instead, including installed software, drivers, system
  details, package lists, and storage layout.
- Generate destructive disk/partition actions as reviewable scripts instead of
  silently running them.

## Quick Start

### Windows

Right-click and run as administrator when using repair or disk workflows.

- `launchers\run_windows_emergency_backup.cmd`
- `launchers\run_windows_backup_gui.cmd`
- `launchers\run_windows_software_reinstall_gui.cmd`
- `launchers\run_windows_troubleshoot.cmd`
- `launchers\run_windows_disk_drive_assistant.cmd`

### Generic Linux

```bash
chmod +x launchers/*.sh scripts/linux/*.sh scripts/ubuntu/*.sh
./launchers/run_linux_emergency_backup.sh
```

### Ubuntu-Focused

```bash
chmod +x launchers/*.sh scripts/ubuntu/*.sh
./launchers/run_ubuntu_emergency_backup.sh
```

## Backup Output

Backups are written to a timestamped folder:

```text
SoftwareBackup-YYYYMMDD-HHMMSS/
  data/
  logs/
  manifests/
  generated/
```

`data/` contains copied unique files. `logs/` contains installed software,
drivers, OS details, package state, storage layout, and skipped/reproducible
paths. `manifests/` contains hashes and source-to-backup mappings.

## Safety Notes

- Disk and partition scripts diagnose first and generate scripts for review.
- Repartitioning scripts are generated with warnings and confirmations.
- Repair scripts use OS-native tools and avoid formatting drives.
- Always inspect generated disk scripts before running them.
