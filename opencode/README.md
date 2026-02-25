# OpenCode Session Archive

This directory stores exported OpenCode sessions in a JSONL format similar to the Claude Code archive.

## Files

- `opencode-archive.sh`: Export script.
- `opencode-archive.log`: Run log output.
- `-Users-.../`: Per-project slug directories with session JSONL files.

## Manual runs

Run the export:

```bash
bash ~/dev/opencode-archive/opencode-archive.sh
```

Dry run:

```bash
bash ~/dev/opencode-archive/opencode-archive.sh --dry-run
```

## Launchd schedule

LaunchAgent file:

- `~/Library/LaunchAgents/com.<username>.opencode-archive.plist`

Default schedule: daily at 23:00.

Useful commands:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.<username>.opencode-archive.plist
launchctl enable gui/$(id -u)/com.<username>.opencode-archive
launchctl kickstart -k gui/$(id -u)/com.<username>.opencode-archive

launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.<username>.opencode-archive.plist
```

## Notes

- The script exports sessions via `opencode export` and writes JSONL to `-Users-.../<session-id>.jsonl`.
- File mtime is set to the session `updated` timestamp.
- Sessions are skipped when the archive file is already up to date.
