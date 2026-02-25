# AI Session Archive

Scripts for archiving local AI coding assistant sessions to a persistent directory. Each script runs incrementally — only copying or exporting sessions that are new or updated since the last run.

## Tools

| Directory | Tool | Script |
|-----------|------|--------|
| [`claude-code/`](./claude-code/) | [Claude Code](https://claude.ai/code) | `archive.sh` |
| [`opencode/`](./opencode/) | [opencode](https://opencode.ai) | `opencode-archive.sh` |

## Scheduling

Both scripts are scheduled via launchd to run daily at 23:00. See each tool's README for plist paths and `launchctl` commands.

## Dry run

Both scripts support `--dry-run` / `-n` to preview what would be copied without writing anything.
