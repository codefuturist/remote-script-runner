#!/usr/bin/env bash
# =============================================================================
# @name         backup-unified
# @description  Unified backup system supporting rsync, rclone, restic, borg, kopia
# @version      1.0.0
# @author       RSR Team
# @license      MIT
# @requires     bash 4.0+
# =============================================================================
#
# Usage:
#   backup-unified.sh [COMMAND] [OPTIONS]
#
# Commands:
#   run         Run a backup (default)
#   restore     Restore from backup
#   list        List available backups/snapshots
#   init        Initialize backup repository
#   verify      Verify backup integrity
#   prune       Apply retention policy
#   status      Show backup status and tools
#   profile     Manage backup profiles
#   schedule    Create scheduled backup jobs
#   install     Install backup tools
#
# Examples:
#   backup-unified.sh run --source /home --dest /backup --tool restic
#   backup-unified.sh restore --snapshot latest --target /restore
#   backup-unified.sh profile create daily --tool restic --source /home
#
# =============================================================================

set -eo pipefail

# =============================================================================
# RSR Library
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [ -n "${SCRIPT_SOURCE}" ] && [ "${SCRIPT_SOURCE}" != "bash" ] && [ "${SCRIPT_SOURCE}" != "sh" ] && [ "${SCRIPT_SOURCE}" != "-bash" ] && [ "${SCRIPT_SOURCE}" != "-sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

# Load RSR library with backup module
if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    # shellcheck source=../../../lib/rsr-lib.sh
    source "$RSR_LIB_DIR/rsr-lib.sh"
    # Load backup module
    if [[ -f "$RSR_LIB_DIR/modules/backup.sh" ]]; then
        source "$RSR_LIB_DIR/modules/backup.sh"
    fi
else
    echo "ERROR: RSR library not found at $RSR_LIB_DIR/rsr-lib.sh" >&2
    exit 1
fi

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_NAME="Unified Backup"
readonly SCRIPT_VERSION="1.0.0"

# Default options
VERBOSE=false
DRY_RUN=false
QUIET=false
COMMAND=""
TOOL=""
SOURCE_PATHS=()
DEST_PATH=""
EXCLUDE_PATTERNS=()
PROFILE_NAME=""
SNAPSHOT_ID="latest"
TARGET_PATH=""
PASSWORD=""
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=1
VERIFY_AFTER=false
PRUNE_AFTER=false
USE_VSS=false
COMPRESSION="auto"
ENCRYPT=false
SCHEDULE_TIME="02:00"
HOOKS_DIR=""

# Color codes (if not loaded from library)
RED=${RSR_COLOR_RED:-'\033[0;31m'}
GREEN=${RSR_COLOR_GREEN:-'\033[0;32m'}
YELLOW=${RSR_COLOR_YELLOW:-'\033[1;33m'}
BLUE=${RSR_COLOR_BLUE:-'\033[0;34m'}
CYAN=${RSR_COLOR_CYAN:-'\033[0;36m'}
DIM=${RSR_COLOR_DIM:-'\033[2m'}
BOLD=${RSR_COLOR_BOLD:-'\033[1m'}
NC=${RSR_COLOR_RESET:-'\033[0m'}

# =============================================================================
# Help & Usage
# =============================================================================

show_help() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                          RSR Unified Backup System                           ║
╚══════════════════════════════════════════════════════════════════════════════╝

USAGE:
    backup-unified.sh [COMMAND] [OPTIONS]

COMMANDS:
    run             Run a backup (default command)
    restore         Restore from backup
    list            List available backups/snapshots
    init            Initialize backup repository
    verify          Verify backup integrity
    prune           Apply retention policy
    status          Show backup status and installed tools
    profile         Manage backup profiles (create/list/delete/run)
    schedule        Create scheduled backup jobs
    install         Install backup tools

GLOBAL OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -q, --quiet             Suppress non-essential output
    -d, --dry-run           Show what would be done without executing
    --version               Show version information

RUN OPTIONS:
    -t, --tool TOOL         Backup tool: rsync, rclone, restic, borg, kopia
                            (auto-detects best available if not specified)
    -s, --source PATH       Source path to backup (can be repeated)
    -D, --dest PATH         Destination/repository path
    -x, --exclude PATTERN   Exclude pattern (can be repeated)
    -p, --profile NAME      Use a saved backup profile
    --password PWD          Encryption password (or set BACKUP_PASSWORD env)
    --verify                Verify backup after completion
    --prune                 Apply retention policy after backup
    --vss                   Use VSS snapshot (Windows) or LVM snapshot (Linux)
    --compress METHOD       Compression: auto, gzip, lz4, zstd, none
    --encrypt               Enable encryption (requires password)
    --hooks-dir DIR         Directory containing pre/post backup hooks

RESTORE OPTIONS:
    --snapshot ID           Snapshot ID to restore (default: latest)
    --target PATH           Restore target path

RETENTION OPTIONS:
    --keep-daily N          Keep N daily backups (default: 7)
    --keep-weekly N         Keep N weekly backups (default: 4)
    --keep-monthly N        Keep N monthly backups (default: 6)
    --keep-yearly N         Keep N yearly backups (default: 1)

PROFILE SUBCOMMANDS:
    profile create NAME     Create a new profile
    profile list            List all profiles
    profile show NAME       Show profile details
    profile delete NAME     Delete a profile
    profile run NAME        Run backup using profile

SCHEDULE OPTIONS:
    --time HH:MM            Time to run scheduled backup (default: 02:00)
    --daily                 Run daily
    --weekly                Run weekly (Sundays)

SUPPORTED BACKUP TOOLS:
    rsync       Fast incremental file sync (local/remote)
    rclone      Cloud storage swiss army knife (40+ backends)
    restic      Fast, secure, deduplicated backups
    borg        Deduplicating archiver with compression
    kopia       Fast, encrypted, deduplicated backups

EXAMPLES:
    # Quick backup with auto-detected tool
    backup-unified.sh run -s /home/user -D /backup/home

    # Backup with specific tool and encryption
    backup-unified.sh run -t restic -s /home -D /backup/repo --encrypt

    # Create and use a profile
    backup-unified.sh profile create daily -t restic -s /home -D /backup
    backup-unified.sh profile run daily

    # Restore latest backup
    backup-unified.sh restore -t restic -D /backup/repo --target /restore

    # List snapshots
    backup-unified.sh list -t restic -D /backup/repo

    # Apply retention policy
    backup-unified.sh prune -t restic -D /backup/repo --keep-daily 7

    # Schedule daily backup
    backup-unified.sh schedule -p daily --time 02:00 --daily

    # Check available tools
    backup-unified.sh status

EOF
}

show_version() {
    echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
    echo "RSR Backup Module v${_RSR_BACKUP_VERSION:-1.0.0}"
}

# =============================================================================
# Logging Helpers
# =============================================================================

log_info() { [[ "$QUIET" != "true" ]] && echo -e "${BLUE}▸${NC} $1"; }
log_ok() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}  $1${NC}"; }

print_header() {
    [[ "$QUIET" != "true" ]] && echo -e "\n${BOLD}${CYAN}═══ $1 ═══${NC}\n"
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    # Get command if provided
    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
        COMMAND="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -t|--tool)
                TOOL="$2"
                shift 2
                ;;
            -s|--source)
                SOURCE_PATHS+=("$2")
                shift 2
                ;;
            -D|--dest|--destination|--repo|--repository)
                DEST_PATH="$2"
                shift 2
                ;;
            -x|--exclude)
                EXCLUDE_PATTERNS+=("$2")
                shift 2
                ;;
            -p|--profile)
                PROFILE_NAME="$2"
                shift 2
                ;;
            --password)
                PASSWORD="$2"
                shift 2
                ;;
            --snapshot)
                SNAPSHOT_ID="$2"
                shift 2
                ;;
            --target)
                TARGET_PATH="$2"
                shift 2
                ;;
            --verify)
                VERIFY_AFTER=true
                shift
                ;;
            --prune)
                PRUNE_AFTER=true
                shift
                ;;
            --vss)
                USE_VSS=true
                shift
                ;;
            --compress)
                COMPRESSION="$2"
                shift 2
                ;;
            --encrypt)
                ENCRYPT=true
                shift
                ;;
            --hooks-dir)
                HOOKS_DIR="$2"
                shift 2
                ;;
            --keep-daily)
                KEEP_DAILY="$2"
                shift 2
                ;;
            --keep-weekly)
                KEEP_WEEKLY="$2"
                shift 2
                ;;
            --keep-monthly)
                KEEP_MONTHLY="$2"
                shift 2
                ;;
            --keep-yearly)
                KEEP_YEARLY="$2"
                shift 2
                ;;
            --time)
                SCHEDULE_TIME="$2"
                shift 2
                ;;
            --daily|--weekly)
                SCHEDULE_FREQUENCY="${1#--}"
                shift
                ;;
            # Profile subcommands
            create|list|show|delete|run)
                if [[ "$COMMAND" == "profile" ]]; then
                    PROFILE_SUBCOMMAND="$1"
                    shift
                    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                        PROFILE_NAME="$1"
                        shift
                    fi
                else
                    shift
                fi
                ;;
            --)
                shift
                break
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                # Positional argument - could be profile name for subcommand
                if [[ -z "$PROFILE_NAME" ]]; then
                    PROFILE_NAME="$1"
                fi
                shift
                ;;
        esac
    done

    # Default command
    [[ -z "$COMMAND" ]] && COMMAND="status"

    # Password from environment
    [[ -z "$PASSWORD" ]] && PASSWORD="${BACKUP_PASSWORD:-${RESTIC_PASSWORD:-${BORG_PASSPHRASE:-}}}"
}

# =============================================================================
# Tool Detection & Selection
# =============================================================================

detect_best_tool() {
    local tool
    tool=$(rsr_backup_get_default_tool)
    if [[ -n "$tool" ]]; then
        echo "$tool"
    else
        log_error "No backup tool found. Install one with: backup-unified.sh install"
        exit 1
    fi
}

ensure_tool() {
    if [[ -z "$TOOL" ]]; then
        TOOL=$(detect_best_tool)
        log_info "Auto-selected backup tool: $TOOL"
    fi

    if ! rsr_backup_tool_installed "$TOOL"; then
        log_error "Backup tool '$TOOL' is not installed"
        log_info "Install with: backup-unified.sh install $TOOL"
        exit 1
    fi
}

# =============================================================================
# Command: status
# =============================================================================

cmd_status() {
    print_header "Backup System Status"

    echo -e "${BOLD}Installed Backup Tools:${NC}"
    echo ""

    local tools
    tools=$(rsr_backup_list_tools)

    if [[ -z "$tools" ]]; then
        log_warn "No backup tools installed"
        echo ""
        echo "Install tools with:"
        echo "  backup-unified.sh install restic"
        echo "  backup-unified.sh install rclone"
        echo "  backup-unified.sh install borg"
        return
    fi

    printf "  %-12s %-15s %s\n" "TOOL" "VERSION" "STATUS"
    printf "  %-12s %-15s %s\n" "────" "───────" "──────"

    for tool_info in $tools; do
        local tool="${tool_info%%:*}"
        local version="${tool_info#*:}"
        printf "  %-12s %-15s ${GREEN}✓ installed${NC}\n" "$tool" "$version"
    done

    echo ""

    # Show default tool
    local default_tool
    default_tool=$(rsr_backup_get_default_tool)
    echo -e "${BOLD}Default Tool:${NC} $default_tool"

    echo ""

    # Show profiles
    echo -e "${BOLD}Backup Profiles:${NC}"
    local profiles
    profiles=$(rsr_backup_list_profiles 2>/dev/null)
    if [[ -n "$profiles" ]]; then
        echo "$profiles" | while read -r profile; do
            echo "  • $profile"
        done
    else
        echo "  (no profiles configured)"
    fi

    # Platform-specific info
    echo ""
    local os
    os=$(rsr_detect_os)
    case "$os" in
        darwin)
            echo -e "${BOLD}macOS Integration:${NC}"
            if rsr_backup_tool_installed "timemachine"; then
                echo "  • Time Machine: available"
            fi
            ;;
        linux)
            echo -e "${BOLD}Linux Integration:${NC}"
            if command -v systemctl &>/dev/null; then
                echo "  • systemd timers: available"
            fi
            ;;
    esac
}

# =============================================================================
# Command: run
# =============================================================================

cmd_run() {
    # Use profile if specified
    if [[ -n "$PROFILE_NAME" ]]; then
        cmd_profile_run
        return
    fi

    # Validate required options
    if [[ ${#SOURCE_PATHS[@]} -eq 0 ]]; then
        log_error "No source path specified. Use -s/--source"
        exit 1
    fi

    if [[ -z "$DEST_PATH" ]]; then
        log_error "No destination specified. Use -D/--dest"
        exit 1
    fi

    ensure_tool

    print_header "Running Backup"

    log_info "Tool: $TOOL"
    log_info "Sources: ${SOURCE_PATHS[*]}"
    log_info "Destination: $DEST_PATH"

    if [[ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]]; then
        log_info "Excludes: ${EXCLUDE_PATTERNS[*]}"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run mode - no changes will be made"
    fi

    # Run pre-backup hooks
    if [[ -n "$HOOKS_DIR" ]]; then
        rsr_backup_run_pre_hooks "$HOOKS_DIR"
    fi

    local exit_code=0
    local backup_opts=""

    # Build exclude options
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        case "$TOOL" in
            rsync)   backup_opts="$backup_opts --exclude=$pattern" ;;
            rclone)  backup_opts="$backup_opts --exclude $pattern" ;;
            restic)  backup_opts="$backup_opts --exclude $pattern" ;;
            borg)    backup_opts="$backup_opts --exclude $pattern" ;;
            kopia)   backup_opts="$backup_opts --ignore $pattern" ;;
        esac
    done

    # Add compression
    if [[ "$COMPRESSION" != "none" ]] && [[ "$COMPRESSION" != "auto" ]]; then
        case "$TOOL" in
            restic)  backup_opts="$backup_opts --compression $COMPRESSION" ;;
            borg)    backup_opts="$backup_opts --compression $COMPRESSION" ;;
        esac
    fi

    # Add verbose flag
    if [[ "$VERBOSE" == "true" ]]; then
        case "$TOOL" in
            rsync)   backup_opts="$backup_opts -v" ;;
            rclone)  backup_opts="$backup_opts -v" ;;
            restic)  backup_opts="$backup_opts -v" ;;
            borg)    backup_opts="$backup_opts -v" ;;
            kopia)   backup_opts="$backup_opts --log-level=debug" ;;
        esac
    fi

    # Set password environment variable
    if [[ -n "$PASSWORD" ]]; then
        export RESTIC_PASSWORD="$PASSWORD"
        export BORG_PASSPHRASE="$PASSWORD"
    fi

    # Run backup for each source
    for source in "${SOURCE_PATHS[@]}"; do
        log_info "Backing up: $source"

        if [[ "$DRY_RUN" == "true" ]]; then
            case "$TOOL" in
                rsync)   backup_opts="$backup_opts -n" ;;
                rclone)  backup_opts="$backup_opts --dry-run" ;;
                restic)  backup_opts="$backup_opts -n" ;;
                borg)    backup_opts="$backup_opts --dry-run" ;;
                kopia)   backup_opts="$backup_opts --dry-run" ;;
            esac
        fi

        if ! rsr_backup_create "$TOOL" "$DEST_PATH" "$source" $backup_opts; then
            exit_code=1
            log_error "Backup failed for: $source"
        fi
    done

    # Post-backup operations
    if [[ $exit_code -eq 0 ]]; then
        if [[ "$VERIFY_AFTER" == "true" ]]; then
            log_info "Verifying backup..."
            rsr_backup_verify "$TOOL" "$DEST_PATH" || exit_code=1
        fi

        if [[ "$PRUNE_AFTER" == "true" ]]; then
            log_info "Applying retention policy..."
            rsr_backup_prune "$TOOL" "$DEST_PATH" "$KEEP_DAILY" "$KEEP_WEEKLY" "$KEEP_MONTHLY" || true
        fi

        log_ok "Backup completed successfully"
    fi

    # Run post-backup hooks
    if [[ -n "$HOOKS_DIR" ]]; then
        rsr_backup_run_post_hooks "$HOOKS_DIR" "$exit_code"
    fi

    return $exit_code
}

# =============================================================================
# Command: restore
# =============================================================================

cmd_restore() {
    if [[ -z "$DEST_PATH" ]]; then
        log_error "No repository specified. Use -D/--dest"
        exit 1
    fi

    if [[ -z "$TARGET_PATH" ]]; then
        log_error "No restore target specified. Use --target"
        exit 1
    fi

    ensure_tool

    print_header "Restoring Backup"

    log_info "Tool: $TOOL"
    log_info "Repository: $DEST_PATH"
    log_info "Snapshot: $SNAPSHOT_ID"
    log_info "Target: $TARGET_PATH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run mode - no changes will be made"
        return 0
    fi

    # Set password
    if [[ -n "$PASSWORD" ]]; then
        export RESTIC_PASSWORD="$PASSWORD"
        export BORG_PASSPHRASE="$PASSWORD"
    fi

    # Create target directory
    mkdir -p "$TARGET_PATH"

    if rsr_backup_restore "$TOOL" "$DEST_PATH" "$TARGET_PATH" "$SNAPSHOT_ID"; then
        log_ok "Restore completed successfully"
    else
        log_error "Restore failed"
        exit 1
    fi
}

# =============================================================================
# Command: list
# =============================================================================

cmd_list() {
    if [[ -z "$DEST_PATH" ]]; then
        log_error "No repository specified. Use -D/--dest"
        exit 1
    fi

    ensure_tool

    print_header "Backup Snapshots"

    # Set password
    if [[ -n "$PASSWORD" ]]; then
        export RESTIC_PASSWORD="$PASSWORD"
        export BORG_PASSPHRASE="$PASSWORD"
    fi

    rsr_backup_list "$TOOL" "$DEST_PATH"
}

# =============================================================================
# Command: init
# =============================================================================

cmd_init() {
    if [[ -z "$DEST_PATH" ]]; then
        log_error "No repository path specified. Use -D/--dest"
        exit 1
    fi

    ensure_tool

    print_header "Initializing Backup Repository"

    log_info "Tool: $TOOL"
    log_info "Repository: $DEST_PATH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run mode - no changes will be made"
        return 0
    fi

    if rsr_backup_init_repo "$TOOL" "$DEST_PATH" "$PASSWORD"; then
        log_ok "Repository initialized successfully"
    else
        log_error "Repository initialization failed"
        exit 1
    fi
}

# =============================================================================
# Command: verify
# =============================================================================

cmd_verify() {
    if [[ -z "$DEST_PATH" ]]; then
        log_error "No repository specified. Use -D/--dest"
        exit 1
    fi

    ensure_tool

    print_header "Verifying Backup"

    # Set password
    if [[ -n "$PASSWORD" ]]; then
        export RESTIC_PASSWORD="$PASSWORD"
        export BORG_PASSPHRASE="$PASSWORD"
    fi

    if rsr_backup_verify "$TOOL" "$DEST_PATH" "$SNAPSHOT_ID"; then
        log_ok "Backup verification passed"
    else
        log_error "Backup verification failed"
        exit 1
    fi
}

# =============================================================================
# Command: prune
# =============================================================================

cmd_prune() {
    if [[ -z "$DEST_PATH" ]]; then
        log_error "No repository specified. Use -D/--dest"
        exit 1
    fi

    ensure_tool

    print_header "Applying Retention Policy"

    log_info "Keep daily: $KEEP_DAILY"
    log_info "Keep weekly: $KEEP_WEEKLY"
    log_info "Keep monthly: $KEEP_MONTHLY"
    log_info "Keep yearly: $KEEP_YEARLY"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run mode - no changes will be made"
    fi

    # Set password
    if [[ -n "$PASSWORD" ]]; then
        export RESTIC_PASSWORD="$PASSWORD"
        export BORG_PASSPHRASE="$PASSWORD"
    fi

    if rsr_backup_prune "$TOOL" "$DEST_PATH" "$KEEP_DAILY" "$KEEP_WEEKLY" "$KEEP_MONTHLY"; then
        log_ok "Retention policy applied successfully"
    else
        log_error "Retention policy application failed"
        exit 1
    fi
}

# =============================================================================
# Command: profile
# =============================================================================

cmd_profile() {
    case "${PROFILE_SUBCOMMAND:-list}" in
        create)
            cmd_profile_create
            ;;
        list)
            cmd_profile_list
            ;;
        show)
            cmd_profile_show
            ;;
        delete)
            cmd_profile_delete
            ;;
        run)
            cmd_profile_run
            ;;
        *)
            log_error "Unknown profile subcommand: $PROFILE_SUBCOMMAND"
            exit 1
            ;;
    esac
}

cmd_profile_create() {
    if [[ -z "$PROFILE_NAME" ]]; then
        log_error "Profile name required"
        exit 1
    fi

    if [[ ${#SOURCE_PATHS[@]} -eq 0 ]]; then
        log_error "At least one source path required. Use -s/--source"
        exit 1
    fi

    if [[ -z "$DEST_PATH" ]]; then
        log_error "Destination required. Use -D/--dest"
        exit 1
    fi

    ensure_tool

    local excludes=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        excludes="$excludes $pattern"
    done

    rsr_backup_create_profile "$PROFILE_NAME" "$TOOL" "$DEST_PATH" "${SOURCE_PATHS[*]}" "$excludes"
}

cmd_profile_list() {
    print_header "Backup Profiles"

    local profiles
    profiles=$(rsr_backup_list_profiles 2>/dev/null)

    if [[ -z "$profiles" ]]; then
        log_warn "No profiles configured"
        echo ""
        echo "Create a profile with:"
        echo "  backup-unified.sh profile create myprofile -t restic -s /home -D /backup"
        return
    fi

    echo "$profiles"
}

cmd_profile_show() {
    if [[ -z "$PROFILE_NAME" ]]; then
        log_error "Profile name required"
        exit 1
    fi

    local profile_file="$RSR_BACKUP_PROFILE_DIR/${PROFILE_NAME}.conf"

    if [[ ! -f "$profile_file" ]]; then
        log_error "Profile not found: $PROFILE_NAME"
        exit 1
    fi

    print_header "Profile: $PROFILE_NAME"
    cat "$profile_file"
}

cmd_profile_delete() {
    if [[ -z "$PROFILE_NAME" ]]; then
        log_error "Profile name required"
        exit 1
    fi

    local profile_file="$RSR_BACKUP_PROFILE_DIR/${PROFILE_NAME}.conf"

    if [[ ! -f "$profile_file" ]]; then
        log_error "Profile not found: $PROFILE_NAME"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Would delete: $profile_file"
        return
    fi

    rm -f "$profile_file"
    log_ok "Deleted profile: $PROFILE_NAME"
}

cmd_profile_run() {
    if [[ -z "$PROFILE_NAME" ]]; then
        log_error "Profile name required. Use -p/--profile"
        exit 1
    fi

    local profile_file="$RSR_BACKUP_PROFILE_DIR/${PROFILE_NAME}.conf"

    if [[ ! -f "$profile_file" ]]; then
        log_error "Profile not found: $PROFILE_NAME"
        exit 1
    fi

    # Source the profile
    # shellcheck source=/dev/null
    source "$profile_file"

    # Override from profile
    TOOL="${BACKUP_TOOL:-$TOOL}"
    DEST_PATH="${BACKUP_REPO:-$DEST_PATH}"

    # Convert space-separated sources to array
    if [[ -n "${BACKUP_SOURCES:-}" ]]; then
        IFS=' ' read -ra SOURCE_PATHS <<< "$BACKUP_SOURCES"
    fi

    if [[ -n "${BACKUP_EXCLUDES:-}" ]]; then
        IFS=' ' read -ra EXCLUDE_PATTERNS <<< "$BACKUP_EXCLUDES"
    fi

    KEEP_DAILY="${KEEP_DAILY:-7}"
    KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
    KEEP_MONTHLY="${KEEP_MONTHLY:-6}"
    VERIFY_AFTER="${BACKUP_VERIFY:-false}"
    PRUNE_AFTER="${BACKUP_PRUNE:-false}"

    log_info "Running profile: $PROFILE_NAME"
    cmd_run
}

# =============================================================================
# Command: schedule
# =============================================================================

cmd_schedule() {
    if [[ -z "$PROFILE_NAME" ]]; then
        log_error "Profile name required. Use -p/--profile"
        exit 1
    fi

    local os
    os=$(rsr_detect_os)

    print_header "Creating Scheduled Backup"

    log_info "Profile: $PROFILE_NAME"
    log_info "Time: $SCHEDULE_TIME"
    log_info "Frequency: ${SCHEDULE_FREQUENCY:-daily}"

    case "$os" in
        darwin)
            cmd_schedule_launchd
            ;;
        linux)
            if command -v systemctl &>/dev/null; then
                cmd_schedule_systemd
            else
                cmd_schedule_cron
            fi
            ;;
        *)
            log_error "Scheduling not supported on this platform"
            exit 1
            ;;
    esac
}

cmd_schedule_launchd() {
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist_file="$plist_dir/com.rsr.backup.${PROFILE_NAME}.plist"

    mkdir -p "$plist_dir"

    local hour minute
    hour="${SCHEDULE_TIME%%:*}"
    minute="${SCHEDULE_TIME#*:}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Would create: $plist_file"
        rsr_backup_generate_launchd "$PROFILE_NAME" "$hour" "$minute"
        return
    fi

    rsr_backup_generate_launchd "$PROFILE_NAME" "$hour" "$minute" > "$plist_file"

    launchctl load "$plist_file" 2>/dev/null || true

    log_ok "Created launchd job: $plist_file"
    log_info "To start immediately: launchctl start com.rsr.backup.${PROFILE_NAME}"
}

cmd_schedule_systemd() {
    local service_file="/etc/systemd/system/rsr-backup-${PROFILE_NAME}.service"
    local timer_file="/etc/systemd/system/rsr-backup-${PROFILE_NAME}.timer"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Would create: $service_file"
        log_warn "Would create: $timer_file"
        return
    fi

    # Need root for systemd
    if [[ $EUID -ne 0 ]]; then
        log_warn "Root required for systemd. Creating user timer instead."
        service_file="$HOME/.config/systemd/user/rsr-backup-${PROFILE_NAME}.service"
        timer_file="$HOME/.config/systemd/user/rsr-backup-${PROFILE_NAME}.timer"
        mkdir -p "$(dirname "$service_file")"
    fi

    rsr_backup_generate_systemd_service "$PROFILE_NAME" > "$service_file"
    rsr_backup_generate_systemd_timer "$PROFILE_NAME" "*-*-* ${SCHEDULE_TIME}:00" > "$timer_file"

    if [[ $EUID -eq 0 ]]; then
        systemctl daemon-reload
        systemctl enable "rsr-backup-${PROFILE_NAME}.timer"
        systemctl start "rsr-backup-${PROFILE_NAME}.timer"
    else
        systemctl --user daemon-reload
        systemctl --user enable "rsr-backup-${PROFILE_NAME}.timer"
        systemctl --user start "rsr-backup-${PROFILE_NAME}.timer"
    fi

    log_ok "Created systemd timer for profile: $PROFILE_NAME"
}

cmd_schedule_cron() {
    local cron_entry
    cron_entry=$(rsr_backup_generate_cron "${SCHEDULE_TIME%%:*} ${SCHEDULE_TIME#*:} * * *" "$PROFILE_NAME")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Would add cron entry:"
        echo "  $cron_entry"
        return
    fi

    (crontab -l 2>/dev/null | grep -v "rsr backup.*--profile $PROFILE_NAME"; echo "$cron_entry") | crontab -

    log_ok "Added cron job for profile: $PROFILE_NAME"
}

# =============================================================================
# Command: install
# =============================================================================

cmd_install() {
    local install_tool="${PROFILE_NAME:-restic}"

    print_header "Installing Backup Tool"

    if rsr_backup_tool_installed "$install_tool"; then
        local version
        version=$(rsr_backup_tool_version "$install_tool")
        log_warn "$install_tool is already installed (version: $version)"
        return 0
    fi

    log_info "Installing: $install_tool"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run mode - would install $install_tool"
        return 0
    fi

    if rsr_backup_install_tool "$install_tool"; then
        log_ok "$install_tool installed successfully"
    else
        log_error "Failed to install $install_tool"
        exit 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    case "$COMMAND" in
        status|"")
            cmd_status
            ;;
        run|backup)
            cmd_run
            ;;
        restore)
            cmd_restore
            ;;
        list|snapshots)
            cmd_list
            ;;
        init|initialize)
            cmd_init
            ;;
        verify|check)
            cmd_verify
            ;;
        prune|cleanup|retention)
            cmd_prune
            ;;
        profile|profiles)
            cmd_profile
            ;;
        schedule)
            cmd_schedule
            ;;
        install)
            cmd_install
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# =============================================================================
# Entry Point
# =============================================================================

main "$@"

