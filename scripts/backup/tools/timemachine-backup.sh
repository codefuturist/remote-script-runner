#!/usr/bin/env bash
# =============================================================================
# @name         timemachine-backup
# @description  macOS Time Machine backup management
# @version      1.0.0
# @author       RSR Team
# @license      MIT
# @requires     bash 4.0+, macOS
# =============================================================================
#
# Time Machine management:
#   - Start/stop backups
#   - Add/remove backup destinations
#   - Exclude paths
#   - View backup history
#   - Restore files
#
# =============================================================================

set -eo pipefail

# =============================================================================
# RSR Library
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [ -n "${SCRIPT_SOURCE}" ] && [ "${SCRIPT_SOURCE}" != "bash" ] && [ "${SCRIPT_SOURCE}" != "sh" ] && [ "${SCRIPT_SOURCE}" != "-bash" ] && [ "${SCRIPT_SOURCE}" != "-sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2> /dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh"
else
    echo "ERROR: RSR library not found" >&2
    exit 1
fi

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_NAME="Time Machine Backup"
readonly SCRIPT_VERSION="1.0.0"

VERBOSE=false
COMMAND=""
DEST_PATH=""
EXCLUDE_PATH=""
RESTORE_PATH=""
RESTORE_TARGET=""
SNAPSHOT_DATE=""

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
Time Machine Backup - macOS backup management

USAGE:
    timemachine-backup.sh [COMMAND] [OPTIONS]

COMMANDS:
    status          Show Time Machine status (default)
    start           Start a backup now
    stop            Stop current backup
    enable          Enable automatic backups
    disable         Disable automatic backups
    list            List available backups
    destinations    List/manage backup destinations
    exclude         Add exclusion path
    include         Remove exclusion path
    exclusions      List excluded paths
    restore         Restore file/folder from backup
    compare         Compare current with backup
    delete          Delete specific backup
    inherit         Inherit backup from another machine
    verify          Verify backup integrity

DESTINATION OPTIONS:
    --add PATH          Add backup destination
    --remove PATH       Remove backup destination
    --set-default PATH  Set default destination

EXCLUDE OPTIONS:
    --path PATH         Path to exclude/include

RESTORE OPTIONS:
    --source PATH       Source path in backup
    --target PATH       Restore target path
    --date DATE         Backup date (YYYY-MM-DD or "latest")

EXAMPLES:
    # Check status
    timemachine-backup.sh status

    # Start backup now
    sudo timemachine-backup.sh start

    # List all backups
    timemachine-backup.sh list

    # Add network destination
    sudo timemachine-backup.sh destinations --add smb://server/share

    # Exclude a folder
    sudo timemachine-backup.sh exclude --path /path/to/exclude

    # List exclusions
    timemachine-backup.sh exclusions

    # Restore a file
    timemachine-backup.sh restore --source "/Users/me/file.txt" --target "/restore/"

    # Enter Time Machine interface
    open -a "Time Machine"

EOF
}

# =============================================================================
# Logging
# =============================================================================

log_info() { echo -e "${RSR_COLOR_BLUE:-}▸${RSR_COLOR_RESET:-} $1"; }
log_ok() { echo -e "${RSR_COLOR_GREEN:-}✓${RSR_COLOR_RESET:-} $1"; }
log_warn() { echo -e "${RSR_COLOR_YELLOW:-}⚠${RSR_COLOR_RESET:-} $1" >&2; }
log_error() { echo -e "${RSR_COLOR_RED:-}✗${RSR_COLOR_RESET:-} $1" >&2; }

# =============================================================================
# Platform Check
# =============================================================================

check_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_error "Time Machine is only available on macOS"
        exit 1
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_warn "This command may require sudo"
    fi
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    # Check for command
    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
        COMMAND="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_help
                exit 0
                ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            --add | --remove | --set-default | --path)
                DEST_PATH="$2"
                ACTION="${1#--}"
                shift 2
                ;;
            --source)
                RESTORE_PATH="$2"
                shift 2
                ;;
            --target)
                RESTORE_TARGET="$2"
                shift 2
                ;;
            --date)
                SNAPSHOT_DATE="$2"
                shift 2
                ;;
            *) shift ;;
        esac
    done

    [[ -z "$COMMAND" ]] && COMMAND="status"
}

# =============================================================================
# Commands
# =============================================================================

cmd_status() {
    echo ""
    echo "═══ Time Machine Status ═══"
    echo ""

    # Basic status
    local enabled
    enabled=$(tmutil destinationinfo 2> /dev/null | grep -c "Name" || echo "0")

    if [[ "$enabled" -gt 0 ]]; then
        log_ok "Time Machine is configured"
    else
        log_warn "Time Machine is not configured"
        echo ""
        echo "Configure with:"
        echo "  System Preferences → Time Machine → Select Backup Disk"
        return
    fi

    echo ""

    # Destinations
    echo "Backup Destinations:"
    tmutil destinationinfo 2> /dev/null | while read -r line; do
        echo "  $line"
    done

    echo ""

    # Current backup status
    local phase
    phase=$(tmutil currentphase 2> /dev/null || echo "Idle")
    echo "Current Phase: $phase"

    # Last backup
    local latest
    latest=$(tmutil latestbackup 2> /dev/null || echo "No backups")
    echo "Latest Backup: $latest"

    # Auto backup status
    local auto
    auto=$(defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup 2> /dev/null || echo "1")
    if [[ "$auto" == "1" ]]; then
        echo "Auto Backup: Enabled"
    else
        echo "Auto Backup: Disabled"
    fi

    # Local snapshots
    local snapshots
    snapshots=$(tmutil listlocalsnapshots / 2> /dev/null | wc -l | tr -d ' ')
    echo "Local Snapshots: $snapshots"
}

cmd_start() {
    check_root
    log_info "Starting Time Machine backup..."
    tmutil startbackup --auto
    log_ok "Backup started"
}

cmd_stop() {
    check_root
    log_info "Stopping Time Machine backup..."
    tmutil stopbackup
    log_ok "Backup stopped"
}

cmd_enable() {
    check_root
    log_info "Enabling automatic backups..."
    tmutil enable
    log_ok "Automatic backups enabled"
}

cmd_disable() {
    check_root
    log_info "Disabling automatic backups..."
    tmutil disable
    log_ok "Automatic backups disabled"
}

cmd_list() {
    echo ""
    echo "═══ Time Machine Backups ═══"
    echo ""

    tmutil listbackups 2> /dev/null | while read -r backup; do
        local date
        date=$(basename "$backup")
        echo "  • $date"
    done
}

cmd_destinations() {
    case "${ACTION:-list}" in
        add)
            if [[ -z "$DEST_PATH" ]]; then
                log_error "Destination path required"
                exit 1
            fi
            check_root
            log_info "Adding destination: $DEST_PATH"
            tmutil setdestination -a "$DEST_PATH"
            log_ok "Destination added"
            ;;
        remove)
            if [[ -z "$DEST_PATH" ]]; then
                log_error "Destination path required"
                exit 1
            fi
            check_root
            log_info "Removing destination: $DEST_PATH"
            tmutil removedestination "$DEST_PATH"
            log_ok "Destination removed"
            ;;
        set-default)
            if [[ -z "$DEST_PATH" ]]; then
                log_error "Destination path required"
                exit 1
            fi
            check_root
            log_info "Setting default destination: $DEST_PATH"
            tmutil setdestination "$DEST_PATH"
            log_ok "Default destination set"
            ;;
        list | *)
            echo ""
            echo "═══ Backup Destinations ═══"
            echo ""
            tmutil destinationinfo
            ;;
    esac
}

cmd_exclude() {
    if [[ -z "$DEST_PATH" ]]; then
        log_error "Path to exclude required. Use --path"
        exit 1
    fi
    check_root
    log_info "Adding exclusion: $DEST_PATH"
    tmutil addexclusion "$DEST_PATH"
    log_ok "Path excluded from backups"
}

cmd_include() {
    if [[ -z "$DEST_PATH" ]]; then
        log_error "Path to include required. Use --path"
        exit 1
    fi
    check_root
    log_info "Removing exclusion: $DEST_PATH"
    tmutil removeexclusion "$DEST_PATH"
    log_ok "Path will now be included in backups"
}

cmd_exclusions() {
    echo ""
    echo "═══ Excluded Paths ═══"
    echo ""

    # System exclusions
    local exclude_plist="/Library/Preferences/com.apple.TimeMachine.plist"

    if [[ -f "$exclude_plist" ]]; then
        defaults read /Library/Preferences/com.apple.TimeMachine ExcludeByPath 2> /dev/null \
            | grep -v "^(" | grep -v "^)" | sed 's/^[[:space:]]*/  /' | sed 's/,$//' | sed 's/"//g'
    fi

    echo ""
    echo "Note: Some system paths are excluded by default"
}

cmd_restore() {
    if [[ -z "$RESTORE_PATH" ]]; then
        log_error "Source path required. Use --source"
        exit 1
    fi

    if [[ -z "$RESTORE_TARGET" ]]; then
        log_error "Target path required. Use --target"
        exit 1
    fi

    log_info "Restoring: $RESTORE_PATH"
    log_info "To: $RESTORE_TARGET"

    # Find the backup path
    local backup_base
    if [[ -n "$SNAPSHOT_DATE" ]] && [[ "$SNAPSHOT_DATE" != "latest" ]]; then
        backup_base=$(tmutil listbackups 2> /dev/null | grep "$SNAPSHOT_DATE" | head -1)
    else
        backup_base=$(tmutil latestbackup 2> /dev/null)
    fi

    if [[ -z "$backup_base" ]]; then
        log_error "Backup not found"
        exit 1
    fi

    local full_source="${backup_base}${RESTORE_PATH}"

    if [[ ! -e "$full_source" ]]; then
        log_error "Source not found in backup: $full_source"
        exit 1
    fi

    mkdir -p "$RESTORE_TARGET"

    log_info "Copying from: $full_source"
    cp -R "$full_source" "$RESTORE_TARGET/"

    log_ok "Restore completed"
}

cmd_compare() {
    local latest
    latest=$(tmutil latestbackup 2> /dev/null)

    if [[ -z "$latest" ]]; then
        log_error "No backup available for comparison"
        exit 1
    fi

    log_info "Comparing with: $latest"
    tmutil compare "$latest"
}

cmd_verify() {
    log_info "Verifying backup integrity..."
    check_root
    tmutil verifychecksums /
    log_ok "Verification completed"
}

cmd_delete() {
    if [[ -z "$SNAPSHOT_DATE" ]]; then
        log_error "Backup date required. Use --date"
        exit 1
    fi

    check_root

    local backup
    backup=$(tmutil listbackups 2> /dev/null | grep "$SNAPSHOT_DATE" | head -1)

    if [[ -z "$backup" ]]; then
        log_error "Backup not found for date: $SNAPSHOT_DATE"
        exit 1
    fi

    log_info "Deleting backup: $backup"
    tmutil delete "$backup"
    log_ok "Backup deleted"
}

# =============================================================================
# Main
# =============================================================================

main() {
    check_macos
    parse_args "$@"

    case "$COMMAND" in
        status) cmd_status ;;
        start) cmd_start ;;
        stop) cmd_stop ;;
        enable) cmd_enable ;;
        disable) cmd_disable ;;
        list) cmd_list ;;
        destinations) cmd_destinations ;;
        exclude) cmd_exclude ;;
        include) cmd_include ;;
        exclusions) cmd_exclusions ;;
        restore) cmd_restore ;;
        compare) cmd_compare ;;
        verify) cmd_verify ;;
        delete) cmd_delete ;;
        *)
            log_error "Unknown command: $COMMAND"
            exit 1
            ;;
    esac
}

main "$@"
