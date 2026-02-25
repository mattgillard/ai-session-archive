#!/usr/bin/env bash
# Archive Claude Code sessions from ~/.claude/projects/ to this directory
# Mirrors the source directory structure, preserving file timestamps

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  DRY_RUN=true
fi

ARCHIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$HOME/.claude/projects"
LOG="$ARCHIVE_DIR/archive.log"

log() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] $*"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
  fi
}

if [[ ! -d "$SOURCE_DIR" ]]; then
  log "ERROR: $SOURCE_DIR not found"
  exit 1
fi

[[ "$DRY_RUN" == true ]] && log "Dry run — no files will be written"

copied=0
skipped=0

while IFS= read -r -d '' file; do
  rel="${file#$SOURCE_DIR/}"
  dest="$ARCHIVE_DIR/$rel"

  if [[ -f "$dest" ]]; then
    # Already archived - skip unless source is newer
    if [[ "$file" -nt "$dest" ]]; then
      log "UPDATE  $dest"
      [[ "$DRY_RUN" == true ]] || cp -p "$file" "$dest"
      ((copied++)) || true
    else
      log "SKIP    $dest (up to date)"
      ((skipped++)) || true
    fi
  else
    log "COPY    $dest"
    if [[ "$DRY_RUN" != true ]]; then
      mkdir -p "$(dirname "$dest")"
      cp -p "$file" "$dest"
    fi
    ((copied++)) || true
  fi
done < <(find "$SOURCE_DIR" -name '*.jsonl' -print0)

log "Done. Copied/updated: $copied, Skipped (up to date): $skipped"
