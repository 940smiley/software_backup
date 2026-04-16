#!/usr/bin/env bash
set -euo pipefail
mode="${1:-assisted}"
stamp="$(date +%Y%m%d-%H%M%S)"
out="${TMPDIR:-/tmp}/UbuntuRepair-$stamp"
mkdir -p "$out"
sudo -v

step() {
  local title="$1"; shift
  echo
  echo "=== $title ==="
  if [[ "$mode" == "assisted" ]]; then read -r -p "Press Enter to run this step"; fi
  "$@" 2>&1 | tee "$out/$(echo "$title" | tr ' A-Z/' '_a-z_').log" || true
}

step "ubuntu inventory" bash -c 'lsb_release -a; uname -a; lsblk -f; ubuntu-drivers devices || true'
step "repair dpkg database" sudo dpkg --configure -a
step "fix broken apt dependencies" sudo apt-get -f install -y
step "apt update" sudo apt-get update
step "apt full upgrade" sudo apt-get full-upgrade -y
step "remove unused packages" sudo apt-get autoremove -y
if command -v ubuntu-drivers >/dev/null 2>&1; then
  step "ubuntu recommended driver install" sudo ubuntu-drivers autoinstall
fi
if command -v fwupdmgr >/dev/null 2>&1; then
  step "firmware update check" bash -c 'sudo fwupdmgr refresh --force && sudo fwupdmgr get-updates'
fi
step "filesystem guidance" bash -c 'echo "Boot recovery media before fsck on mounted system partitions."; findmnt -R /'
echo "Ubuntu repair complete. Logs: $out"
