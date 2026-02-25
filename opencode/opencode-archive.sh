#!/usr/bin/env bash
# Archive opencode sessions to this directory
# Requires bun and the opencode CLI
set -euo pipefail

ARCHIVE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$ARCHIVE_ROOT/opencode-archive.log"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    -n|--dry-run)
      DRY_RUN=true
      ;;
    *)
      ;;
  esac
done

file_mtime() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    stat -f %m "$1"
  else
    stat -c %Y "$1"
  fi
}

epoch_to_touch() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    date -r "$1" "+%Y%m%d%H%M.%S"
  else
    date -d "@$1" "+%Y%m%d%H%M.%S"
  fi
}

log() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] $*"
  else
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"
  fi
}

[[ "$DRY_RUN" == true ]] && log "Dry run — no files will be written"

copied=0
skipped=0

while IFS=$'\t' read -r id dir updated; do
  slug="-${dir#/}"
  slug="${slug//\//-}"
  destDir="$ARCHIVE_ROOT/$slug"
  dest="$destDir/$id.jsonl"

  if [[ -f "$dest" ]]; then
    mtime=$(file_mtime "$dest")
    if (( updated / 1000 <= mtime )); then
      log "SKIP    $dest (up to date)"
      ((skipped++)) || true
      continue
    fi
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log "DRYRUN  $dest"
    ((copied++)) || true
    continue
  fi

  mkdir -p "$destDir"

  tmpjson="$(mktemp "$destDir/.opencode-archive.XXXXXX.json")"
  tmp="$(mktemp "$destDir/.opencode-archive.XXXXXX")"
  if ! opencode export "$id" > "$tmpjson" 2>>"$LOG"; then
    rm -f "$tmpjson" "$tmp"
    log "ERROR   export failed: $id"
    continue
  fi

  if ! bun -e '
const data = await Bun.file(process.argv[1]).json()
const lines = [
  { type: "session", info: data.info },
  ...data.messages.map(m => ({ type: "message", info: m.info, parts: m.parts })),
].map(JSON.stringify).join("\n")
process.stdout.write(lines + "\n")
' "$tmpjson" > "$tmp"; then
    rm -f "$tmpjson" "$tmp"
    log "ERROR   invalid json: $id"
    continue
  fi

  rm -f "$tmpjson"
  mv "$tmp" "$dest"

  touch -t "$(epoch_to_touch "$((updated / 1000))")" "$dest"

  log "WRITE   $dest"
  ((copied++)) || true
done < <(opencode session list --format json 2>>"$LOG" | bun -e '
const sessions = await new Response(process.stdin).json()
for (const s of sessions) {
  process.stdout.write(`${s.id}\t${s.directory}\t${s.updated}\n`)
}
')

log "Done. Copied/updated: $copied, Skipped (up to date): $skipped"
