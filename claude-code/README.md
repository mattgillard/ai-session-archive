# Claude Code Session Archive

Automatically archives Claude Code session files from `~/.claude/projects/` into this directory, preserving the original project structure and file timestamps.

## Files

- `archive.sh` — the archive script
- `archive.log` — run log (appended on each real run)

## Usage

```bash
# Dry run — shows what would be copied without writing anything
./archive.sh --dry-run

# Real run
./archive.sh
```

Sessions are copied with `cp -p` (preserving original timestamps). On subsequent runs, a file is only re-copied if the source is newer than the destination.

## Archive structure

Mirrors `~/.claude/projects/` directly:

```
claude-code-archive/
  -Users-matt/
    <session-uuid>.jsonl
  -Users-matt-dev/
    <session-uuid>.jsonl
  -Users-matt-dev-some-project/
    <session-uuid>.jsonl
    <session-uuid>/
      subagents/
        agent-<id>.jsonl
```

## Scheduled via launchd

The script runs daily at 23:00 via a launchd agent.

**Plist location:**
```
~/Library/LaunchAgents/com.matt.claude-code-archive.plist
```

**Manage the job:**
```bash
# Load / register (survives reboots)
launchctl load ~/Library/LaunchAgents/com.matt.claude-code-archive.plist

# Unload / deregister
launchctl unload ~/Library/LaunchAgents/com.matt.claude-code-archive.plist

# Trigger manually without waiting for 23:00
launchctl start com.matt.claude-code-archive

# Check status
launchctl list | grep claude-code-archive
```
