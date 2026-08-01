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
STATE_DIR="${HOME}/.local/state/backups"
STATUS_FILE="${STATE_DIR}/status.json"

die() { echo "backup_desktop: $*" >&2; exit 1; }

# Status file for the proxmox-monitor dashboard to read — this script
# never reads it back or acts on it, it only ever writes its own
# outcome. Written via a trap so a run that fails partway (missing
# restic, network down, restic itself erroring) still records
# "failure" instead of leaving stale/missing status behind.
mkdir -p "${STATE_DIR}"
START_EPOCH="$(date +%s)"

destination_space() {
  # Uses the sftp CLI's built-in `df` (OpenSSH's statvfs@openssh.com
  # extension) over the same restricted account restic already uses
  # — no new credential, no shell needed on the remote end. Prints
  # "total_kb avail_kb" on success, nothing on any failure (best
  # effort: a query failure here must never fail the whole run).
  printf 'df data\n' | sftp -q -b - backup-target 2>/dev/null \
    | awk 'NR==3 {print $1, $3}'
}

write_status() {
  local exit_code="$1"
  local end_epoch
  end_epoch="$(date +%s)"
  local status="success"
  [[ "${exit_code}" -eq 0 ]] || status="failure"

  local size_bytes="null"
  if [[ "${status}" == "success" ]]; then
    size_bytes="$(restic stats latest --json 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("total_size","null"))' 2>/dev/null || echo null)"
  fi

  local dest_total_kb="" dest_avail_kb=""
  read -r dest_total_kb dest_avail_kb < <(destination_space || true)

  python3 - "${status}" "${START_EPOCH}" "${end_epoch}" "${size_bytes}" "${STATUS_FILE}" "${dest_total_kb}" "${dest_avail_kb}" <<'PYEOF'
import json
import sys

status, start_epoch, end_epoch, size_bytes, status_file, dest_total_kb, dest_avail_kb = sys.argv[1:8]
data = {
    "last_run_start": int(start_epoch),
    "last_run_end": int(end_epoch),
    "duration_s": int(end_epoch) - int(start_epoch),
    "status": status,
    "size_bytes": None if size_bytes in ("null", "") else int(size_bytes),
    "dest_total_bytes": int(dest_total_kb) * 1024 if dest_total_kb.isdigit() else None,
    "dest_avail_bytes": int(dest_avail_kb) * 1024 if dest_avail_kb.isdigit() else None,
}
with open(status_file, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
}

trap 'write_status "$?"' EXIT

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
