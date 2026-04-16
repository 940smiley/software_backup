#!/usr/bin/env bash
set -euo pipefail

mode="${1:-assisted}"
stamp="$(date +%Y%m%d-%H%M%S)"
out="${TMPDIR:-/tmp}/LinuxRepair-$stamp"
mkdir -p "$out"

step() {
  local title="$1"; shift
  echo
  echo "=== $title ==="
  if [[ "$mode" == "assisted" ]]; then
    read -r -p "Press Enter to run this step"
  fi
  "$@" 2>&1 | tee "$out/$(echo "$title" | tr ' A-Z/' '_a-z_').log" || true
}

require_sudo() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    sudo -v
  fi
}

require_sudo
step "system inventory" bash -c 'uname -a; lsblk -f; df -hT; free -h'
step "failed services" bash -c 'systemctl --failed --no-pager || true'
step "journal errors" bash -c 'journalctl -p 3 -xb --no-pager | tail -300 || true'

if command -v apt-get >/dev/null 2>&1; then
  step "apt repair package database" sudo dpkg --configure -a
  step "apt fix broken dependencies" sudo apt-get -f install -y
  step "apt update" sudo apt-get update
  step "apt upgrade" sudo apt-get upgrade -y
elif command -v dnf >/dev/null 2>&1; then
  step "dnf upgrade refresh" sudo dnf upgrade --refresh -y
elif command -v yum >/dev/null 2>&1; then
  step "yum update" sudo yum update -y
elif command -v pacman >/dev/null 2>&1; then
  step "pacman system upgrade" sudo pacman -Syu --noconfirm
fi

if command -v fwupdmgr >/dev/null 2>&1; then
  step "firmware update check" bash -c 'sudo fwupdmgr refresh --force && sudo fwupdmgr get-updates'
fi

step "filesystem guidance" bash -c 'echo "Do not fsck mounted filesystems. Boot rescue media, then run: sudo fsck -f /dev/<partition>"; findmnt -R /'
step "driver hints" bash -c 'lspci -nnk || true; lsmod || true; dmesg | grep -Ei "firmware|driver|failed|error" | tail -200 || true'

echo "Repair run complete. Logs: $out"
