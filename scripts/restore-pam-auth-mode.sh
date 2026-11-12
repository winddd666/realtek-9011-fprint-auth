#!/usr/bin/env bash
# Restore original /etc/pam.d/ files backed up by install-pam-auth-mode.sh.

set -euo pipefail

readonly STATE_FILE=/var/lib/fprint-auth-mode/active-pam-backup

if (( EUID != 0 )); then
  echo "Error: this script must run as root." >&2
  exit 1
fi

backup_dir="${1:-}"
if [[ -z "$backup_dir" ]]; then
  if [[ ! -r "$STATE_FILE" ]]; then
    echo "Error: $STATE_FILE not found. Pass the backup directory explicitly." >&2
    exit 1
  fi
  backup_dir=$(<"$STATE_FILE")
fi

case "$backup_dir" in
  /var/backups/fprint-auth-mode/*) ;;
  *)
    echo "Error: invalid backup path '$backup_dir'." >&2
    exit 2
    ;;
esac

restored=0
for service in swaylock greetd; do
  if [[ -f "$backup_dir/$service" ]]; then
    install -o root -g root -m 0644 "$backup_dir/$service" "/etc/pam.d/$service"
    echo "Restored /etc/pam.d/$service"
    restored=1
  fi
done

if (( restored == 0 )); then
  echo "Error: no PAM backup files found in $backup_dir" >&2
  exit 3
fi

echo "PAM configuration restored from $backup_dir"
