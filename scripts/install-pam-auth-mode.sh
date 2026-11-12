#!/usr/bin/env bash
# Safely install explicit password/fingerprint PAM mode selection rules into
# /etc/pam.d/swaylock and/or /etc/pam.d/greetd without touching system-auth,
# sudo, polkit-1, or sshd.

set -euo pipefail

readonly SELECTOR_LINE='auth       [success=ignore default=1] pam_auth_mode_selector.so'
readonly FPRINT_LINE='auth       [success=done default=die] pam_fprintd.so max-tries=1 timeout=10'
readonly BACKUP_ROOT=/var/backups/fprint-auth-mode
readonly STATE_ROOT=/var/lib/fprint-auth-mode
readonly STAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR="$BACKUP_ROOT/$STAMP"

if (( EUID != 0 )); then
  echo "Error: this script must run as root." >&2
  exit 1
fi

if [[ ! -x /usr/lib/security/pam_auth_mode_selector.so ]]; then
  echo "Error: /usr/lib/security/pam_auth_mode_selector.so not found. Install pam-auth-mode-selector first." >&2
  exit 1
fi

if [[ ! -x /usr/lib/security/pam_fprintd.so ]]; then
  echo "Error: /usr/lib/security/pam_fprintd.so not found. Install fprintd first." >&2
  exit 1
fi

targets=("$@")
if (( ${#targets[@]} == 0 )); then
  for candidate in swaylock greetd; do
    if [[ -r "/etc/pam.d/$candidate" ]]; then
      targets+=("$candidate")
    fi
  done
fi

if (( ${#targets[@]} == 0 )); then
  echo "Error: neither /etc/pam.d/swaylock nor /etc/pam.d/greetd exists." >&2
  exit 2
fi

for service in "${targets[@]}"; do
  case "$service" in
    swaylock|greetd) ;;
    *)
      echo "Error: unsupported PAM service '$service' (supported: swaylock, greetd)." >&2
      exit 2
      ;;
  esac

  file="/etc/pam.d/$service"
  if [[ ! -r "$file" ]]; then
    echo "Error: $file does not exist." >&2
    exit 2
  fi

  if grep -qE 'pam_auth_mode_selector\.so|pam_fprintd\.so' "$file"; then
    echo "Error: $file already contains pam_auth_mode_selector or pam_fprintd; refusing to duplicate." >&2
    exit 3
  fi

  if [[ "$service" == "greetd" ]] && [[ $(grep -Ec '^auth[[:space:]]+requisite[[:space:]]+pam_nologin\.so' "$file") -ne 1 ]]; then
    echo "Error: unexpected /etc/pam.d/greetd layout (missing unique pam_nologin.so line)." >&2
    exit 4
  fi

  if [[ "$service" == "swaylock" ]] && [[ $(grep -Ec '^auth[[:space:]]+include[[:space:]]+login' "$file") -ne 1 ]]; then
    echo "Error: unexpected /etc/pam.d/swaylock layout (missing unique 'auth include login' line)." >&2
    exit 4
  fi
done

install -d -o root -g root -m 0700 "$BACKUP_DIR" "$STATE_ROOT"

tmp_files=()
cleanup() {
  for f in "${tmp_files[@]:-}"; do
    [[ -n "$f" ]] && rm -f "$f"
  done
}
trap cleanup EXIT

for service in "${targets[@]}"; do
  file="/etc/pam.d/$service"
  install -o root -g root -m 0600 "$file" "$BACKUP_DIR/$service"

  tmp=$(mktemp)
  tmp_files+=("$tmp")

  if [[ "$service" == "greetd" ]]; then
    awk -v sel="$SELECTOR_LINE" -v fp="$FPRINT_LINE" '
      /^auth[[:space:]]+requisite[[:space:]]+pam_nologin\.so/ {
        print
        print sel
        print fp
        next
      }
      { print }
    ' "$file" > "$tmp"
  else
    awk -v sel="$SELECTOR_LINE" -v fp="$FPRINT_LINE" '
      /^auth[[:space:]]+include[[:space:]]+login/ {
        print sel
        print fp
        print
        next
      }
      { print }
    ' "$file" > "$tmp"
  fi

  [[ $(grep -Fxc "$SELECTOR_LINE" "$tmp") -eq 1 ]]
  [[ $(grep -Fxc "$FPRINT_LINE" "$tmp") -eq 1 ]]
  install -o root -g root -m 0644 "$tmp" "$file"
  echo "Configured /etc/pam.d/$service"
done

printf '%s\n' "$BACKUP_DIR" > "$STATE_ROOT/active-pam-backup"
chmod 0600 "$STATE_ROOT/active-pam-backup"

echo "Backup saved to: $BACKUP_DIR"
