#!/usr/bin/env bash
# =============================================================================
# @name         restic-backup
# @description  Secure, deduplicated backup using restic
# @version      1.0.0
# @author       RSR Team
# @license      MIT
# @requires     bash 4.0+, restic
# =============================================================================
#
# Restic features:
#   - Fast deduplication
#   - Encryption by default
#   - Multiple backends (local, S3, SFTP, rest-server)
#   - Efficient incremental backups
#   - Easy restores
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
    [[ -f "$RSR_LIB_DIR/modules/backup.sh" ]] && source "$RSR_LIB_DIR/modules/backup.sh"
else
    echo "ERROR: RSR library not found" >&2
    exit 1
fi

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_NAME="Restic Backup"
readonly SCRIPT_VERSION="1.0.0"

VERBOSE=false
DRY_RUN=false
COMMAND="backup"
REPO=""
PASSWORD=""
PASSWORD_FILE=""
PATHS=()
EXCLUDE_PATTERNS=()
EXCLUDE_FILE=""
TAGS=()
HOST=""
SNAPSHOT_ID=""
TARGET=""
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=1
COMPRESSION="auto"
PACK_SIZE=""
CACHE_DIR=""
NO_CACHE=false
QUIET=false
JSON_OUTPUT=false

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
Restic Backup - Fast, secure, deduplicated backups

USAGE:
    restic-backup.sh [COMMAND] [OPTIONS] [PATHS...]

COMMANDS:
    backup      Create a new backup (default)
    restore     Restore files from a snapshot
    snapshots   List available snapshots
    init        Initialize a new repository
    check       Verify repository integrity
    prune       Remove old snapshots
    forget      Remove snapshots by policy
    mount       Mount repository as FUSE filesystem
    diff        Show differences between snapshots
    stats       Show repository statistics
    key         Manage repository keys
    unlock      Remove stale locks

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be done
    -r, --repo REPO         Repository location (required)
    -p, --password PWD      Repository password (or set RESTIC_PASSWORD)
    --password-file FILE    Read password from file
    -x, --exclude PATTERN   Exclude pattern (can be repeated)
    --exclude-file FILE     Read exclude patterns from file
    -t, --tag TAG           Add tag to snapshot (can be repeated)
    --host HOST             Set hostname for snapshot
    --snapshot ID           Snapshot ID for restore/diff
    --target PATH           Restore target path
    --compression MODE      Compression: auto, off, max (default: auto)
    --pack-size SIZE        Target pack size in MiB
    --cache-dir DIR         Custom cache directory
    --no-cache              Disable caching
    -q, --quiet             Suppress output
    --json                  Output in JSON format

RETENTION OPTIONS (for forget/prune):
    --keep-daily N          Keep N daily snapshots (default: 7)
    --keep-weekly N         Keep N weekly snapshots (default: 4)
    --keep-monthly N        Keep N monthly snapshots (default: 6)
    --keep-yearly N         Keep N yearly snapshots (default: 1)

REPOSITORY FORMATS:
    Local:      /path/to/repo
    SFTP:       sftp:user@host:/path/to/repo
    S3:         s3:s3.amazonaws.com/bucket
    S3 (Minio): s3:http://localhost:9000/bucket
    B2:         b2:bucket:path/to/repo
    Azure:      azure:container:/path
    GCS:        gs:bucket:/path
    Rest:       rest:http://host:8000/

EXAMPLES:
    # Initialize repository
    restic-backup.sh init -r /backup/restic-repo

    # Backup with tags
    restic-backup.sh backup -r /backup/repo -t daily /home /etc

    # List snapshots
    restic-backup.sh snapshots -r /backup/repo

    # Restore latest
    restic-backup.sh restore -r /backup/repo --target /restore

    # Restore specific snapshot
    restic-backup.sh restore -r /backup/repo --snapshot abc123 --target /restore

    # Apply retention policy
    restic-backup.sh forget -r /backup/repo --keep-daily 7 --keep-weekly 4 --prune

    # Check repository
    restic-backup.sh check -r /backup/repo

    # Backup to S3
    export AWS_ACCESS_KEY_ID=xxx
    export AWS_SECRET_ACCESS_KEY=yyy
    restic-backup.sh backup -r s3:s3.amazonaws.com/mybucket /home

EOF
}

# =============================================================================
# Logging
# =============================================================================

log_info() { [[ "$QUIET" != "true" ]] && echo -e "${RSR_COLOR_BLUE:-}▸${RSR_COLOR_RESET:-} $1"; }
log_ok() { [[ "$QUIET" != "true" ]] && echo -e "${RSR_COLOR_GREEN:-}✓${RSR_COLOR_RESET:-} $1"; }
log_warn() { echo -e "${RSR_COLOR_YELLOW:-}⚠${RSR_COLOR_RESET:-} $1" >&2; }
log_error() { echo -e "${RSR_COLOR_RED:-}✗${RSR_COLOR_RESET:-} $1" >&2; }

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    # Check for command
    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
        case "$1" in
            backup | restore | snapshots | init | check | prune | forget | mount | diff | stats | key | unlock)
                COMMAND="$1"
                shift
                ;;
        esac
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
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            -r | --repo)
                REPO="$2"
                shift 2
                ;;
            -p | --password)
                PASSWORD="$2"
                shift 2
                ;;
            --password-file)
                PASSWORD_FILE="$2"
                shift 2
                ;;
            -x | --exclude)
                EXCLUDE_PATTERNS+=("$2")
                shift 2
                ;;
            --exclude-file)
                EXCLUDE_FILE="$2"
                shift 2
                ;;
            -t | --tag)
                TAGS+=("$2")
                shift 2
                ;;
            --host)
                HOST="$2"
                shift 2
                ;;
            --snapshot)
                SNAPSHOT_ID="$2"
                shift 2
                ;;
            --target)
                TARGET="$2"
                shift 2
                ;;
            --compression)
                COMPRESSION="$2"
                shift 2
                ;;
            --pack-size)
                PACK_SIZE="$2"
                shift 2
                ;;
            --cache-dir)
                CACHE_DIR="$2"
                shift 2
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            -q | --quiet)
                QUIET=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
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
            --prune)
                PRUNE=true
                shift
                ;;
            --)
                shift
                PATHS+=("$@")
                break
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                PATHS+=("$1")
                shift
                ;;
        esac
    done

    # Repository required for most commands
    if [[ -z "$REPO" ]]; then
        REPO="${RESTIC_REPOSITORY:-}"
        if [[ -z "$REPO" ]]; then
            log_error "Repository required. Use -r/--repo or set RESTIC_REPOSITORY"
            exit 1
        fi
    fi

    # Password handling
    if [[ -z "$PASSWORD" ]] && [[ -z "$PASSWORD_FILE" ]]; then
        PASSWORD="${RESTIC_PASSWORD:-}"
        PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-}"
    fi
}

# =============================================================================
# Commands
# =============================================================================

cmd_init() {
    log_info "Initializing restic repository..."
    log_info "Repository: $REPO"

    local opts=()
    [[ -n "$PASSWORD_FILE" ]] && opts+=(--password-file "$PASSWORD_FILE")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run - would initialize: $REPO"
        return 0
    fi

    if [[ -n "$PASSWORD" ]]; then
        RESTIC_PASSWORD="$PASSWORD" restic init -r "$REPO" "${opts[@]}"
    else
        restic init -r "$REPO" "${opts[@]}"
    fi
}

cmd_backup() {
    if [[ ${#PATHS[@]} -eq 0 ]]; then
        log_error "No paths specified for backup"
        exit 1
    fi

    log_info "Creating restic backup..."
    log_info "Repository: $REPO"
    log_info "Paths: ${PATHS[*]}"

    local opts=(-r "$REPO")

    # Verbose
    [[ "$VERBOSE" == "true" ]] && opts+=(-v)

    # Dry run
    [[ "$DRY_RUN" == "true" ]] && opts+=(-n)

    # Password
    [[ -n "$PASSWORD_FILE" ]] && opts+=(--password-file "$PASSWORD_FILE")

    # Excludes
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        opts+=(--exclude "$pattern")
    done
    [[ -n "$EXCLUDE_FILE" ]] && opts+=(--exclude-file "$EXCLUDE_FILE")

    # Tags
    for tag in "${TAGS[@]}"; do
        opts+=(--tag "$tag")
    done

    # Host
    [[ -n "$HOST" ]] && opts+=(--host "$HOST")

    # Compression
    [[ -n "$COMPRESSION" ]] && opts+=(--compression "$COMPRESSION")

    # Pack size
    [[ -n "$PACK_SIZE" ]] && opts+=(--pack-size "$PACK_SIZE")

    # Cache
    [[ -n "$CACHE_DIR" ]] && opts+=(--cache-dir "$CACHE_DIR")
    [[ "$NO_CACHE" == "true" ]] && opts+=(--no-cache)

    # JSON output
    [[ "$JSON_OUTPUT" == "true" ]] && opts+=(--json)

    if [[ -n "$PASSWORD" ]]; then
        RESTIC_PASSWORD="$PASSWORD" restic backup "${opts[@]}" "${PATHS[@]}"
    else
        restic backup "${opts[@]}" "${PATHS[@]}"
    fi
}

cmd_restore() {
    if [[ -z "$TARGET" ]]; then
        log_error "Restore target required. Use --target"
        exit 1
    fi

    local snapshot="${SNAPSHOT_ID:-latest}"

    log_info "Restoring from restic backup..."
    log_info "Repository: $REPO"
    log_info "Snapshot: $snapshot"
    log_info "Target: $TARGET"

    local opts=(-r "$REPO")

    [[ "$VERBOSE" == "true" ]] && opts+=(-v)
    [[ -n "$PASSWORD_FILE" ]] && opts+=(--password-file "$PASSWORD_FILE")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run - would restore snapshot $snapshot to $TARGET"
        return 0
    fi

    mkdir -p "$TARGET"

    if [[ -n "$PASSWORD" ]]; then
        RESTIC_PASSWORD="$PASSWORD" restic restore "${opts[@]}" "$snapshot" --target "$TARGET"
    else
        restic restore "${opts[@]}" "$snapshot" --target "$TARGET"
    fi
}

cmd_snapshots() {
    local opts=(-r "$REPO")

    [[ -n "$PASSWORD_FILE" ]] && opts+=(--password-file "$PASSWORD_FILE")
    [[ "$JSON_OUTPUT" == "true" ]] && opts+=(--json)
    [[ -n "$HOST" ]] && opts+=(--host "$HOST")

    for tag in "${TAGS[@]}"; do
        opts+=(--tag "$tag")
    done

    if [[ -n "$PASSWORD" ]]; then
        RESTIC_PASSWORD="$PASSWORD" restic snapshots "${opts[@]}"
    else
        restic snapshots "${opts[@]}"
    fi
}

cmd_check() {
    log_info "Checking restic repository..."

    local opts=(-r "$REPO")

    [[ "$VERBOSE" == "true" ]] && opts+=(-v)
    [[ -n "$PASSWORD_FILE" ]] && opts+=(--password-file "$PASSWORD_FILE")

    if [[ -n "$PASSWORD" ]]; then
        RESTIC_PASSWORD="$PASSWORD" restic check "${opts[@]}"
    else
        restic check "${opts[@]}"
    fi
}

cmd_forget() {
    log_info "Applying retention policy..."

    local opts=(-r "$REPO")

    [[ "$VERBOSE" == "true" ]] && opts+=(-v)
    [[ "$DRY_RUN" == "true" ]] && opts+=(-n)
    [[ -n "$PASSWORD_FILE" ]] && opts+=(--password-file "$PASSWORD_FILE")

    opts+=(--keep-daily "$KEEP_DAILY")
    opts+=(--keep-weekly "$KEEP_WEEKLY")
    opts+=(--keep-monthly "$KEEP_MONTHLY")
    opts+=(--keep-yearly "$KEEP_YEARLY")

    [[ "${PRUNE:-false}" == "true" ]] && opts+=(--prune)

    [[ -n "$HOST" ]] && opts+=(--host "$HOST")
    for tag in "${TAGS[@]}"; do
        opts+=(--tag "$tag")
    done

    if [[ -n "$PASSWORD" ]]; then
        RESTIC_PASSWORD="$PASSWORD" restic forget "${opts[@]}"
    else
        restic forget "${opts[@]}"
    fi
}

cmd_prune() {
    log_info "Pruning repository..."

    local opts=(-r "$REPO")

    [[ "$VERBOSE" == "true" ]] && opts+=(-v)
    [[ "$DRY_RUN" == "true" ]] && opts+=(-n)
    [[ -n "$PASSWORD_FILE" ]] && opts+=(--password-file "$PASSWORD_FILE")

    if [[ -n "$PASSWORD" ]]; then
        RESTIC_PASSWORD="$PASSWORD" restic prune "${opts[@]}"
    else
        restic prune "${opts[@]}"
    fi
}

cmd_stats() {
    local opts=(-r "$REPO")

    [[ -n "$PASSWORD_FILE" ]] && opts+=(--password-file "$PASSWORD_FILE")
    [[ "$JSON_OUTPUT" == "true" ]] && opts+=(--json)

    if [[ -n "$PASSWORD" ]]; then
        RESTIC_PASSWORD="$PASSWORD" restic stats "${opts[@]}"
    else
        restic stats "${opts[@]}"
    fi
}

cmd_unlock() {
    log_info "Removing stale locks..."

    local opts=(-r "$REPO")
    [[ -n "$PASSWORD_FILE" ]] && opts+=(--password-file "$PASSWORD_FILE")

    if [[ -n "$PASSWORD" ]]; then
        RESTIC_PASSWORD="$PASSWORD" restic unlock "${opts[@]}"
    else
        restic unlock "${opts[@]}"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Check restic is installed
    if ! command -v restic &> /dev/null; then
        log_error "restic is not installed"
        log_info "Install with: brew install restic (macOS) or apt install restic (Linux)"
        exit 1
    fi

    case "$COMMAND" in
        init) cmd_init ;;
        backup) cmd_backup ;;
        restore) cmd_restore ;;
        snapshots) cmd_snapshots ;;
        check) cmd_check ;;
        forget) cmd_forget ;;
        prune) cmd_prune ;;
        stats) cmd_stats ;;
        unlock) cmd_unlock ;;
        *)
            log_error "Unknown command: $COMMAND"
            exit 1
            ;;
    esac

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_ok "Restic $COMMAND completed successfully"
    fi

    return $exit_code
}

main "$@"
