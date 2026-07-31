# CLAUDE.md

## Job
Archive stale files out of Downloads; back up the whole PC to Proxmox storage.

## Non-goals
- No AI in the execution path. AI may *review* backup health after the fact, in a separate manual session — it never triggers, selects what to back up, or performs the backup itself. If a request implies AI making a judgment call about what to delete or archive, stop and ask rather than building it — this repo trades cleverness for reliability, on purpose.
- Prefer boring, well-understood tools (`restic`/`borg` + a systemd timer) over building bespoke backup logic.

## Before adding anything
Check it against the Job and Non-goals above. If it doesn't cleanly fit, stop and ask — don't force it in. Full repo map and dependency direction: https://github.com/r-ssa/rafael-systems

## This repo can destroy data if wrong. Extra rules:
- `main` should be branch-protected, but GitHub Pro is required for that on a private repo — not yet active. Until it is, treat this as an honor rule: work on a branch + PR for the user to read, never push directly to `main`, even though nothing currently blocks it.
- Any archival/deletion logic defaults to dry-run and requires an explicit confirm step before it deletes or moves anything for real. No exceptions, even for "obviously safe" cases.
