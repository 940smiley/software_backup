#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp)"
selected="$(mktemp)"
trap 'rm -f "$tmp" "$selected"' EXIT

if command -v dpkg-query >/dev/null 2>&1; then
  dpkg-query -W -f='apt\t${binary:Package}\t${Version}\n' >>"$tmp"
fi
if command -v rpm >/dev/null 2>&1; then
  rpm -qa --qf 'rpm\t%{NAME}\t%{VERSION}\n' >>"$tmp"
fi
if command -v pacman >/dev/null 2>&1; then
  pacman -Qqe | awk '{print "pacman\t"$1"\t"}' >>"$tmp"
fi
if command -v flatpak >/dev/null 2>&1; then
  flatpak list --app --columns=application | awk '{print "flatpak\t"$1"\t"}' >>"$tmp"
fi
if command -v snap >/dev/null 2>&1; then
  snap list | awk 'NR>1 {print "snap\t"$1"\t"$2}' >>"$tmp"
fi

if [[ ! -s "$tmp" ]]; then
  echo "No supported package manager inventory found." >&2
  exit 1
fi

if command -v zenity >/dev/null 2>&1; then
  args=()
  while IFS=$'\t' read -r mgr name version; do
    args+=(FALSE "$mgr" "$name" "$version")
  done <"$tmp"
  zenity --list --checklist --separator=$'\t' --width=900 --height=600 \
    --title="Select software to reinstall" \
    --column="Install" --column="Manager" --column="Package" --column="Version" \
    "${args[@]}" >"$selected"
else
  nl -w1 -s': ' "$tmp"
  echo "Enter package numbers separated by spaces:"
  read -r picks
  for n in $picks; do sed -n "${n}p" "$tmp"; done >"$selected"
fi

out="${PWD}/reinstall-selected-software.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  while IFS=$'\t' read -r mgr name version _; do
    case "$mgr" in
      apt) echo "sudo apt-get install -y '$name'" ;;
      rpm) echo "sudo dnf install -y '$name' || sudo yum install -y '$name'" ;;
      pacman) echo "sudo pacman -S --needed '$name'" ;;
      flatpak) echo "flatpak install -y flathub '$name'" ;;
      snap) echo "sudo snap install '$name'" ;;
    esac
  done <"$selected"
} >"$out"
chmod +x "$out"
echo "Created $out"
