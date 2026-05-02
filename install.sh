#!/bin/bash
# Install script for rclone-bisync-gdrive service
# This script installs the sync script and sets up a user systemd service
# Environment variables should be set in the user's shell profile

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="rclone-bisync-gdrive.sh"
SERVICE_NAME="rclone-bisync-gdrive"

# Install paths
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

# =============================================================================
# Colors for output
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper functions
# =============================================================================

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# =============================================================================
# Main installation
# =============================================================================

main() {
    info "Starting rclone-bisync-gdrive service installation..."
    info "Repository directory: $REPO_DIR"

    # Check prerequisites
    check_prerequisites

    # Create directories
    info "Creating directories..."
    mkdir -p "$BIN_DIR"
    mkdir -p "$SERVICE_DIR"

    # Copy the script
    info "Installing sync script to $BIN_DIR/$SCRIPT_NAME..."
    cp "$REPO_DIR/$SCRIPT_NAME" "$BIN_DIR/$SCRIPT_NAME"
    chmod +x "$BIN_DIR/$SCRIPT_NAME"
    success "Script installed to $BIN_DIR/$SCRIPT_NAME"

    # Copy systemd files
    info "Installing systemd service and timer files..."
    cp "$REPO_DIR/${SERVICE_NAME}.service" "$SERVICE_DIR/${SERVICE_NAME}.service"
    cp "$REPO_DIR/${SERVICE_NAME}.timer" "$SERVICE_DIR/${SERVICE_NAME}.timer"
    success "Systemd files installed to $SERVICE_DIR/"

    # Update service file paths to use the installed script location
    info "Updating service file with correct paths..."
    local script_path="$BIN_DIR/$SCRIPT_NAME"
    
    # Calculate relative path from HOME for use with %h in user service
    local relative_bin_dir="${BIN_DIR#$HOME/}"
    
    # If BIN_DIR is not under HOME, use absolute path instead of %h
    if [[ "$BIN_DIR" == "$HOME"* ]]; then
        # BIN_DIR is under HOME, use %h with relative path
        sed -i "s|ExecStart=.*|ExecStart=%h/$relative_bin_dir/$SCRIPT_NAME|" "$SERVICE_DIR/${SERVICE_NAME}.service"
    else
        # BIN_DIR is outside HOME, use absolute path
        sed -i "s|ExecStart=.*|ExecStart=$script_path|" "$SERVICE_DIR/${SERVICE_NAME}.service"
    fi
    
    success "Service file updated with correct paths"

    # Reload systemd
    info "Reloading systemd user daemon..."
    systemctl --user daemon-reload
    success "Systemd daemon reloaded"

    # Enable and start the timer
    info "Enabling and starting the timer..."
    systemctl --user enable --now "${SERVICE_NAME}.timer"
    success "Timer enabled and started"

    # Verify installation
    verify_installation

    info ""
    info "Installation complete!"
    info ""
    info "The service will now run automatically every 15 minutes."
    info ""
    info "IMPORTANT: You must set the required environment variables in your shell profile:"
    info "  LOCAL, REMOTE, BACKUP_DIR"
    info ""
    info "Example (add to ~/.bashrc or ~/.zshrc):"
    info "  export LOCAL=\"\$HOME/Documents\""
    info "  export REMOTE=\"gdrive:Documents\""
    info "  export BACKUP_DIR=\"gdrive:Backup\""
    info ""
    info "Then restart your shell or run: source ~/.bashrc"
    info ""
    info "To check status:"
    info "  systemctl --user status ${SERVICE_NAME}.timer"
    info "  systemctl --user status ${SERVICE_NAME}.service"
    info ""
    info "To view logs:"
    info "  journalctl --user -u ${SERVICE_NAME}.service -f"
    info ""
    info "To manually run a sync:"
    info "  $BIN_DIR/$SCRIPT_NAME"
    info ""
    info "To stop the automatic sync:"
    info "  systemctl --user stop ${SERVICE_NAME}.timer"
    info "  systemctl --user disable ${SERVICE_NAME}.timer"
}

# =============================================================================
# Check prerequisites
# =============================================================================

check_prerequisites() {
    # Check if rclone is installed
    if ! command -v rclone &> /dev/null; then
        error "rclone is not installed. Please install it first:"
        error "  sudo apt install rclone  # Debian/Ubuntu"
        error "  sudo pacman -S rclone    # Arch"
        error "  brew install rclone      # macOS"
        exit 1
    fi
    success "rclone is installed"

    # Check if rclone is configured
    if ! rclone listremotes &> /dev/null; then
        error "rclone is not configured. Please configure it first:"
        error "  rclone config"
        exit 1
    fi
    success "rclone is configured"

    # Check if systemd is available for user services
    if ! systemctl --user is-system-running &> /dev/null; then
        warn "User systemd is not running. The service will start when you log in."
    fi
}

# =============================================================================
# Verify installation
# =============================================================================

verify_installation() {
    info "Verifying installation..."

    # Check script is in place
    if [ -x "$BIN_DIR/$SCRIPT_NAME" ]; then
        success "Script is installed and executable"
    else
        error "Script not found at $BIN_DIR/$SCRIPT_NAME"
        exit 1
    fi

    # Check service files are in place
    if [ -f "$SERVICE_DIR/${SERVICE_NAME}.service" ] && [ -f "$SERVICE_DIR/${SERVICE_NAME}.timer" ]; then
        success "Service and timer files are installed"
    else
        error "Service or timer files not found in $SERVICE_DIR/"
        exit 1
    fi

    # Check timer is enabled
    if systemctl --user is-enabled "${SERVICE_NAME}.timer" &> /dev/null; then
        success "Timer is enabled"
    else
        error "Timer is not enabled"
        exit 1
    fi
}

# =============================================================================
# Uninstall function
# =============================================================================

uninstall() {
    info "Uninstalling rclone-bisync-gdrive service..."

    # Stop and disable the timer
    if systemctl --user is-enabled "${SERVICE_NAME}.timer" &> /dev/null; then
        info "Stopping and disabling timer..."
        systemctl --user stop "${SERVICE_NAME}.timer" 2> /dev/null || true
        systemctl --user disable "${SERVICE_NAME}.timer" 2> /dev/null || true
        success "Timer stopped and disabled"
    else
        info "Timer is not currently enabled"
    fi

    # Remove systemd files
    info "Removing systemd files..."
    rm -f "$SERVICE_DIR/${SERVICE_NAME}.service"
    rm -f "$SERVICE_DIR/${SERVICE_NAME}.timer"
    success "Systemd files removed"

    # Remove script
    info "Removing script..."
    rm -f "$BIN_DIR/$SCRIPT_NAME"
    success "Script removed"

    # Reload systemd
    info "Reloading systemd user daemon..."
    systemctl --user daemon-reload 2> /dev/null || true

    info ""
    info "Uninstallation complete!"
}

# =============================================================================
# Parse command line arguments
# =============================================================================

case "${1:-}" in
    --uninstall)
        uninstall
        exit 0
        ;;
    --help|-h)
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  --uninstall    Remove the installed service and files"
        echo "  --help, -h     Show this help message"
        echo ""
        echo "Without options, installs the service."
        echo ""
        echo "IMPORTANT: Set LOCAL, REMOTE, and BACKUP_DIR environment variables"
        echo "in your shell profile before installing."
        exit 0
        ;;
    "")
        main
        ;;
    *)
        error "Unknown option: $1"
        error "Use --help for usage information"
        exit 1
        ;;
esac
