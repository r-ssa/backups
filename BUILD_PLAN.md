# BUILD_PLAN.md

Same discipline as proxmox-ops: phases in order, explicit STOPs, no
skipping ahead. This repo's job is narrower and lower-risk in one
direction (no AI in the execution path, ever) but higher-risk in
another (it can lose data if wrong) — so "boring and correct" beats
"clever" at every decision point here.

## Assumptions made instead of asking (correct any that are wrong)

- Backup destination: the Proxmox `local` storage's backup directory
  (confirmed to exist and be flagged `content=backup` — not invented),
  in a dedicated `desktop-backups/` subfolder so this never collides
  with Proxmox's own vzdump archives.
- Retention: 7 daily + 4 weekly.
- Downloads archival threshold: untouched 30+ days, moved (never
  deleted) to `~/Downloads/Archive/YYYY-MM/`.

## PHASE 1 — Downloads archival

Goal: declutter Downloads without ever deleting anything.

Steps:
- Dry-run default, same as every mutating script tonight.
- Move-only, never delete. A move is trivially reversible; the point
  of "archival" is organization, not cleanup-by-deletion.
- Never touch a file currently open/locked by another process (skip,
  don't force).

STOP: none required — this is local-only, reversible, and needs no new
credentials. Still gets a PR, still gets read before merge, since
"low-risk" isn't the same as "unreviewed."

## PHASE 2 — Prerequisite: scoped backup credential

Goal: a dedicated, narrowly-scoped way to reach the Proxmox-side
destination — not root, not the user's personal SSH key.

STOP: this needs a real decision, not an assumption. Proposed design,
confirm or correct: a dedicated system user on the Proxmox host (e.g.
`backup-agent`), SSH key-only auth, restricted via
`command="rsync --server ..."` in `authorized_keys` (or sshd
`ChrootDirectory` + `internal-sftp`) so that even if the key leaked,
it could only read/write inside `desktop-backups/` — nothing else on
the host is reachable through it.

## PHASE 3 — Whole-PC backup

Goal: `restic` (or `borg`), pushing to the Phase 2 destination, on a
schedule.

Steps:
- Sensible default excludes (caches, `node_modules`-style build
  artifacts, anything already gitignored at the top level) — reviewed
  with the user before the first real run, not assumed silently.
- Retention policy (Phase 0 assumption: 7 daily + 4 weekly) enforced
  via the tool's own prune/forget mechanism, not hand-rolled.
- systemd timer, not cron — consistent with everything else in this
  project.

STOP: first real backup run gets watched, not fired-and-forgotten —
confirm it completes, confirm a restore actually works before trusting
the timer to run unattended.

## PHASE 4 — Restore verification

Goal: prove a restore works before this is ever relied on in a real
emergency. A backup nobody has ever restored from isn't a backup.

STOP: run and confirm an actual test restore before this repo is
considered done.
