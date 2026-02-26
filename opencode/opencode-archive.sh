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
session_count=0

while IFS=$'\t' read -r id dir updated; do
  [[ -z "${id:-}" ]] && continue
  ((session_count++)) || true

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
const raw = await Bun.file(process.argv[1]).text()
if (!raw.trim()) {
  throw new Error("empty export payload")
}

let data
try {
  data = JSON.parse(raw)
} catch (err) {
  throw new Error(`invalid export json: ${err?.message ?? err}`)
}

const sessionInfo = data?.info ?? {}
const sessionId = sessionInfo.id ?? "unknown-session"
const sessionCwd = sessionInfo.directory ?? ""
const version = sessionInfo.version ?? "0.0.0"

const toIso = (ms) => new Date(typeof ms === "number" ? ms : Date.now()).toISOString()
const toString = (value) => {
  if (typeof value === "string") return value
  if (value == null) return ""
  try {
    return JSON.stringify(value)
  } catch {
    return String(value)
  }
}

const toTextContent = (text) => ({ type: "text", text: text ?? "" })
const toThinkingContent = (text) => ({ type: "thinking", thinking: text ?? "", signature: null })
const toToolUseContent = (part, fallbackId) => ({
  type: "tool_use",
  id: part.callID ?? part.id ?? fallbackId,
  name: part.tool ?? "tool",
  input: part.state?.input ?? {},
})

const extractContents = (parts, forRole) => {
  if (!Array.isArray(parts)) return []
  const contents = []
  let toolIndex = 0
  for (const part of parts) {
    if (!part || typeof part !== "object") {
      contents.push(toTextContent(toString(part)))
      continue
    }

    if (part.type === "text") {
      contents.push(toTextContent(part.text))
      continue
    }

    if (part.type === "reasoning") {
      if (forRole === "assistant") {
        contents.push(toThinkingContent(part.text))
      } else {
        contents.push(toTextContent(part.text))
      }
      continue
    }

    if (part.type === "tool" && forRole === "assistant") {
      toolIndex += 1
      contents.push(toToolUseContent(part, `tool_${toolIndex}`))
      continue
    }

    if (part.type === "step-start" || part.type === "step-finish") {
      continue
    }

    contents.push(toTextContent(toString(part)))
  }
  return contents
}

const buildBase = (info, timestamp, uuid) => ({
  parentUuid: info?.parentID ?? null,
  isSidechain: false,
  userType: "human",
  cwd: info?.path?.cwd ?? sessionCwd,
  sessionId,
  version,
  uuid,
  timestamp,
})

const entries = []

for (const message of data?.messages ?? []) {
  const info = message?.info ?? {}
  const role = info.role ?? "user"
  const created = info?.time?.created ?? sessionInfo?.time?.created
  const timestamp = toIso(created)
  const uuid = info.id ?? `msg_${entries.length + 1}`

  if (role === "assistant") {
    const content = extractContents(message.parts, "assistant")
    const usage = info.tokens
      ? {
          input_tokens: info.tokens.input ?? null,
          cache_creation_input_tokens: info.tokens.cache?.write ?? null,
          cache_read_input_tokens: info.tokens.cache?.read ?? null,
          output_tokens: info.tokens.output ?? null,
        }
      : null

    entries.push({
      type: "assistant",
      ...buildBase(info, timestamp, uuid),
      requestId: info.requestID ?? null,
      message: {
        id: uuid,
        type: "message",
        role: "assistant",
        model: info.modelID ?? info.model?.modelID ?? "unknown",
        content,
        stop_reason: info.finish ?? null,
        stop_sequence: null,
        usage,
      },
    })

    let toolResultIndex = 0
    for (const part of message.parts ?? []) {
      if (!part || part.type !== "tool") continue
      const toolUseId = part.callID ?? part.id ?? `tool_${toolResultIndex + 1}`
      toolResultIndex += 1

      const status = part.state?.status ?? "completed"
      const isError = status === "error" || Boolean(part.state?.error)
      const output = part.state?.output ?? part.state?.error ?? ""
      const resultText = toString(output)
      const toolTimestamp = toIso(part.state?.time?.end ?? created)
      const toolUuid = `${uuid}-tool-${toolResultIndex}`

      entries.push({
        type: "user",
        ...buildBase({ ...info, parentID: uuid }, toolTimestamp, toolUuid),
        toolUseResult: resultText,
        message: {
          role: "user",
          content: [
            {
              type: "tool_result",
              tool_use_id: toolUseId,
              content: resultText,
              is_error: isError,
            },
          ],
        },
      })
    }

    continue
  }

  const content = extractContents(message.parts, "user")
  entries.push({
    type: "user",
    ...buildBase(info, timestamp, uuid),
    message: {
      role: "user",
      content,
    },
  })
}

const lines = entries.map((entry) => JSON.stringify(entry)).join("\n")
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
done < <(({ opencode db "SELECT id, directory, time_updated AS updated FROM session WHERE time_archived IS NULL ORDER BY time_updated DESC" --format json 2>>"$LOG" || opencode session list --format json 2>>"$LOG"; } | bun -e '
const raw = (await new Response(process.stdin).text()).trim()
if (!raw) process.exit(0)

let sessions
try {
  sessions = JSON.parse(raw)
} catch {
  const lines = raw.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
  const parsed = []
  for (const line of lines) {
    try {
      parsed.push(JSON.parse(line))
    } catch {
      // ignore bad line
    }
  }
  sessions = parsed
}

const emit = (session) => {
  if (!session || typeof session !== "object") return
  const id = session.id
  const directory = session.directory ?? session.path?.cwd ?? session.cwd
  const updatedRaw = session.updated ?? session.time_updated ?? session.time?.updated ?? session.time?.modified
  const updated = Number(updatedRaw)
  if (!id || !directory || !Number.isFinite(updated)) return
  process.stdout.write(`${id}\t${directory}\t${Math.trunc(updated)}\n`)
}

if (Array.isArray(sessions)) {
  for (const session of sessions) emit(session)
  process.exit(0)
}

if (Array.isArray(sessions?.sessions)) {
  for (const session of sessions.sessions) emit(session)
  process.exit(0)
}

throw new Error("unexpected session list format")
' 2>>"$LOG"))

log "Done. Sessions scanned: $session_count, Copied/updated: $copied, Skipped (up to date): $skipped"
