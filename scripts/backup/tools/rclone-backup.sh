#!/usr/bin/env bash
# =============================================================================
# @name         rclone-backup
# @description  Cloud backup using rclone (supports 40+ cloud providers)
# @version      1.0.0
# @author       RSR Team
# @license      MIT
# @requires     bash 4.0+, rclone
# =============================================================================
#
# Rclone backup features:
#   - 40+ cloud storage backends (S3, GCS, Azure, Dropbox, etc.)
#   - Encryption support
#   - Bandwidth limiting
#   - Sync and copy modes
#   - Server-side copy when possible
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

readonly SCRIPT_NAME="Rclone Backup"
readonly SCRIPT_VERSION="1.0.0"

VERBOSE=false
DRY_RUN=false
COMMAND="sync"
SOURCE=""
DEST=""
EXCLUDE_PATTERNS=()
INCLUDE_PATTERNS=()
FILTER_FILE=""
BANDWIDTH=""
TRANSFERS=4
CHECKERS=8
MIN_AGE=""
MAX_AGE=""
MIN_SIZE=""
MAX_SIZE=""
COMPARE_MODE="mod-time"
CREATE_EMPTY_DIRS=true
BACKUP_DIR=""
SUFFIX=""
LOG_FILE=""
LOG_LEVEL="INFO"
STATS_INTERVAL="1m"
PROGRESS=true

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
Rclone Backup - Cloud storage swiss army knife

USAGE:
    rclone-backup.sh [COMMAND] [OPTIONS] SOURCE DEST

COMMANDS:
    sync        Make destination identical to source (default)
    copy        Copy files without deleting
    move        Move files (delete after copy)
    check       Check if files are identical
    ls          List files
    config      Configure remotes interactively

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be done
    -x, --exclude PATTERN   Exclude pattern (can be repeated)
    -i, --include PATTERN   Include pattern (can be repeated)
    --filter-from FILE      Read filter patterns from file
    --bwlimit RATE          Bandwidth limit (e.g., 10M, 1G)
    --transfers N           Number of parallel transfers (default: 4)
    --checkers N            Number of checkers (default: 8)
    --min-age AGE           Skip files newer than AGE
    --max-age AGE           Skip files older than AGE
    --min-size SIZE         Skip files smaller than SIZE
    --max-size SIZE         Skip files larger than SIZE
    --checksum              Compare by checksum instead of mod-time
    --size-only             Compare by size only
    --no-empty-dirs         Don't create empty directories
    --backup-dir DIR        Move deleted/changed files to DIR
    --suffix SUFFIX         Suffix for backup files
    --log FILE              Write log to file
    --log-level LEVEL       Log level: DEBUG, INFO, NOTICE, ERROR
    --stats-interval DUR    Stats update interval (default: 1m)
    --no-progress           Disable progress display

REMOTE SYNTAX:
    Local path:     /path/to/folder
    Remote:         remote:path

    Supported remotes (configure with 'rclone config'):
    - s3:bucket/path          Amazon S3
    - gcs:bucket/path         Google Cloud Storage
    - azure:container/path    Azure Blob Storage
    - b2:bucket/path          Backblaze B2
    - dropbox:path            Dropbox
    - gdrive:path             Google Drive
    - onedrive:path           OneDrive
    - sftp:user@host:path     SFTP
    ... and 40+ more

EXAMPLES:
    # Sync local to S3
    rclone-backup.sh sync /home/user s3:mybucket/backup

    # Copy to Google Drive with progress
    rclone-backup.sh copy /documents gdrive:backups/docs

    # Sync with bandwidth limit
    rclone-backup.sh sync --bwlimit 10M /data remote:backup

    # Backup with versioning
    rclone-backup.sh sync /data s3:bucket --backup-dir s3:bucket/old

    # Check if local matches remote
    rclone-backup.sh check /data s3:bucket/data

    # Configure a new remote
    rclone-backup.sh config

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

    # Check for command
    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
        case "$1" in
            sync|copy|move|check|ls|config)
                COMMAND="$1"
                shift
                ;;
        esac
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) show_help; exit 0 ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            -x|--exclude) EXCLUDE_PATTERNS+=("$2"); shift 2 ;;
            -i|--include) INCLUDE_PATTERNS+=("$2"); shift 2 ;;
            --filter-from) FILTER_FILE="$2"; shift 2 ;;
            --bwlimit) BANDWIDTH="$2"; shift 2 ;;
            --transfers) TRANSFERS="$2"; shift 2 ;;
            --checkers) CHECKERS="$2"; shift 2 ;;
            --min-age) MIN_AGE="$2"; shift 2 ;;
            --max-age) MAX_AGE="$2"; shift 2 ;;
            --min-size) MIN_SIZE="$2"; shift 2 ;;
            --max-size) MAX_SIZE="$2"; shift 2 ;;
            --checksum) COMPARE_MODE="checksum"; shift ;;
            --size-only) COMPARE_MODE="size"; shift ;;
            --no-empty-dirs) CREATE_EMPTY_DIRS=false; shift ;;
            --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
            --suffix) SUFFIX="$2"; shift 2 ;;
            --log) LOG_FILE="$2"; shift 2 ;;
            --log-level) LOG_LEVEL="$2"; shift 2 ;;
            --stats-interval) STATS_INTERVAL="$2"; shift 2 ;;
            --no-progress) PROGRESS=false; shift ;;
            --) shift; positional+=("$@"); break ;;
            -*) log_error "Unknown option: $1"; exit 1 ;;
            *) positional+=("$1"); shift ;;
        esac
    done

    # Config command doesn't need source/dest
    if [[ "$COMMAND" == "config" ]]; then
        return
    fi

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

    # Check rclone is installed
    if ! command -v rclone &>/dev/null; then
        log_error "rclone is not installed"
        log_info "Install with: brew install rclone (macOS) or apt install rclone (Linux)"
        exit 1
    fi

    # Config command
    if [[ "$COMMAND" == "config" ]]; then
        exec rclone config
    fi

    # Build rclone command
    local rclone_opts=()

    # Verbose
    [[ "$VERBOSE" == "true" ]] && rclone_opts+=(-v)

    # Dry run
    [[ "$DRY_RUN" == "true" ]] && rclone_opts+=(--dry-run)

    # Progress
    [[ "$PROGRESS" == "true" ]] && rclone_opts+=(--progress)

    # Transfers and checkers
    rclone_opts+=(--transfers "$TRANSFERS" --checkers "$CHECKERS")

    # Excludes
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        rclone_opts+=(--exclude "$pattern")
    done

    # Includes
    for pattern in "${INCLUDE_PATTERNS[@]}"; do
        rclone_opts+=(--include "$pattern")
    done

    # Filter file
    [[ -n "$FILTER_FILE" ]] && rclone_opts+=(--filter-from "$FILTER_FILE")

    # Bandwidth limit
    [[ -n "$BANDWIDTH" ]] && rclone_opts+=(--bwlimit "$BANDWIDTH")

    # Age filters
    [[ -n "$MIN_AGE" ]] && rclone_opts+=(--min-age "$MIN_AGE")
    [[ -n "$MAX_AGE" ]] && rclone_opts+=(--max-age "$MAX_AGE")

    # Size filters
    [[ -n "$MIN_SIZE" ]] && rclone_opts+=(--min-size "$MIN_SIZE")
    [[ -n "$MAX_SIZE" ]] && rclone_opts+=(--max-size "$MAX_SIZE")

    # Compare mode
    case "$COMPARE_MODE" in
        checksum) rclone_opts+=(--checksum) ;;
        size) rclone_opts+=(--size-only) ;;
    esac

    # Empty dirs
    [[ "$CREATE_EMPTY_DIRS" == "true" ]] && rclone_opts+=(--create-empty-src-dirs)

    # Backup dir (for versioning)
    [[ -n "$BACKUP_DIR" ]] && rclone_opts+=(--backup-dir "$BACKUP_DIR")
    [[ -n "$SUFFIX" ]] && rclone_opts+=(--suffix "$SUFFIX")

    # Logging
    rclone_opts+=(--log-level "$LOG_LEVEL")
    [[ -n "$LOG_FILE" ]] && rclone_opts+=(--log-file "$LOG_FILE")

    # Stats
    rclone_opts+=(--stats "$STATS_INTERVAL")

    log_info "Starting rclone $COMMAND..."
    log_info "Source: $SOURCE"
    log_info "Destination: $DEST"

    rclone "$COMMAND" "${rclone_opts[@]}" "$SOURCE" "$DEST"

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_ok "Rclone $COMMAND completed successfully"
    else
        log_error "Rclone $COMMAND failed with exit code: $exit_code"
    fi

    return $exit_code
}

main "$@"

