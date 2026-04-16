#!/usr/bin/env bash
set -euo pipefail

mode="${1:-assisted}"
output_root="${2:-$PWD}"
stamp="$(date +%Y%m%d-%H%M%S)"

if [[ "$mode" == "gui" ]] && command -v zenity >/dev/null 2>&1; then
  output_root="$(zenity --file-selection --directory --title="Select where the disk/drive plan should be created")"
fi

if [[ "$mode" == "assisted" ]]; then
  echo "This workflow inventories disks, checks health signals, and generates reviewable scripts."
  echo "It will not repartition or format anything during diagnosis."
  read -r -p "Press Enter to collect disk and volume information"
fi

out="$output_root/DiskDrivePlan-$stamp"
mkdir -p "$out"

run_log() {
  local name="$1"; shift
  "$@" >"$out/$name" 2>&1 || true
}

run_log lsblk.txt lsblk -f -o NAME,TYPE,FSTYPE,LABEL,UUID,SIZE,FSUSE%,MOUNTPOINTS,MODEL,SERIAL
run_log block_devices.txt bash -c 'for d in /sys/block/*; do echo "== $d =="; cat "$d/size" "$d/removable" 2>/dev/null; done'
if command -v smartctl >/dev/null 2>&1; then
  while read -r dev type; do
    [[ "$type" == "disk" ]] || continue
    run_log "smart_${dev//\//_}.txt" sudo smartctl -a "$dev"
  done < <(lsblk -dn -o PATH,TYPE)
else
  echo "smartctl not installed. Install smartmontools for drive health." >"$out/smart_missing.txt"
fi

{
  echo "Disk/drive recommendations"
  echo "=========================="
  echo "Replace drives that report SMART overall failure, reallocated/pending sectors, media errors, or repeated I/O errors."
  echo "Repartition only after backup/recovery review, especially when partition tables are missing or filesystems are corrupt."
  echo
  grep -RaiE "SMART overall-health|Reallocated|Pending|Media_Wearout|I/O error|failed|corrupt" "$out" || true
} >"$out/recommendations.txt"

if [[ "$mode" == "assisted" ]]; then
  cat "$out/recommendations.txt"
  read -r -p "Press Enter to generate backup, mount, and repartition helper scripts"
fi

cat >"$out/01_backup_before_disk_change.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
src="${1:?source path required}"
dest="${2:?destination path required}"
rsync -aHAX --numeric-ids --info=progress2 "$src"/ "$dest"/
EOF

cat >"$out/02_mount_unmount_examples.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Mount example: sudo mount /dev/sdXN /mnt/recovery"
echo "Unmount example: sudo umount /mnt/recovery"
echo "Readonly mount example: sudo mount -o ro /dev/sdXN /mnt/recovery"
EOF

cat >"$out/03_DESTRUCTIVE_repartition_gpt_ext4.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
disk="${1:?disk path required, example /dev/sdb}"
label="${2:-Data}"
echo "This will erase $disk."
read -r -p "Type WIPE-$disk to continue: " confirm
[[ "$confirm" == "WIPE-$disk" ]] || { echo "Cancelled"; exit 1; }
sudo parted -s "$disk" mklabel gpt
sudo parted -s "$disk" mkpart primary ext4 1MiB 100%
sudo mkfs.ext4 -L "$label" "${disk}1"
EOF

chmod +x "$out"/*.sh
echo "Disk/drive plan created: $out"
cat "$out/recommendations.txt"
