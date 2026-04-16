#!/usr/bin/env bash
set -euo pipefail

timestamp="$(date +%Y%m%d-%H%M%S)"

choose_destination() {
  if [[ "${1:-}" != "" ]]; then
    printf '%s\n' "$1"
    return
  fi
  if command -v zenity >/dev/null 2>&1; then
    zenity --file-selection --directory --title="Select backup drive or folder"
    return
  fi
  if command -v whiptail >/dev/null 2>&1; then
    whiptail --inputbox "Enter backup drive/folder path" 10 70 "/media/$USER" 3>&1 1>&2 2>&3
    return
  fi
  read -r -p "Backup drive/folder path: " dest
  printf '%s\n' "$dest"
}

is_reproducible() {
  case "$1" in
    */.cache/*|*/Cache/*|*/node_modules/*|*/.git/*|*/.svn/*|*/.hg/*|*/target/*|*/dist/*|*/build/*|*/__pycache__/*|*/.venv/*|*/venv/*|*/Downloads/*|*/.npm/*|*/.cargo/registry/*|*/.gradle/caches/*)
      return 0 ;;
    *) return 1 ;;
  esac
}

log_command() {
  local output="$1"; shift
  if command -v "$1" >/dev/null 2>&1; then
    "$@" >"$output" 2>&1 || true
  else
    printf '%s not found\n' "$1" >"$output"
  fi
}

dest="$(choose_destination "${1:-}")"
mkdir -p "$dest"
backup_root="$dest/SoftwareBackup-$timestamp"
data_dir="$backup_root/data"
logs_dir="$backup_root/logs"
manifest_dir="$backup_root/manifests"
generated_dir="$backup_root/generated"
mkdir -p "$data_dir" "$logs_dir" "$manifest_dir" "$generated_dir"

sources=(
  "$HOME/Desktop"
  "$HOME/Documents"
  "$HOME/Pictures"
  "$HOME/Videos"
  "$HOME/Music"
  "$HOME/.ssh"
  "$HOME/.gnupg"
  "$HOME/.config"
  "$HOME/.local/share/applications"
)

printf '%s\n' "${sources[@]}" >"$logs_dir/selected_sources.txt"
uname -a >"$logs_dir/uname.txt" || true
log_command "$logs_dir/lsblk.txt" lsblk -f -o NAME,FSTYPE,LABEL,UUID,SIZE,FSUSE%,MOUNTPOINTS,MODEL,SERIAL
log_command "$logs_dir/lspci.txt" lspci -nnk
log_command "$logs_dir/lsusb.txt" lsusb
log_command "$logs_dir/dmesg_storage_tail.txt" dmesg -T
log_command "$logs_dir/systemd_failed.txt" systemctl --failed --no-pager
log_command "$logs_dir/dpkg_packages.txt" dpkg-query -W -f='${binary:Package}\t${Version}\n'
log_command "$logs_dir/rpm_packages.txt" rpm -qa
log_command "$logs_dir/pacman_packages.txt" pacman -Qqe
log_command "$logs_dir/flatpak_apps.txt" flatpak list --app
log_command "$logs_dir/snap_apps.txt" snap list

manifest="$manifest_dir/copied_unique_files.tsv"
skipped="$manifest_dir/skipped_reproducible_or_errors.tsv"
dupes="$manifest_dir/duplicates_logged_not_copied.tsv"
hash_index="$manifest_dir/hash_index.tsv"
: >"$hash_index"
printf 'hash\tsource\tdestination\tbytes\tmodified_epoch\n' >"$manifest"
printf 'reason\tpath\n' >"$skipped"
printf 'hash\tduplicate_source\tkept_destination\n' >"$dupes"

for root in "${sources[@]}"; do
  [[ -e "$root" ]] || continue
  root_name="$(printf '%s' "$root" | sed "s#^$HOME#HOME#; s#[/:]#_#g")"
  while IFS= read -r -d '' file; do
    if is_reproducible "$file"; then
      printf 'reproducible_or_cache\t%s\n' "$file" >>"$skipped"
      continue
    fi
    if ! hash="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"; then
      printf 'hash_error\t%s\n' "$file" >>"$skipped"
      continue
    fi
    existing="$(awk -F '\t' -v h="$hash" '$1 == h { print $2; exit }' "$hash_index")"
    if [[ "$existing" != "" ]]; then
      printf '%s\t%s\t%s\n' "$hash" "$file" "$existing" >>"$dupes"
      continue
    fi
    rel="${file#"$root"/}"
    target="$data_dir/$root_name/$rel"
    mkdir -p "$(dirname "$target")"
    if cp -p "$file" "$target" 2>/dev/null; then
      size="$(stat -c %s "$file" 2>/dev/null || printf '0')"
      mtime="$(stat -c %Y "$file" 2>/dev/null || printf '0')"
      printf '%s\t%s\n' "$hash" "$target" >>"$hash_index"
      printf '%s\t%s\t%s\t%s\t%s\n' "$hash" "$file" "$target" "$size" "$mtime" >>"$manifest"
    else
      printf 'copy_error\t%s\n' "$file" >>"$skipped"
    fi
  done < <(find "$root" -xdev -type f -print0 2>/dev/null)
done

printf 'Backup complete: %s\n' "$backup_root" | tee "$backup_root/BACKUP_COMPLETE.txt"
