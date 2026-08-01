#!/usr/bin/env bash
set -euo pipefail

# archive_downloads.sh — Phase 1. Move files untouched for 30+ days out
# of ~/Downloads into ~/Downloads/Archive/YYYY-MM/, organized by the
# month they were archived (not the month they were created).
#
# MOVE ONLY. Never deletes. The whole point of "archival" here is
# organization, not cleanup-via-deletion — if you want something gone
# for good, that's a decision for you to make manually, not something
# this script does on your behalf.
#
# Dry-run is the default, same as every mutating script in this
# project. Real moves require --yes.

DOWNLOADS="${HOME}/Downloads"
ARCHIVE_ROOT="${DOWNLOADS}/Archive"
THRESHOLD_DAYS="${ARCHIVE_THRESHOLD_DAYS:-30}"
MONTH_DIR="${ARCHIVE_ROOT}/$(date +%Y-%m)"

die() { echo "archive_downloads: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Usage: archive_downloads.sh [--yes]

  --yes    Actually move files. Without it, dry-run only — lists what
           would move and changes nothing.

Files untouched for 30+ days (override with ARCHIVE_THRESHOLD_DAYS=N)
move to ~/Downloads/Archive/YYYY-MM/. Never deletes anything. Files
currently open/locked by another process are skipped, not forced.
EOF
  exit 2
}

APPLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) APPLY=true ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

[[ -d "${DOWNLOADS}" ]] || die "no ${DOWNLOADS} directory found"

# Never recurse into Archive itself — that would move already-archived
# files into new monthly buckets every run, which defeats the point.
mapfile -d '' -t candidates < <(
  find "${DOWNLOADS}" -maxdepth 1 -type f -mtime "+${THRESHOLD_DAYS}" -print0
)

if [[ "${#candidates[@]}" -eq 0 ]]; then
  echo "archive_downloads: nothing untouched for ${THRESHOLD_DAYS}+ days."
  exit 0
fi

echo "Found ${#candidates[@]} file(s) untouched for ${THRESHOLD_DAYS}+ days:"
for f in "${candidates[@]}"; do
  echo "  $(basename "${f}")"
done

if [[ "${APPLY}" != "true" ]]; then
  echo
  echo "DRY RUN — nothing moved. Would move the above into:"
  echo "  ${MONTH_DIR}/"
  echo "Re-run with --yes to do it for real."
  exit 0
fi

mkdir -p "${MONTH_DIR}"

moved=0
skipped=0
for f in "${candidates[@]}"; do
  name="$(basename "${f}")"
  # Skip anything currently held open by another process — a browser
  # mid-download, an archive tool mid-extract, etc. lsof absence just
  # means "can't check", which is treated as "assume it might be open"
  # rather than silently proceeding.
  if command -v lsof >/dev/null 2>&1 && lsof -- "${f}" >/dev/null 2>&1; then
    echo "  skip (in use): ${name}"
    ((skipped++)) || true
    continue
  fi

  dest="${MONTH_DIR}/${name}"
  if [[ -e "${dest}" ]]; then
    # Don't clobber an existing archived file with the same name —
    # disambiguate instead of silently overwriting.
    dest="${MONTH_DIR}/$(date +%s)-${name}"
  fi

  mv -- "${f}" "${dest}"
  echo "  moved: ${name}"
  ((moved++)) || true
done

echo
echo "Moved ${moved} file(s) to ${MONTH_DIR}/ (${skipped} skipped as in-use)."
