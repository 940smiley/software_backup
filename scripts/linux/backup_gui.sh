#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if command -v zenity >/dev/null 2>&1 || command -v whiptail >/dev/null 2>&1; then
  exec "$SCRIPT_DIR/emergency_backup.sh" "$@"
fi
echo "No GUI helper found. Running terminal backup."
exec "$SCRIPT_DIR/emergency_backup.sh" "$@"
