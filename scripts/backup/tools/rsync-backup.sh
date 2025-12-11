#!/usr/bin/env bash
# =============================================================================
# @name         rsync-backup
# @description  Fast incremental backup using rsync
# @version      1.0.0
# @author       RSR Team
# @license      MIT
# @requires     bash 4.0+, rsync
# =============================================================================
#
# Rsync backup with:
#   - Incremental transfers (only changed files)
#   - Hard links for space-efficient versioning
#   - Bandwidth limiting
#   - Remote backup via SSH
#   - Detailed logging
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

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh"
    [[ -f "$RSR_LIB_DIR/modules/backup.sh" ]] && source "$RSR_LIB_DIR/modules/backup.sh"
else
    echo "ERROR: RSR library not found" >&2
    exit 1
fi

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_NAME="Rsync Backup"
readonly SCRIPT_VERSION="1.0.0"

VERBOSE=false
DRY_RUN=false
SOURCE=""
DEST=""
EXCLUDE_FILE=""
EXCLUDE_PATTERNS=()
INCLUDE_PATTERNS=()
BANDWIDTH=""
DELETE_MODE="after"
LINK_DEST=""
REMOTE_SHELL="ssh"
SSH_KEY=""
SSH_PORT=""
CHECKSUM=false
COMPRESS_TRANSFER=true
PRESERVE_HARD_LINKS=false
LOG_FILE=""
STATS=true

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
Rsync Backup - Fast incremental file synchronization

USAGE:
    rsync-backup.sh [OPTIONS] SOURCE DEST

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be transferred
    -x, --exclude PATTERN   Exclude pattern (can be repeated)
    -i, --include PATTERN   Include pattern (can be repeated)
    --exclude-from FILE     Read exclude patterns from file
    --bwlimit KBPS          Limit bandwidth (KB/s)
    --delete-before         Delete files before transfer
    --delete-after          Delete files after transfer (default)
    --delete-during         Delete files during transfer
    --no-delete             Don't delete extraneous files
    --link-dest DIR         Create hard links to DIR for unchanged files
    -e, --rsh COMMAND       Remote shell command
    --ssh-key FILE          SSH private key file
    --ssh-port PORT         SSH port
    -c, --checksum          Use checksum instead of mod-time
    --no-compress           Disable compression during transfer
    -H, --hard-links        Preserve hard links
    --log FILE              Write log to file
    --no-stats              Don't show transfer statistics

EXAMPLES:
    # Simple local backup
    rsync-backup.sh /home/user /backup/home

    # Backup to remote server
    rsync-backup.sh /home/user user@server:/backup/

    # Incremental with hard links (time machine style)
    rsync-backup.sh --link-dest /backup/latest /home /backup/$(date +%Y%m%d)

    # Bandwidth limited backup
    rsync-backup.sh --bwlimit 5000 /home /backup

    # Exclude patterns
    rsync-backup.sh -x '*.tmp' -x '.cache' /home /backup

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
# Argument Parsing
# =============================================================================

parse_args() {
    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) show_help; exit 0 ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            -x|--exclude) EXCLUDE_PATTERNS+=("$2"); shift 2 ;;
            -i|--include) INCLUDE_PATTERNS+=("$2"); shift 2 ;;
            --exclude-from) EXCLUDE_FILE="$2"; shift 2 ;;
            --bwlimit) BANDWIDTH="$2"; shift 2 ;;
            --delete-before) DELETE_MODE="before"; shift ;;
            --delete-after) DELETE_MODE="after"; shift ;;
            --delete-during) DELETE_MODE="during"; shift ;;
            --no-delete) DELETE_MODE="none"; shift ;;
            --link-dest) LINK_DEST="$2"; shift 2 ;;
            -e|--rsh) REMOTE_SHELL="$2"; shift 2 ;;
            --ssh-key) SSH_KEY="$2"; shift 2 ;;
            --ssh-port) SSH_PORT="$2"; shift 2 ;;
            -c|--checksum) CHECKSUM=true; shift ;;
            --no-compress) COMPRESS_TRANSFER=false; shift ;;
            -H|--hard-links) PRESERVE_HARD_LINKS=true; shift ;;
            --log) LOG_FILE="$2"; shift 2 ;;
            --no-stats) STATS=false; shift ;;
            --) shift; positional+=("$@"); break ;;
            -*) log_error "Unknown option: $1"; exit 1 ;;
            *) positional+=("$1"); shift ;;
        esac
    done

    if [[ ${#positional[@]} -lt 2 ]]; then
        log_error "Source and destination required"
        show_help
        exit 1
    fi

    SOURCE="${positional[0]}"
    DEST="${positional[1]}"
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Check rsync is installed
    if ! command -v rsync &>/dev/null; then
        log_error "rsync is not installed"
        exit 1
    fi

    # Build rsync command
    local rsync_opts=(-a)

    # Verbose
    [[ "$VERBOSE" == "true" ]] && rsync_opts+=(-v --progress)

    # Dry run
    [[ "$DRY_RUN" == "true" ]] && rsync_opts+=(-n)

    # Delete mode
    case "$DELETE_MODE" in
        before) rsync_opts+=(--delete-before) ;;
        after) rsync_opts+=(--delete-after) ;;
        during) rsync_opts+=(--delete-during) ;;
    esac

    # Excludes
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        rsync_opts+=(--exclude="$pattern")
    done

    # Includes
    for pattern in "${INCLUDE_PATTERNS[@]}"; do
        rsync_opts+=(--include="$pattern")
    done

    # Exclude file
    [[ -n "$EXCLUDE_FILE" ]] && rsync_opts+=(--exclude-from="$EXCLUDE_FILE")

    # Bandwidth limit
    [[ -n "$BANDWIDTH" ]] && rsync_opts+=(--bwlimit="$BANDWIDTH")

    # Link dest (for incremental backups)
    [[ -n "$LINK_DEST" ]] && rsync_opts+=(--link-dest="$LINK_DEST")

    # Remote shell
    local rsh_cmd="$REMOTE_SHELL"
    [[ -n "$SSH_KEY" ]] && rsh_cmd="$rsh_cmd -i $SSH_KEY"
    [[ -n "$SSH_PORT" ]] && rsh_cmd="$rsh_cmd -p $SSH_PORT"
    rsync_opts+=(-e "$rsh_cmd")

    # Checksum
    [[ "$CHECKSUM" == "true" ]] && rsync_opts+=(-c)

    # Compression
    [[ "$COMPRESS_TRANSFER" == "true" ]] && rsync_opts+=(-z)

    # Hard links
    [[ "$PRESERVE_HARD_LINKS" == "true" ]] && rsync_opts+=(-H)

    # Stats
    [[ "$STATS" == "true" ]] && rsync_opts+=(--stats)

    # Ensure source ends with / for directory content
    [[ -d "$SOURCE" && ! "$SOURCE" =~ /$ ]] && SOURCE="${SOURCE}/"

    log_info "Starting rsync backup..."
    log_info "Source: $SOURCE"
    log_info "Destination: $DEST"

    if [[ -n "$LOG_FILE" ]]; then
        rsync "${rsync_opts[@]}" "$SOURCE" "$DEST" 2>&1 | tee "$LOG_FILE"
    else
        rsync "${rsync_opts[@]}" "$SOURCE" "$DEST"
    fi

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_ok "Rsync backup completed successfully"
    else
        log_error "Rsync backup failed with exit code: $exit_code"
    fi

    return $exit_code
}

main "$@"

