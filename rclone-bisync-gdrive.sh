#!/bin/bash
# Safe bidirectional sync: PC <-> Google Drive
# Deletions propagate both ways, but with safety nets
#
# Usage:
#   1. Set environment variables (LOCAL, REMOTE, etc.) or use .env file
#   2. Run manually for first sync: ./rclone-bisync-gdrive.sh --first-run
#   3. For periodic runs: ./rclone-bisync-gdrive.sh
#
# NOTE: First run requires --resync flag. Periodic runs must NOT use --resync.

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

# Local directory to sync (absolute path)
LOCAL=$LOCAL

# Google Drive remote and path (format: remote:path)
REMOTE=$REMOTE

# State file - tracks sync history between runs
# CRITICAL: Never delete this file or bisync will resync everything
STATE_DIR=${XDG_DATA_HOME:-"$HOME/.local/share"}/rclone-bisync-gdrive
STATE_FILE=${STATE_FILE:-"$STATE_DIR/state.json"}

# Backup directories - MUST be outside LOCAL and REMOTE paths
# BACKUP_DIR_LOCAL: local path for LOCAL backups
# BACKUP_DIR_REMOTE: remote:path for REMOTE backups
BACKUP_DIR_LOCAL=${BACKUP_DIR_LOCAL:-}
BACKUP_DIR_REMOTE=${BACKUP_DIR_REMOTE:-}

# Validate required variables
if [ -z "$LOCAL" ] || [ -z "$REMOTE" ]; then
    echo "ERROR: LOCAL and REMOTE must be specified" >&2
    echo "Set them via environment variables or .env file" >&2
    exit 1
fi

# Validate at least one backup directory is set
if [ -z "$BACKUP_DIR_LOCAL" ] && [ -z "$BACKUP_DIR_REMOTE" ]; then
    echo "ERROR: At least one of BACKUP_DIR_LOCAL or BACKUP_DIR_REMOTE must be specified" >&2
    echo "These are the backup locations for LOCAL and REMOTE paths respectively" >&2
    echo "Set them via environment variables or .env file" >&2
    exit 1
fi

# Log file for sync operations
LOG_DIR=${XDG_CACHE_HOME:-"$HOME/.cache"}/rclone-bisync-gdrive
LOG_FILE=${LOG_FILE:-"$LOG_DIR/log"}

# Ensure directories exist
mkdir -p "$STATE_DIR" "$LOG_DIR"

# Lock file to prevent overlapping runs
LOCK_FILE=${LOCK_FILE:-'/tmp/rclone-bisync-gdrive.lock'}

# Conflict resolution: newest, oldest, path1, path2
# - newest: keep file with latest modification time (recommended)
# - oldest: keep file with earliest modification time
# - path1: always prefer local version
# - path2: always prefer remote version
CONFLICT_RESOLVE=${CONFLICT_RESOLVE:-'newest'}

# Maximum number of files allowed to be deleted in one run
# Safety feature: aborts if more than this count would be deleted
MAX_DELETE_COUNT=${MAX_DELETE_COUNT:-10}

# Suffix for conflict files (supports {DateOnly}, {Time}, etc.)
CONFLICT_SUFFIX=${CONFLICT_SUFFIX:-"-{DateTime}-conflict"}

# =============================================================================

# Check if first run flag is set
FIRST_RUN=false
for arg in "$@"; do
    if [ "$arg" = "--first-run" ] || [ "$arg" = "--resync" ]; then
        FIRST_RUN=true
    fi
done

# Safety: prevent overlapping runs
if [ -f "$LOCK_FILE" ]; then
    echo "$(date): Sync already in progress (PID: $(cat $LOCK_FILE)). Exiting." >> "$LOG_FILE"
    echo "WARNING: Sync already in progress. If this is unexpected, check for stuck processes."
    exit 0
fi
echo $$ > "$LOCK_FILE"

# Cleanup lock file on exit
trap 'rm -f "$LOCK_FILE"' EXIT

echo "$(date): Starting bisync" >> "$LOG_FILE"

# Build the bisync command
BISYNC_CMD="rclone bisync \"$LOCAL\" \"$REMOTE\" \"$STATE_FILE\""

# Add flags
if [ -n "$BACKUP_DIR_LOCAL" ]; then
    BISYNC_CMD+=" --backup-dir1 \"$BACKUP_DIR_LOCAL\""
fi
if [ -n "$BACKUP_DIR_REMOTE" ]; then
    BISYNC_CMD+=" --backup-dir2 \"$BACKUP_DIR_REMOTE\""
fi
BISYNC_CMD+=" --check-access"
BISYNC_CMD+=" --max-delete $MAX_DELETE_COUNT"
BISYNC_CMD+=" --conflict-resolve $CONFLICT_RESOLVE"
BISYNC_CMD+=" --conflict-suffix \"$CONFLICT_SUFFIX\""
BISYNC_CMD+=" --create-empty-src-dirs"
BISYNC_CMD+=" --track-renames"

# Add --resync only for first run
if [ "$FIRST_RUN" = true ]; then
    BISYNC_CMD+=" --resync"
    echo "$(date): Running FIRST SYNC with --resync flag" >> "$LOG_FILE"
else
    echo "$(date): Running periodic sync (no --resync)" >> "$LOG_FILE"
fi

# Execute the command
echo "$(date): Executing: $BISYNC_CMD" >> "$LOG_FILE"
eval "$BISYNC_CMD" >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

echo "$(date): Bisync completed with exit code $EXIT_CODE" >> "$LOG_FILE"

# Notify on failure
if [ $EXIT_CODE -ne 0 ]; then
    echo "$(date): *** SYNC FAILED - Check $LOG_FILE ***" >> "$LOG_FILE"
    echo ""
    echo "=== SYNC FAILED ==="
    echo "Exit code: $EXIT_CODE"
    echo "Log file: $LOG_FILE"
    echo ""
    echo "To investigate:"
    echo "  tail -n 100 $LOG_FILE"
    echo ""
    # If exit code 7, requires --resync
    if [ $EXIT_CODE -eq 7 ]; then
        echo "ACTION REQUIRED: Run with --first-run flag to recover"
        echo "  ./rclone-bisync-gdrive.sh --first-run"
    fi
    exit $EXIT_CODE
fi

echo "Sync completed successfully."
exit 0
