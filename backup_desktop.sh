#!/usr/bin/env bash
set -euo pipefail

# backup_desktop.sh — Phase 3. Whole-PC backup via restic, pushed to
# the Proxmox-side destination over the restricted SFTP-only account
# set up for exactly this purpose.
#
# Retention (7 daily + 4 weekly) is enforced by restic's own
# forget/prune, not hand-rolled logic.
#
# The repository password is itself a credential — stored the same way
# as every other secret in this project: local file, mode 600,
# gitignored.

CONFIG_DIR="${HOME}/.config/backups"
PASSWORD_FILE="${CONFIG_DIR}/restic-password"
EXCLUDE_FILE="${CONFIG_DIR}/excludes.txt"
REPO="sftp:backup-target:data"

die() { echo "backup_desktop: $*" >&2; exit 1; }

command -v restic >/dev/null || die "restic not installed"

if [[ ! -f "${PASSWORD_FILE}" ]]; then
  mkdir -p "${CONFIG_DIR}"
  # Subshell: umask must not leak past this block. It did once, during
  # development — it silently applied to everything restic created
  # afterward, including its cache directory, which then couldn't even
  # be read back by its own owner (mode 600 on a directory has no
  # execute bit, so it's unenterable). Found by actually running this,
  # not by review.
  (
    umask 177
    head -c 32 /dev/urandom | base64 > "${PASSWORD_FILE}"
  )
  chmod 600 "${PASSWORD_FILE}"
  echo "backup_desktop: generated a new repository password at ${PASSWORD_FILE}" >&2
  echo "backup_desktop: BACK THIS FILE UP SEPARATELY — losing it means losing the ability to restore anything, even though the backup data itself is intact." >&2
fi

if [[ ! -f "${EXCLUDE_FILE}" ]]; then
  mkdir -p "${CONFIG_DIR}"
  cat > "${EXCLUDE_FILE}" <<'EOF'
# Reviewed with the user before the first real run (Phase 3 STOP).
# One pattern per line, relative to $HOME unless absolute.
.cache/
.local/share/Trash/
**/node_modules/
**/__pycache__/
**/target/
**/.venv/
*.tmp
EOF
  echo "backup_desktop: wrote default excludes to ${EXCLUDE_FILE} — review before relying on this." >&2
fi

export RESTIC_REPOSITORY="${REPO}"
export RESTIC_PASSWORD_FILE="${PASSWORD_FILE}"

if ! restic snapshots >/dev/null 2>&1; then
  echo "backup_desktop: repository not initialized yet — initializing now."
  restic init
fi

echo "backup_desktop: starting backup of ${HOME}..."
restic backup "${HOME}" \
  --exclude-file="${EXCLUDE_FILE}" \
  --exclude-caches \
  --one-file-system \
  --tag=desktop

echo "backup_desktop: enforcing retention (7 daily, 4 weekly)..."
restic forget --keep-daily 7 --keep-weekly 4 --prune

echo "backup_desktop: done."
