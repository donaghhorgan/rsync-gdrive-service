# Bidirectional rclone sync to Google Drive

Safe bidirectional synchronization between a local directory and Google Drive, with deletion propagation and multiple safety layers.

## Overview

This repository provides a script and systemd service for `rclone bisync` to safely sync your local folder with Google Drive bidirectionally.

**Why this setup:**
- You need **bidirectional sync with deletion propagation** between PC and Google Drive
- Standard `rclone sync` in both directions causes **cascade-delete data loss**
- `rclone bisync` is the correct tool for safe bidirectional sync

## Quick Start

### Prerequisites

#### 1. Install and configure rclone

```bash
# Install (choose one method)
sudo apt install rclone  # Debian/Ubuntu
sudo pacman -S rclone    # Arch
brew install rclone      # macOS

# Configure your Google Drive remote
rclone config

# Verify
rclone listremotes    # List configured remotes
rclone lsd <remote>:  # Test connection to your remote
```

### Setup

#### 1. Clone this repo
```bash
git clone https://github.com/donaghhorgan/rclone-bisync-gdrive.git
cd rclone-bisync-gdrive
```

#### 2. Configure

Copy and edit the environment file:
```bash
cp .env.example .env
nano .env  # Edit with your values
```

Or set environment variables directly:
```bash
export LOCAL="$HOME/Documents"
export REMOTE="gdrive:Documents"
export BACKUP_DIR_LOCAL="$HOME/Backup"
export BACKUP_DIR_REMOTE="gdrive:Backup"
```

**Available Variables:**

**Note:** At least one of `BACKUP_DIR_LOCAL` or `BACKUP_DIR_REMOTE` must be set.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCAL` | (required) | Local directory to sync |
| `REMOTE` | (required) | Google Drive remote:path |
| `STATE_FILE` | `~/.local/share/rclone-bisync-gdrive/state.json` | State tracking file |
| `BACKUP_DIR_LOCAL` | (optional) | Local backup directory - **MUST NOT be inside LOCAL** |
| `BACKUP_DIR_REMOTE` | (optional) | Remote backup path - **MUST NOT be inside REMOTE** |
| `LOG_FILE` | `~/.cache/rclone-bisync-gdrive/log` | Log file path |
| `LOCK_FILE` | `/tmp/rclone-bisync-gdrive.lock` | Lock file path |
| `CONFLICT_RESOLVE` | `newest` | Conflict resolution: newest, oldest, path1, path2 |
| `MAX_DELETE_COUNT` | `10` | Maximum number of files allowed to be deleted in one run |
| `CONFLICT_SUFFIX` | `-{DateTime}-conflict` | Suffix for conflict files |

#### 3. First Run
```bash
# Dry run first - REVIEW CAREFULLY
source .env
./rclone-bisync-gdrive.sh --first-run --dry-run

# If it looks correct, run for real
./rclone-bisync-gdrive.sh --first-run
```

This creates the state file. **Never delete the state file.**

#### 4. Test

Make a small change locally or on Google Drive, then run:
```bash
./rclone-bisync-gdrive.sh
```

Verify the change propagated to the other side.

#### 5. (Optional) Install as systemd user service

```bash
# Copy service files to user service directory
mkdir -p ~/.config/systemd/user/
cp rclone-bisync-gdrive.service rclone-bisync-gdrive.timer ~/.config/systemd/user/

# Enable and start
systemctl --user daemon-reload
systemctl --user enable --now rclone-bisync-gdrive.timer

# Verify
systemctl --user list-timers | grep gdrive
journalctl --user -u rclone-bisync-gdrive.service -f
```

**Note:** User services run as your user account and have automatic access to your home directory and rclone config.

## Usage

```bash
# Normal periodic sync (NO --resync flag)
./rclone-bisync-gdrive.sh

# First run or after config changes (USE --first-run)
./rclone-bisync-gdrive.sh --first-run

# Force resync (only if you know what you're doing)
./rclone-bisync-gdrive.sh --resync
```

## Recovery

### Restore a Deleted File
```bash
# List backup contents
rclone lsl gdrive:Documents/_bisync_backup/

# Restore a specific file
rclone copy gdrive:Documents/_bisync_backup/file.txt ~/Documents/
```

### Bisync Requires --resync
If you see: `Must run --resync to recover`
```bash
./rclone-bisync-gdrive.sh --first-run
```

### State File Corruption
```bash
# Backup the old state file
mv ~/.local/share/rclone-bisync-gdrive/state.json ~/.local/share/rclone-bisync-gdrive/state.json.bak

# Rebuild state with dry run
./rclone-bisync-gdrive.sh --first-run --dry-run

# Review, then run for real
./rclone-bisync-gdrive.sh --first-run
```

## Files

| File | Purpose |
|------|---------|
| `rclone-bisync-gdrive.sh` | Main sync script |
| `rclone-bisync-gdrive.service` | Systemd service file |
| `rclone-bisync-gdrive.timer` | Systemd timer file |
| `.env.example` | Environment variable template |
| `LICENSE` | GPLv3 License |

## License

GNU General Public License v3 - see [LICENSE](LICENSE) for details.

## References

- [rclone bisync documentation](https://rclone.org/bisync/)
- [rclone documentation](https://rclone.org/)
