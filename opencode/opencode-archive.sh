#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_ROOT="$HOME/dev/opencode-archive"
LOG="$ARCHIVE_ROOT/opencode-archive.log"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    -n|--dry-run)
      DRY_RUN=1
      ;;
    *)
      ;;
  esac
done

mkdir -p "$ARCHIVE_ROOT"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"
}

opencode session list --format json 2>>"$LOG" | bun -e '
const sessions = await new Response(process.stdin).json()
for (const s of sessions) {
  process.stdout.write(`${s.id}\t${s.directory}\t${s.updated}\n`)
}
' | while IFS=$'\t' read -r id dir updated; do
  slug="-${dir#/}"
  slug="${slug//\//-}"
  destDir="$ARCHIVE_ROOT/$slug"
  dest="$destDir/$id.jsonl"
  mkdir -p "$destDir"

  if [[ -f "$dest" ]]; then
    mtime=$(stat -f %m "$dest")
    if (( updated / 1000 <= mtime )); then
      log "SKIP    $dest (up to date)"
      continue
    fi
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRYRUN  $dest"
    continue
  fi

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

  touch -t "$(date -r "$((updated / 1000))" "+%Y%m%d%H%M.%S")" "$dest"

  log "WRITE   $dest"
done
