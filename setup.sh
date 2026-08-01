#!/usr/bin/env bash
set -euo pipefail

# setup.sh — wires up the SSH alias this repo's scripts depend on.
# The actual backup-agent SSH key and the Proxmox-side account are
# provisioned separately (see BUILD_PLAN.md Phase 2) — this just
# points the local SSH config at them.

read -rp "Proxmox host/IP: " host
read -rp "Path to the backup-agent private key [~/.ssh/backup_agent_ed25519]: " key
key="${key:-${HOME}/.ssh/backup_agent_ed25519}"

mkdir -p "${HOME}/.ssh/config.d"
cat > "${HOME}/.ssh/config.d/backups" <<EOF
Host backup-target
  HostName ${host}
  User backup-agent
  IdentityFile ${key}
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
chmod 600 "${HOME}/.ssh/config.d/backups"

if [[ -f "${HOME}/.ssh/config" ]] && ! grep -qE '^\s*Include\s+config\.d/\*' "${HOME}/.ssh/config"; then
  echo "NOTE: ~/.ssh/config does not Include config.d/* — add that as its first line."
elif [[ ! -f "${HOME}/.ssh/config" ]]; then
  echo "Include config.d/*" > "${HOME}/.ssh/config"
  chmod 600 "${HOME}/.ssh/config"
fi

echo "Wrote ${HOME}/.ssh/config.d/backups"
echo "Test with: ssh backup-target (should say 'sftp connections only', not fail to connect)"
