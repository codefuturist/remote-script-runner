#!/usr/bin/env bash
# =============================================================================
# @name         borg-backup
# @description  Deduplicating archiver with compression and encryption
# @version      1.0.0
# @author       RSR Team
# @license      MIT
# @requires     bash 4.0+, borg
# =============================================================================
#
# Borg Backup features:
#   - Deduplication at chunk level
#   - Compression (lz4, zstd, zlib, lzma)
#   - Encryption (AES-256)
#   - Remote repositories via SSH
#   - Append-only mode for ransomware protection
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

readonly SCRIPT_NAME="Borg Backup"
readonly SCRIPT_VERSION="1.0.0"

VERBOSE=false
DRY_RUN=false
COMMAND="create"
REPO=""
PASSWORD=""
PATHS=()
ARCHIVE_NAME=""
EXCLUDE_PATTERNS=()
EXCLUDE_FILE=""
COMPRESSION="lz4"
ENCRYPTION="repokey"
APPEND_ONLY=false
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=1
CHECKPOINT_INTERVAL=1800
ONE_FILE_SYSTEM=false
STATS=true
PROGRESS=true
LIST_FILES=false
JSON_OUTPUT=false
REMOTE_PATH=""
RSH=""
TARGET=""
ARCHIVE=""

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
Borg Backup - Deduplicating archiver with compression

USAGE:
    borg-backup.sh [COMMAND] [OPTIONS] [PATHS...]

COMMANDS:
    create      Create a new archive (default)
    extract     Extract files from an archive
    list        List archives or archive contents
    init        Initialize a new repository
    check       Check repository consistency
    prune       Remove old archives
    info        Show repository/archive information
    mount       Mount repository/archive as FUSE filesystem
    diff        Show differences between archives
    delete      Delete archive(s)
    compact     Free space in repository
    key         Manage repository keys

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be done
    -r, --repo REPO         Repository location (required)
    -a, --archive NAME      Archive name (for create/extract)
    -p, --password PWD      Repository password (or set BORG_PASSPHRASE)
    -x, --exclude PATTERN   Exclude pattern (can be repeated)
    --exclude-from FILE     Read exclude patterns from file
    -C, --compression MODE  Compression: none, lz4, zstd, zlib, lzma (default: lz4)
    -e, --encryption MODE   Encryption: none, repokey, keyfile (default: repokey)
    --append-only           Create append-only mode repository
    --one-file-system       Don't cross filesystem boundaries
    --checkpoint N          Save checkpoint every N seconds (default: 1800)
    --no-progress           Disable progress display
    --list                  List files as they are processed
    --json                  Output in JSON format
    --remote-path PATH      Path to borg on remote host
    --rsh COMMAND           Remote shell command
    --target PATH           Extract target path

RETENTION OPTIONS (for prune):
    --keep-daily N          Keep N daily archives (default: 7)
    --keep-weekly N         Keep N weekly archives (default: 4)
    --keep-monthly N        Keep N monthly archives (default: 6)
    --keep-yearly N         Keep N yearly archives (default: 1)

REPOSITORY FORMATS:
    Local:      /path/to/repo
    SSH:        user@host:/path/to/repo
    SSH+Port:   ssh://user@host:port/./path/to/repo

ARCHIVE NAMING:
    Use placeholders: {hostname}, {user}, {now}, {utcnow}
    Example: {hostname}-{now:%Y-%m-%d_%H:%M}

EXAMPLES:
    # Initialize encrypted repository
    borg-backup.sh init -r /backup/borg-repo

    # Create backup with timestamp
    borg-backup.sh create -r /backup/borg -a "backup-{now}" /home /etc

    # List archives
    borg-backup.sh list -r /backup/borg

    # Extract latest archive
    borg-backup.sh extract -r /backup/borg -a latest --target /restore

    # Prune old archives
    borg-backup.sh prune -r /backup/borg --keep-daily 7 --keep-weekly 4

    # Remote backup
    borg-backup.sh create -r user@server:/backup/borg -a "daily" /home

    # High compression backup
    borg-backup.sh create -r /backup/borg -C zstd,10 /data

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
    # Check for command
    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
        case "$1" in
            create|extract|list|init|check|prune|info|mount|diff|delete|compact|key)
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
            -r|--repo) REPO="$2"; shift 2 ;;
            -a|--archive) ARCHIVE_NAME="$2"; shift 2 ;;
            -p|--password) PASSWORD="$2"; shift 2 ;;
            -x|--exclude) EXCLUDE_PATTERNS+=("$2"); shift 2 ;;
            --exclude-from) EXCLUDE_FILE="$2"; shift 2 ;;
            -C|--compression) COMPRESSION="$2"; shift 2 ;;
            -e|--encryption) ENCRYPTION="$2"; shift 2 ;;
            --append-only) APPEND_ONLY=true; shift ;;
            --one-file-system) ONE_FILE_SYSTEM=true; shift ;;
            --checkpoint) CHECKPOINT_INTERVAL="$2"; shift 2 ;;
            --no-progress) PROGRESS=false; shift ;;
            --list) LIST_FILES=true; shift ;;
            --json) JSON_OUTPUT=true; shift ;;
            --remote-path) REMOTE_PATH="$2"; shift 2 ;;
            --rsh) RSH="$2"; shift 2 ;;
            --target) TARGET="$2"; shift 2 ;;
            --keep-daily) KEEP_DAILY="$2"; shift 2 ;;
            --keep-weekly) KEEP_WEEKLY="$2"; shift 2 ;;
            --keep-monthly) KEEP_MONTHLY="$2"; shift 2 ;;
            --keep-yearly) KEEP_YEARLY="$2"; shift 2 ;;
            --) shift; PATHS+=("$@"); break ;;
            -*) log_error "Unknown option: $1"; exit 1 ;;
            *) PATHS+=("$1"); shift ;;
        esac
    done

    # Repository required
    if [[ -z "$REPO" ]]; then
        REPO="${BORG_REPO:-}"
        if [[ -z "$REPO" ]]; then
            log_error "Repository required. Use -r/--repo or set BORG_REPO"
            exit 1
        fi
    fi

    # Password handling
    [[ -z "$PASSWORD" ]] && PASSWORD="${BORG_PASSPHRASE:-}"

    # Default archive name for create
    if [[ "$COMMAND" == "create" ]] && [[ -z "$ARCHIVE_NAME" ]]; then
        ARCHIVE_NAME="{hostname}-{now:%Y-%m-%d_%H:%M:%S}"
    fi
}

# =============================================================================
# Commands
# =============================================================================

cmd_init() {
    log_info "Initializing borg repository..."
    log_info "Repository: $REPO"
    log_info "Encryption: $ENCRYPTION"

    local opts=(--encryption="$ENCRYPTION")

    [[ "$APPEND_ONLY" == "true" ]] && opts+=(--append-only)
    [[ -n "$REMOTE_PATH" ]] && opts+=(--remote-path "$REMOTE_PATH")
    [[ -n "$RSH" ]] && opts+=(--rsh "$RSH")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run - would initialize: $REPO"
        return 0
    fi

    if [[ -n "$PASSWORD" ]]; then
        BORG_PASSPHRASE="$PASSWORD" borg init "${opts[@]}" "$REPO"
    else
        borg init "${opts[@]}" "$REPO"
    fi
}

cmd_create() {
    if [[ ${#PATHS[@]} -eq 0 ]]; then
        log_error "No paths specified for backup"
        exit 1
    fi

    local archive="${REPO}::${ARCHIVE_NAME}"

    log_info "Creating borg archive..."
    log_info "Repository: $REPO"
    log_info "Archive: $ARCHIVE_NAME"
    log_info "Paths: ${PATHS[*]}"

    local opts=()

    # Verbose/progress
    [[ "$VERBOSE" == "true" ]] && opts+=(-v)
    [[ "$PROGRESS" == "true" ]] && opts+=(--progress)
    [[ "$LIST_FILES" == "true" ]] && opts+=(--list)

    # Dry run
    [[ "$DRY_RUN" == "true" ]] && opts+=(-n)

    # Stats
    [[ "$STATS" == "true" ]] && opts+=(--stats)

    # Compression
    opts+=(--compression "$COMPRESSION")

    # Excludes
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        opts+=(--exclude "$pattern")
    done
    [[ -n "$EXCLUDE_FILE" ]] && opts+=(--exclude-from "$EXCLUDE_FILE")

    # Filesystem options
    [[ "$ONE_FILE_SYSTEM" == "true" ]] && opts+=(--one-file-system)

    # Checkpoint
    opts+=(--checkpoint-interval "$CHECKPOINT_INTERVAL")

    # Remote
    [[ -n "$REMOTE_PATH" ]] && opts+=(--remote-path "$REMOTE_PATH")
    [[ -n "$RSH" ]] && opts+=(--rsh "$RSH")

    # JSON
    [[ "$JSON_OUTPUT" == "true" ]] && opts+=(--json)

    if [[ -n "$PASSWORD" ]]; then
        BORG_PASSPHRASE="$PASSWORD" borg create "${opts[@]}" "$archive" "${PATHS[@]}"
    else
        borg create "${opts[@]}" "$archive" "${PATHS[@]}"
    fi
}

cmd_extract() {
    if [[ -z "$ARCHIVE_NAME" ]]; then
        log_error "Archive name required. Use -a/--archive"
        exit 1
    fi

    local archive="${REPO}::${ARCHIVE_NAME}"
    local target="${TARGET:-.}"

    log_info "Extracting from borg archive..."
    log_info "Archive: $archive"
    log_info "Target: $target"

    local opts=()

    [[ "$VERBOSE" == "true" ]] && opts+=(-v)
    [[ "$PROGRESS" == "true" ]] && opts+=(--progress)
    [[ "$DRY_RUN" == "true" ]] && opts+=(-n)
    [[ "$LIST_FILES" == "true" ]] && opts+=(--list)
    [[ -n "$REMOTE_PATH" ]] && opts+=(--remote-path "$REMOTE_PATH")

    mkdir -p "$target"
    cd "$target"

    if [[ -n "$PASSWORD" ]]; then
        BORG_PASSPHRASE="$PASSWORD" borg extract "${opts[@]}" "$archive" "${PATHS[@]}"
    else
        borg extract "${opts[@]}" "$archive" "${PATHS[@]}"
    fi
}

cmd_list() {
    local opts=()

    [[ "$JSON_OUTPUT" == "true" ]] && opts+=(--json)
    [[ -n "$REMOTE_PATH" ]] && opts+=(--remote-path "$REMOTE_PATH")

    local target="$REPO"
    [[ -n "$ARCHIVE_NAME" ]] && target="${REPO}::${ARCHIVE_NAME}"

    if [[ -n "$PASSWORD" ]]; then
        BORG_PASSPHRASE="$PASSWORD" borg list "${opts[@]}" "$target"
    else
        borg list "${opts[@]}" "$target"
    fi
}

cmd_info() {
    local opts=()

    [[ "$JSON_OUTPUT" == "true" ]] && opts+=(--json)
    [[ -n "$REMOTE_PATH" ]] && opts+=(--remote-path "$REMOTE_PATH")

    local target="$REPO"
    [[ -n "$ARCHIVE_NAME" ]] && target="${REPO}::${ARCHIVE_NAME}"

    if [[ -n "$PASSWORD" ]]; then
        BORG_PASSPHRASE="$PASSWORD" borg info "${opts[@]}" "$target"
    else
        borg info "${opts[@]}" "$target"
    fi
}

cmd_check() {
    log_info "Checking borg repository..."

    local opts=()

    [[ "$VERBOSE" == "true" ]] && opts+=(-v)
    [[ "$PROGRESS" == "true" ]] && opts+=(--progress)
    [[ -n "$REMOTE_PATH" ]] && opts+=(--remote-path "$REMOTE_PATH")

    if [[ -n "$PASSWORD" ]]; then
        BORG_PASSPHRASE="$PASSWORD" borg check "${opts[@]}" "$REPO"
    else
        borg check "${opts[@]}" "$REPO"
    fi
}

cmd_prune() {
    log_info "Pruning borg repository..."
    log_info "Keep daily: $KEEP_DAILY"
    log_info "Keep weekly: $KEEP_WEEKLY"
    log_info "Keep monthly: $KEEP_MONTHLY"
    log_info "Keep yearly: $KEEP_YEARLY"

    local opts=()

    [[ "$VERBOSE" == "true" ]] && opts+=(-v)
    [[ "$DRY_RUN" == "true" ]] && opts+=(-n)
    [[ "$STATS" == "true" ]] && opts+=(--stats)
    [[ "$LIST_FILES" == "true" ]] && opts+=(--list)
    [[ -n "$REMOTE_PATH" ]] && opts+=(--remote-path "$REMOTE_PATH")

    opts+=(--keep-daily "$KEEP_DAILY")
    opts+=(--keep-weekly "$KEEP_WEEKLY")
    opts+=(--keep-monthly "$KEEP_MONTHLY")
    opts+=(--keep-yearly "$KEEP_YEARLY")

    if [[ -n "$PASSWORD" ]]; then
        BORG_PASSPHRASE="$PASSWORD" borg prune "${opts[@]}" "$REPO"
    else
        borg prune "${opts[@]}" "$REPO"
    fi
}

cmd_compact() {
    log_info "Compacting borg repository..."

    local opts=()

    [[ "$VERBOSE" == "true" ]] && opts+=(-v)
    [[ "$PROGRESS" == "true" ]] && opts+=(--progress)
    [[ -n "$REMOTE_PATH" ]] && opts+=(--remote-path "$REMOTE_PATH")

    if [[ -n "$PASSWORD" ]]; then
        BORG_PASSPHRASE="$PASSWORD" borg compact "${opts[@]}" "$REPO"
    else
        borg compact "${opts[@]}" "$REPO"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Check borg is installed
    if ! command -v borg &>/dev/null; then
        log_error "borg is not installed"
        log_info "Install with: brew install borgbackup (macOS) or apt install borgbackup (Linux)"
        exit 1
    fi

    case "$COMMAND" in
        init) cmd_init ;;
        create) cmd_create ;;
        extract) cmd_extract ;;
        list) cmd_list ;;
        info) cmd_info ;;
        check) cmd_check ;;
        prune) cmd_prune ;;
        compact) cmd_compact ;;
        *)
            log_error "Unknown command: $COMMAND"
            exit 1
            ;;
    esac

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_ok "Borg $COMMAND completed successfully"
    fi

    return $exit_code
}

main "$@"

