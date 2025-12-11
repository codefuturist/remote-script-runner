#!/usr/bin/env bash
# =============================================================================
# @name         kopia-backup
# @description  Fast, encrypted, deduplicated backup using Kopia
# @version      1.0.0
# @author       RSR Team
# @license      MIT
# @requires     bash 4.0+, kopia
# =============================================================================
#
# Kopia features:
#   - Fast deduplication
#   - Encryption by default
#   - Compression (gzip, zstd, s2, pgzip)
#   - Multiple backends (local, S3, GCS, Azure, SFTP, WebDAV)
#   - Built-in server mode
#   - Snapshot policies
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

readonly SCRIPT_NAME="Kopia Backup"
readonly SCRIPT_VERSION="1.0.0"

VERBOSE=false
DRY_RUN=false
COMMAND="snapshot"
SUBCOMMAND=""
REPO_PATH=""
REPO_TYPE="filesystem"
PASSWORD=""
CONFIG_FILE=""
PATHS=()
EXCLUDE_PATTERNS=()
TAGS=()
DESCRIPTION=""
COMPRESSION="zstd"
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=1
SNAPSHOT_ID=""
TARGET=""
PARALLEL=0
JSON_OUTPUT=false

# Remote storage settings
S3_BUCKET=""
S3_ENDPOINT=""
S3_REGION=""
GCS_BUCKET=""
AZURE_CONTAINER=""
SFTP_HOST=""
SFTP_USER=""
SFTP_PATH=""

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
Kopia Backup - Fast, encrypted, deduplicated backups

USAGE:
    kopia-backup.sh [COMMAND] [OPTIONS] [PATHS...]

COMMANDS:
    snapshot        Create a snapshot (default)
    restore         Restore from snapshot
    list            List snapshots
    connect         Connect to existing repository
    create          Create new repository
    status          Show repository status
    policy          Manage retention policies
    maintenance     Run maintenance tasks
    server          Start Kopia server
    mount           Mount repository as filesystem

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be done
    --path PATH             Repository path (for filesystem)
    --type TYPE             Repository type: filesystem, s3, gcs, azure, sftp
    -p, --password PWD      Repository password (or set KOPIA_PASSWORD)
    --config FILE           Config file path
    -x, --exclude PATTERN   Exclude pattern (can be repeated)
    -t, --tag TAG           Add tag to snapshot (can be repeated)
    --description TEXT      Snapshot description
    --compression MODE      Compression: none, gzip, zstd, s2, pgzip (default: zstd)
    --snapshot ID           Snapshot ID for restore
    --target PATH           Restore target path
    --parallel N            Parallel operations (0=auto)
    --json                  Output in JSON format

S3 OPTIONS:
    --s3-bucket BUCKET      S3 bucket name
    --s3-endpoint URL       S3 endpoint URL
    --s3-region REGION      S3 region

GCS OPTIONS:
    --gcs-bucket BUCKET     GCS bucket name

AZURE OPTIONS:
    --azure-container NAME  Azure container name

SFTP OPTIONS:
    --sftp-host HOST        SFTP host
    --sftp-user USER        SFTP username
    --sftp-path PATH        SFTP path

RETENTION OPTIONS:
    --keep-daily N          Keep N daily snapshots (default: 7)
    --keep-weekly N         Keep N weekly snapshots (default: 4)
    --keep-monthly N        Keep N monthly snapshots (default: 6)
    --keep-yearly N         Keep N yearly snapshots (default: 1)

EXAMPLES:
    # Create local repository
    kopia-backup.sh create --path /backup/kopia

    # Create snapshot
    kopia-backup.sh snapshot /home /etc

    # List snapshots
    kopia-backup.sh list

    # Restore snapshot
    kopia-backup.sh restore --snapshot abc123 --target /restore

    # Connect to S3 repository
    kopia-backup.sh connect --type s3 --s3-bucket mybucket --s3-region us-east-1

    # Set retention policy
    kopia-backup.sh policy set --keep-daily 7 --keep-weekly 4

    # Run maintenance
    kopia-backup.sh maintenance run

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
            snapshot|restore|list|connect|create|status|policy|maintenance|server|mount)
                COMMAND="$1"
                shift
                # Check for subcommand
                if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                    case "$1" in
                        create|list|show|set|run|start|stop)
                            SUBCOMMAND="$1"
                            shift
                            ;;
                    esac
                fi
                ;;
        esac
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) show_help; exit 0 ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            --path) REPO_PATH="$2"; shift 2 ;;
            --type) REPO_TYPE="$2"; shift 2 ;;
            -p|--password) PASSWORD="$2"; shift 2 ;;
            --config) CONFIG_FILE="$2"; shift 2 ;;
            -x|--exclude) EXCLUDE_PATTERNS+=("$2"); shift 2 ;;
            -t|--tag) TAGS+=("$2"); shift 2 ;;
            --description) DESCRIPTION="$2"; shift 2 ;;
            --compression) COMPRESSION="$2"; shift 2 ;;
            --snapshot) SNAPSHOT_ID="$2"; shift 2 ;;
            --target) TARGET="$2"; shift 2 ;;
            --parallel) PARALLEL="$2"; shift 2 ;;
            --json) JSON_OUTPUT=true; shift ;;
            --s3-bucket) S3_BUCKET="$2"; shift 2 ;;
            --s3-endpoint) S3_ENDPOINT="$2"; shift 2 ;;
            --s3-region) S3_REGION="$2"; shift 2 ;;
            --gcs-bucket) GCS_BUCKET="$2"; shift 2 ;;
            --azure-container) AZURE_CONTAINER="$2"; shift 2 ;;
            --sftp-host) SFTP_HOST="$2"; shift 2 ;;
            --sftp-user) SFTP_USER="$2"; shift 2 ;;
            --sftp-path) SFTP_PATH="$2"; shift 2 ;;
            --keep-daily) KEEP_DAILY="$2"; shift 2 ;;
            --keep-weekly) KEEP_WEEKLY="$2"; shift 2 ;;
            --keep-monthly) KEEP_MONTHLY="$2"; shift 2 ;;
            --keep-yearly) KEEP_YEARLY="$2"; shift 2 ;;
            --) shift; PATHS+=("$@"); break ;;
            -*) log_error "Unknown option: $1"; exit 1 ;;
            *) PATHS+=("$1"); shift ;;
        esac
    done

    # Password from environment
    [[ -z "$PASSWORD" ]] && PASSWORD="${KOPIA_PASSWORD:-}"
}

# =============================================================================
# Commands
# =============================================================================

cmd_create() {
    log_info "Creating kopia repository..."

    local opts=()

    case "$REPO_TYPE" in
        filesystem)
            if [[ -z "$REPO_PATH" ]]; then
                log_error "Repository path required. Use --path"
                exit 1
            fi
            opts=(filesystem --path "$REPO_PATH")
            ;;
        s3)
            if [[ -z "$S3_BUCKET" ]]; then
                log_error "S3 bucket required. Use --s3-bucket"
                exit 1
            fi
            opts=(s3 --bucket "$S3_BUCKET")
            [[ -n "$S3_ENDPOINT" ]] && opts+=(--endpoint "$S3_ENDPOINT")
            [[ -n "$S3_REGION" ]] && opts+=(--region "$S3_REGION")
            ;;
        gcs)
            if [[ -z "$GCS_BUCKET" ]]; then
                log_error "GCS bucket required. Use --gcs-bucket"
                exit 1
            fi
            opts=(gcs --bucket "$GCS_BUCKET")
            ;;
        azure)
            if [[ -z "$AZURE_CONTAINER" ]]; then
                log_error "Azure container required. Use --azure-container"
                exit 1
            fi
            opts=(azure --container "$AZURE_CONTAINER")
            ;;
        sftp)
            if [[ -z "$SFTP_HOST" ]] || [[ -z "$SFTP_USER" ]]; then
                log_error "SFTP host and user required"
                exit 1
            fi
            opts=(sftp --host "$SFTP_HOST" --username "$SFTP_USER")
            [[ -n "$SFTP_PATH" ]] && opts+=(--path "$SFTP_PATH")
            ;;
        *)
            log_error "Unknown repository type: $REPO_TYPE"
            exit 1
            ;;
    esac

    if [[ -n "$PASSWORD" ]]; then
        opts+=(--password "$PASSWORD")
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run - would create repository"
        return 0
    fi

    kopia repository create "${opts[@]}"
}

cmd_connect() {
    log_info "Connecting to kopia repository..."

    local opts=()

    case "$REPO_TYPE" in
        filesystem)
            opts=(filesystem --path "$REPO_PATH")
            ;;
        s3)
            opts=(s3 --bucket "$S3_BUCKET")
            [[ -n "$S3_ENDPOINT" ]] && opts+=(--endpoint "$S3_ENDPOINT")
            [[ -n "$S3_REGION" ]] && opts+=(--region "$S3_REGION")
            ;;
        gcs)
            opts=(gcs --bucket "$GCS_BUCKET")
            ;;
        azure)
            opts=(azure --container "$AZURE_CONTAINER")
            ;;
        sftp)
            opts=(sftp --host "$SFTP_HOST" --username "$SFTP_USER")
            [[ -n "$SFTP_PATH" ]] && opts+=(--path "$SFTP_PATH")
            ;;
    esac

    if [[ -n "$PASSWORD" ]]; then
        opts+=(--password "$PASSWORD")
    fi

    kopia repository connect "${opts[@]}"
}

cmd_snapshot() {
    if [[ ${#PATHS[@]} -eq 0 ]]; then
        log_error "No paths specified for snapshot"
        exit 1
    fi

    log_info "Creating kopia snapshot..."
    log_info "Paths: ${PATHS[*]}"

    local opts=()

    [[ "$JSON_OUTPUT" == "true" ]] && opts+=(--json)

    # Excludes
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        opts+=(--add-ignore "$pattern")
    done

    # Tags
    for tag in "${TAGS[@]}"; do
        opts+=(--tags "$tag")
    done

    # Description
    [[ -n "$DESCRIPTION" ]] && opts+=(--description "$DESCRIPTION")

    # Parallel
    [[ "$PARALLEL" -gt 0 ]] && opts+=(--parallel "$PARALLEL")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run - would create snapshot"
        return 0
    fi

    kopia snapshot create "${opts[@]}" "${PATHS[@]}"
}

cmd_restore() {
    if [[ -z "$SNAPSHOT_ID" ]]; then
        log_error "Snapshot ID required. Use --snapshot"
        exit 1
    fi

    if [[ -z "$TARGET" ]]; then
        log_error "Restore target required. Use --target"
        exit 1
    fi

    log_info "Restoring from kopia snapshot..."
    log_info "Snapshot: $SNAPSHOT_ID"
    log_info "Target: $TARGET"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run - would restore snapshot"
        return 0
    fi

    mkdir -p "$TARGET"
    kopia snapshot restore "$SNAPSHOT_ID" "$TARGET"
}

cmd_list() {
    local opts=()

    [[ "$JSON_OUTPUT" == "true" ]] && opts+=(--json)

    kopia snapshot list "${opts[@]}"
}

cmd_status() {
    kopia repository status
}

cmd_policy() {
    case "${SUBCOMMAND:-list}" in
        set)
            log_info "Setting retention policy..."
            kopia policy set --global \
                --keep-daily "$KEEP_DAILY" \
                --keep-weekly "$KEEP_WEEKLY" \
                --keep-monthly "$KEEP_MONTHLY" \
                --keep-yearly "$KEEP_YEARLY"
            ;;
        list|show)
            kopia policy list
            ;;
        *)
            log_error "Unknown policy subcommand: $SUBCOMMAND"
            exit 1
            ;;
    esac
}

cmd_maintenance() {
    case "${SUBCOMMAND:-run}" in
        run)
            log_info "Running kopia maintenance..."

            local opts=()
            [[ "$VERBOSE" == "true" ]] && opts+=(--full)

            kopia maintenance run "${opts[@]}"
            ;;
        *)
            log_error "Unknown maintenance subcommand: $SUBCOMMAND"
            exit 1
            ;;
    esac
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Check kopia is installed
    if ! command -v kopia &>/dev/null; then
        log_error "kopia is not installed"
        log_info "Install with: brew install kopia (macOS) or see https://kopia.io/docs/installation/"
        exit 1
    fi

    # Config file
    [[ -n "$CONFIG_FILE" ]] && export KOPIA_CONFIG_PATH="$CONFIG_FILE"

    case "$COMMAND" in
        create) cmd_create ;;
        connect) cmd_connect ;;
        snapshot) cmd_snapshot ;;
        restore) cmd_restore ;;
        list) cmd_list ;;
        status) cmd_status ;;
        policy) cmd_policy ;;
        maintenance) cmd_maintenance ;;
        *)
            log_error "Unknown command: $COMMAND"
            exit 1
            ;;
    esac

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_ok "Kopia $COMMAND completed successfully"
    fi

    return $exit_code
}

main "$@"

