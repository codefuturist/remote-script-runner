#!/bin/bash
# =============================================================================
# @id           db-backup
# @name         database-backup
# @displayName  Database Backup
# @description  Backup MySQL/PostgreSQL databases with compression and encryption
# @category     maintenance
# @version      1.0.0
# @author       codefuturist
# @tags         database,backup,mysql,mariadb,postgresql,dump,maintenance
# @shells       bash
# =============================================================================

set -euo pipefail

# Source interactive utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/../../lib/interactive.sh" ]] && source "$SCRIPT_DIR/../../lib/interactive.sh"

# Script metadata
SCRIPT_NAME="Database Backup"
SCRIPT_VERSION="1.0.0"

# Default values
VERBOSE=false
DRY_RUN=false
INTERACTIVE=auto
DB_TYPE=""
AUTO_DETECT=false
DATABASE=""
ALL_DATABASES=false
SCHEMA_ONLY=false
DATA_ONLY=false
OUTPUT_DIR="/var/backups/databases"
COMPRESS="gzip"
DO_ENCRYPT=false
GPG_KEY=""
PARALLEL=1
UPLOAD_DEST=""
RETENTION=7
DO_VERIFY=false
INCLUDE_PITR=false
LIST_BACKUPS=false
RESTORE_FILE=""
RESTORE_DB=""

# Database credentials (from environment or defaults)
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"

PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-}"
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"

MONGO_USER="${MONGO_USER:-}"
MONGO_PASSWORD="${MONGO_PASSWORD:-}"
MONGO_HOST="${MONGO_HOST:-localhost}"
MONGO_PORT="${MONGO_PORT:-27017}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Exit codes
EXIT_OK=0
EXIT_ERROR=1
EXIT_INVALID_ARGS=2
EXIT_PERMISSION=3
EXIT_DB_NOT_FOUND=4
EXIT_DUMP_FAILED=5
EXIT_COMPRESS_FAIL=6
EXIT_ENCRYPT_FAIL=7
EXIT_UPLOAD_FAIL=8
EXIT_RESTORE_FAIL=9

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Backup MySQL, PostgreSQL, and MongoDB databases with compression and encryption.

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${BOLD}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -i, --interactive       Run in interactive mode (default when no args)
    --no-interactive        Disable interactive mode
    -y, --yes               Auto-confirm all prompts
    --mysql                 Backup MySQL/MariaDB
    --postgresql            Backup PostgreSQL
    --mongodb               Backup MongoDB
    --auto                  Auto-detect databases
    -d, --database DB       Backup specific database
    -A, --all-databases     Backup all databases
    --schema-only           Dump schema only
    --data-only             Dump data only
    -o, --output DIR        Output directory (default: /var/backups/databases)
    --compress METHOD       Compression: gzip, xz, lz4, none (default: gzip)
    --encrypt               Encrypt with GPG
    --gpg-key KEY           GPG key ID
    --parallel N            Parallel threads (PostgreSQL only)
    --upload DEST           Upload to remote storage
    --retention N           Keep N most recent backups (default: 7)
    --verify                Verify backup after creation
    --pitr                  Include point-in-time recovery info
    --list                  List existing backups
    --restore FILE          Restore from backup
    --dry-run               Show what would be done

${BOLD}Environment Variables:${NC}
    MYSQL_USER, MYSQL_PASSWORD, MYSQL_HOST, MYSQL_PORT
    PGUSER, PGPASSWORD, PGHOST, PGPORT
    MONGO_USER, MONGO_PASSWORD, MONGO_HOST, MONGO_PORT

${BOLD}Examples:${NC}
    ${DIM}# Backup all MySQL databases${NC}
    $0 --mysql -A

    ${DIM}# Backup specific PostgreSQL database${NC}
    $0 --postgresql -d myapp

    ${DIM}# Auto-detect and backup all${NC}
    $0 --auto -A

    ${DIM}# Backup with compression and encryption${NC}
    $0 --mysql -A --compress xz --encrypt

    ${DIM}# Upload to S3${NC}
    $0 --mysql -A --upload s3://bucket/db-backups/

    ${DIM}# List existing backups${NC}
    $0 --list

    ${DIM}# Restore MySQL backup${NC}
    $0 --restore /backups/db-20240120.sql.gz --mysql -d mydb

${BOLD}Exit Codes:${NC}
    0 - Backup completed successfully
    1 - General error
    2 - Invalid arguments
    3 - Permission denied
    4 - Database not found
    5 - Dump failed
    6 - Compression failed
    7 - Encryption failed
    8 - Upload failed
    9 - Restore failed

EOF
    exit 0
}

log_info() { echo -e "${BLUE}▸${NC} $1"; }
log_ok() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}  $1${NC}"; }

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ $1 ═══${NC}"
    echo ""
}

human_size() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024))KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help) usage ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            -i | --interactive)
                INTERACTIVE=true
                shift
                ;;
            --no-interactive)
                INTERACTIVE=false
                shift
                ;;
            -y | --yes)
                RSR_YES=1
                INTERACTIVE=false
                shift
                ;;
            --mysql)
                DB_TYPE="mysql"
                shift
                ;;
            --postgresql | --postgres)
                DB_TYPE="postgresql"
                shift
                ;;
            --mongodb | --mongo)
                DB_TYPE="mongodb"
                shift
                ;;
            --auto)
                AUTO_DETECT=true
                shift
                ;;
            -d | --database)
                DATABASE="$2"
                shift 2
                ;;
            -A | --all-databases)
                ALL_DATABASES=true
                shift
                ;;
            --schema-only)
                SCHEMA_ONLY=true
                shift
                ;;
            --data-only)
                DATA_ONLY=true
                shift
                ;;
            -o | --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --compress)
                COMPRESS="$2"
                shift 2
                ;;
            --encrypt)
                DO_ENCRYPT=true
                shift
                ;;
            --gpg-key)
                GPG_KEY="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL="$2"
                shift 2
                ;;
            --upload)
                UPLOAD_DEST="$2"
                shift 2
                ;;
            --retention)
                RETENTION="$2"
                shift 2
                ;;
            --verify)
                DO_VERIFY=true
                shift
                ;;
            --pitr)
                INCLUDE_PITR=true
                shift
                ;;
            --list)
                LIST_BACKUPS=true
                shift
                ;;
            --restore)
                RESTORE_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                exit $EXIT_INVALID_ARGS
                ;;
            *) shift ;;
        esac
    done
}

# Auto-detect installed databases
detect_databases() {
    log_info "Auto-detecting databases..."

    local found=()

    # Check MySQL/MariaDB
    if command -v mysql &> /dev/null; then
        if mysqladmin ping -h "$MYSQL_HOST" -u "$MYSQL_USER" ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} &> /dev/null; then
            found+=("mysql")
            log_ok "MySQL/MariaDB detected"
        fi
    fi

    # Check PostgreSQL
    if command -v psql &> /dev/null; then
        if PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -U "$PGUSER" -p "$PGPORT" -c '\q' &> /dev/null; then
            found+=("postgresql")
            log_ok "PostgreSQL detected"
        fi
    fi

    # Check MongoDB
    if command -v mongosh &> /dev/null || command -v mongo &> /dev/null; then
        local mongo_cmd="mongosh"
        command -v mongosh &> /dev/null || mongo_cmd="mongo"
        if $mongo_cmd --host "$MONGO_HOST" --port "$MONGO_PORT" --eval "db.version()" &> /dev/null; then
            found+=("mongodb")
            log_ok "MongoDB detected"
        fi
    fi

    if [[ ${#found[@]} -eq 0 ]]; then
        log_error "No supported databases detected"
        exit $EXIT_DB_NOT_FOUND
    fi

    echo "${found[@]}"
}

# Setup backup directory
setup_backup_dir() {
    mkdir -p "$OUTPUT_DIR"
    chmod 700 "$OUTPUT_DIR"
}

# Generate backup filename
get_backup_filename() {
    local db_type="$1"
    local db_name="${2:-all}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local hostname
    hostname=$(hostname -s 2> /dev/null || echo "server")

    echo "${db_type}-${db_name}-${hostname}-${timestamp}"
}

# Get MySQL databases
get_mysql_databases() {
    mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
        -N -e "SHOW DATABASES" 2> /dev/null | grep -vE "^(information_schema|performance_schema|mysql|sys)$"
}

# Backup MySQL database
backup_mysql() {
    print_header "MySQL/MariaDB Backup"

    if ! command -v mysqldump &> /dev/null; then
        log_error "mysqldump not found"
        exit $EXIT_ERROR
    fi

    local databases=()

    if [[ "$ALL_DATABASES" == "true" ]]; then
        log_info "Backing up all MySQL databases..."
        mapfile -t databases < <(get_mysql_databases)
    elif [[ -n "$DATABASE" ]]; then
        databases=("$DATABASE")
    else
        log_error "Specify -d DATABASE or -A for all databases"
        exit $EXIT_INVALID_ARGS
    fi

    if [[ ${#databases[@]} -eq 0 ]]; then
        log_warn "No databases found to backup"
        return 0
    fi

    log_info "Found ${#databases[@]} database(s) to backup"

    local dump_opts=""
    [[ "$SCHEMA_ONLY" == "true" ]] && dump_opts="$dump_opts --no-data"
    [[ "$DATA_ONLY" == "true" ]] && dump_opts="$dump_opts --no-create-info"

    # Add best practices options
    dump_opts="$dump_opts --single-transaction --quick --lock-tables=false"
    dump_opts="$dump_opts --routines --triggers --events"

    for db in "${databases[@]}"; do
        local filename
        filename=$(get_backup_filename "mysql" "$db")
        local output_file="$OUTPUT_DIR/${filename}.sql"

        log_info "Dumping database: $db"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would dump $db to $output_file"
            continue
        fi

        mysqldump -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" \
            ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
            $dump_opts "$db" > "$output_file" 2> /dev/null || {
            log_error "Failed to dump database: $db"
            exit $EXIT_DUMP_FAILED
        }

        # Compress and encrypt
        finalize_backup "$output_file" "$db"
    done

    # Include PITR info
    if [[ "$INCLUDE_PITR" == "true" && "$DRY_RUN" != "true" ]]; then
        log_info "Recording binary log position..."
        mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" \
            ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
            -e "SHOW MASTER STATUS\G" > "$OUTPUT_DIR/mysql-binlog-position.txt" 2> /dev/null || true
    fi
}

# Get PostgreSQL databases
get_pg_databases() {
    PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -U "$PGUSER" -p "$PGPORT" \
        -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres'" 2> /dev/null | tr -d ' '
}

# Backup PostgreSQL database
backup_postgresql() {
    print_header "PostgreSQL Backup"

    if ! command -v pg_dump &> /dev/null; then
        log_error "pg_dump not found"
        exit $EXIT_ERROR
    fi

    local databases=()

    if [[ "$ALL_DATABASES" == "true" ]]; then
        log_info "Backing up all PostgreSQL databases..."
        mapfile -t databases < <(get_pg_databases)
    elif [[ -n "$DATABASE" ]]; then
        databases=("$DATABASE")
    else
        log_error "Specify -d DATABASE or -A for all databases"
        exit $EXIT_INVALID_ARGS
    fi

    if [[ ${#databases[@]} -eq 0 ]]; then
        log_warn "No databases found to backup"
        return 0
    fi

    log_info "Found ${#databases[@]} database(s) to backup"

    local dump_opts=""
    [[ "$SCHEMA_ONLY" == "true" ]] && dump_opts="$dump_opts --schema-only"
    [[ "$DATA_ONLY" == "true" ]] && dump_opts="$dump_opts --data-only"

    # Use parallel dump if requested and available
    if [[ "$PARALLEL" -gt 1 ]] && command -v pg_dump &> /dev/null; then
        dump_opts="$dump_opts -j $PARALLEL"
    fi

    for db in "${databases[@]}"; do
        [[ -z "$db" ]] && continue

        local filename
        filename=$(get_backup_filename "postgresql" "$db")
        local output_file="$OUTPUT_DIR/${filename}.sql"

        log_info "Dumping database: $db"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would dump $db to $output_file"
            continue
        fi

        PGPASSWORD="$PGPASSWORD" pg_dump -h "$PGHOST" -U "$PGUSER" -p "$PGPORT" \
            $dump_opts "$db" > "$output_file" 2> /dev/null || {
            log_error "Failed to dump database: $db"
            exit $EXIT_DUMP_FAILED
        }

        # Compress and encrypt
        finalize_backup "$output_file" "$db"
    done

    # Backup roles and tablespaces
    if [[ "$ALL_DATABASES" == "true" && "$DRY_RUN" != "true" ]]; then
        log_info "Backing up global objects (roles, tablespaces)..."
        local globals_file="$OUTPUT_DIR/$(get_backup_filename "postgresql" "globals").sql"
        PGPASSWORD="$PGPASSWORD" pg_dumpall -h "$PGHOST" -U "$PGUSER" -p "$PGPORT" \
            --globals-only > "$globals_file" 2> /dev/null || true
        finalize_backup "$globals_file" "globals"
    fi

    # Include PITR info
    if [[ "$INCLUDE_PITR" == "true" && "$DRY_RUN" != "true" ]]; then
        log_info "Recording WAL position..."
        PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -U "$PGUSER" -p "$PGPORT" \
            -c "SELECT pg_current_wal_lsn();" > "$OUTPUT_DIR/postgresql-wal-position.txt" 2> /dev/null || true
    fi
}

# Get MongoDB databases
get_mongo_databases() {
    local mongo_cmd="mongosh"
    command -v mongosh &> /dev/null || mongo_cmd="mongo"

    local auth_opts=""
    [[ -n "$MONGO_USER" ]] && auth_opts="-u $MONGO_USER"
    [[ -n "$MONGO_PASSWORD" ]] && auth_opts="$auth_opts -p $MONGO_PASSWORD"

    $mongo_cmd --host "$MONGO_HOST" --port "$MONGO_PORT" $auth_opts \
        --quiet --eval "db.adminCommand('listDatabases').databases.map(d => d.name).join('\n')" 2> /dev/null \
        | grep -vE "^(admin|config|local)$"
}

# Backup MongoDB database
backup_mongodb() {
    print_header "MongoDB Backup"

    if ! command -v mongodump &> /dev/null; then
        log_error "mongodump not found"
        exit $EXIT_ERROR
    fi

    local auth_opts=""
    [[ -n "$MONGO_USER" ]] && auth_opts="--username=$MONGO_USER"
    [[ -n "$MONGO_PASSWORD" ]] && auth_opts="$auth_opts --password=$MONGO_PASSWORD"

    local filename
    filename=$(get_backup_filename "mongodb" "${DATABASE:-all}")
    local output_path="$OUTPUT_DIR/$filename"

    if [[ "$ALL_DATABASES" == "true" ]]; then
        log_info "Backing up all MongoDB databases..."

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would dump all databases to $output_path"
            return 0
        fi

        mongodump --host "$MONGO_HOST" --port "$MONGO_PORT" $auth_opts \
            --out "$output_path" 2> /dev/null || {
            log_error "Failed to dump MongoDB"
            exit $EXIT_DUMP_FAILED
        }
    elif [[ -n "$DATABASE" ]]; then
        log_info "Backing up MongoDB database: $DATABASE"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would dump $DATABASE to $output_path"
            return 0
        fi

        mongodump --host "$MONGO_HOST" --port "$MONGO_PORT" $auth_opts \
            --db "$DATABASE" --out "$output_path" 2> /dev/null || {
            log_error "Failed to dump database: $DATABASE"
            exit $EXIT_DUMP_FAILED
        }
    else
        log_error "Specify -d DATABASE or -A for all databases"
        exit $EXIT_INVALID_ARGS
    fi

    # Create archive
    log_info "Creating archive..."
    local archive_file="${output_path}.tar"
    tar -cf "$archive_file" -C "$OUTPUT_DIR" "$filename" 2> /dev/null
    rm -rf "$output_path"

    # Compress and encrypt
    finalize_backup "$archive_file" "${DATABASE:-all}"
}

# Finalize backup (compress, encrypt, checksum)
finalize_backup() {
    local file="$1"
    local db_name="$2"

    [[ ! -f "$file" ]] && return 0

    local final_file="$file"

    # Compress
    case "$COMPRESS" in
        gzip)
            log_debug "Compressing with gzip..."
            gzip -9 "$file" || {
                log_error "Compression failed"
                exit $EXIT_COMPRESS_FAIL
            }
            final_file="${file}.gz"
            ;;
        xz)
            log_debug "Compressing with xz..."
            xz -9 "$file" || {
                log_error "Compression failed"
                exit $EXIT_COMPRESS_FAIL
            }
            final_file="${file}.xz"
            ;;
        lz4)
            log_debug "Compressing with lz4..."
            if lz4 -9 "$file" "${file}.lz4"; then
                rm -f "$file"
            else
                log_error "Compression failed"
                exit $EXIT_COMPRESS_FAIL
            fi
            final_file="${file}.lz4"
            ;;
        none)
            log_debug "Skipping compression"
            ;;
    esac

    # Encrypt
    if [[ "$DO_ENCRYPT" == "true" ]]; then
        log_debug "Encrypting..."
        if [[ -n "$GPG_KEY" ]]; then
            gpg --encrypt --recipient "$GPG_KEY" "$final_file" || {
                log_error "Encryption failed"
                exit $EXIT_ENCRYPT_FAIL
            }
        else
            gpg --symmetric --cipher-algo AES256 "$final_file" || {
                log_error "Encryption failed"
                exit $EXIT_ENCRYPT_FAIL
            }
        fi
        rm -f "$final_file"
        final_file="${final_file}.gpg"
    fi

    # Create checksum
    sha256sum "$final_file" > "${final_file}.sha256" 2> /dev/null \
        || shasum -a 256 "$final_file" > "${final_file}.sha256" 2> /dev/null || true

    local size
    size=$(stat -f%z "$final_file" 2> /dev/null || stat -c%s "$final_file" 2> /dev/null || echo "0")

    log_ok "Backup: $(basename "$final_file") ($(human_size $size))"

    # Verify if requested
    if [[ "$DO_VERIFY" == "true" ]]; then
        verify_backup "$final_file"
    fi

    # Upload if requested
    if [[ -n "$UPLOAD_DEST" ]]; then
        upload_backup "$final_file"
    fi
}

# Verify backup
verify_backup() {
    local file="$1"

    log_debug "Verifying backup integrity..."

    # Check checksum
    local checksum_file="${file}.sha256"
    if [[ -f "$checksum_file" ]]; then
        if sha256sum -c "$checksum_file" &> /dev/null || shasum -a 256 -c "$checksum_file" &> /dev/null; then
            log_debug "Checksum verified"
        else
            log_warn "Checksum verification failed"
        fi
    fi

    # Try to read the file
    if [[ "$file" =~ \.gpg$ ]]; then
        log_debug "Encrypted backup - skipping content verification"
    elif [[ "$file" =~ \.gz$ ]]; then
        if gzip -t "$file" &> /dev/null; then
            log_debug "Gzip archive valid"
        else
            log_warn "Gzip archive may be corrupt"
        fi
    elif [[ "$file" =~ \.xz$ ]]; then
        if xz -t "$file" &> /dev/null; then
            log_debug "XZ archive valid"
        else
            log_warn "XZ archive may be corrupt"
        fi
    fi
}

# Upload backup
upload_backup() {
    local file="$1"

    log_info "Uploading $(basename "$file")..."

    if [[ "$UPLOAD_DEST" =~ ^s3:// ]]; then
        if command -v aws &> /dev/null; then
            aws s3 cp "$file" "$UPLOAD_DEST" || {
                log_error "S3 upload failed"
                exit $EXIT_UPLOAD_FAIL
            }
            log_ok "Uploaded to S3"
        else
            log_error "AWS CLI not installed"
            exit $EXIT_UPLOAD_FAIL
        fi
    elif [[ "$UPLOAD_DEST" =~ ^gs:// ]]; then
        if command -v gsutil &> /dev/null; then
            gsutil cp "$file" "$UPLOAD_DEST" || {
                log_error "GCS upload failed"
                exit $EXIT_UPLOAD_FAIL
            }
            log_ok "Uploaded to GCS"
        else
            log_error "gsutil not installed"
            exit $EXIT_UPLOAD_FAIL
        fi
    elif [[ "$UPLOAD_DEST" =~ ^rsync:// ]]; then
        local dest="${UPLOAD_DEST#rsync://}"
        rsync -avz "$file" "$dest" || {
            log_error "Rsync upload failed"
            exit $EXIT_UPLOAD_FAIL
        }
        log_ok "Uploaded via rsync"
    else
        log_error "Unknown upload destination: $UPLOAD_DEST"
        exit $EXIT_UPLOAD_FAIL
    fi
}

# Apply retention policy
apply_retention() {
    log_info "Applying retention policy (keeping $RETENTION backups per database)..."

    for pattern in mysql postgresql mongodb; do
        local backups
        backups=$(ls -t "$OUTPUT_DIR"/${pattern}-*.sql* "$OUTPUT_DIR"/${pattern}-*.tar* 2> /dev/null | tail -n +$((RETENTION + 1)) || true)

        if [[ -n "$backups" ]]; then
            echo "$backups" | while read -r file; do
                rm -f "$file" "${file}.sha256" 2> /dev/null || true
                log_debug "Removed: $file"
            done
        fi
    done
}

# List existing backups
list_backups() {
    print_header "Existing Database Backups"

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_info "No backups found in $OUTPUT_DIR"
        return 0
    fi

    printf "${BOLD}%-50s %10s %s${NC}\n" "FILENAME" "SIZE" "DATE"
    echo "─────────────────────────────────────────────────────────────────────────"

    local count=0
    for file in "$OUTPUT_DIR"/*.sql* "$OUTPUT_DIR"/*.tar* "$OUTPUT_DIR"/*.bson*; do
        [[ -f "$file" ]] || continue
        [[ "$file" =~ \.sha256$ ]] && continue

        local size date
        size=$(stat -f%z "$file" 2> /dev/null || stat -c%s "$file" 2> /dev/null || echo "?")
        date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" 2> /dev/null || stat -c "%y" "$file" 2> /dev/null | cut -d. -f1 || echo "?")

        printf "%-50s %10s %s\n" "$(basename "$file")" "$(human_size $size)" "$date"
        ((count++)) || true
    done

    echo ""
    log_info "Total: $count backup(s)"
}

# Restore from backup
restore_backup() {
    local file="$1"

    print_header "Restore Database"

    if [[ ! -f "$file" ]]; then
        log_error "Backup file not found: $file"
        exit $EXIT_RESTORE_FAIL
    fi

    if [[ -z "$DB_TYPE" ]]; then
        # Try to detect from filename
        if [[ "$file" =~ mysql ]]; then
            DB_TYPE="mysql"
        elif [[ "$file" =~ postgresql|postgres ]]; then
            DB_TYPE="postgresql"
        elif [[ "$file" =~ mongo ]]; then
            DB_TYPE="mongodb"
        else
            log_error "Cannot detect database type. Specify --mysql, --postgresql, or --mongodb"
            exit $EXIT_INVALID_ARGS
        fi
    fi

    log_warn "This will restore data from backup!"
    log_warn "Target database: ${DATABASE:-'(not specified - will use backup default)'}"

    if [[ "$DRY_RUN" != "true" ]]; then
        read -p "Continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Restore cancelled"
            exit 0
        fi
    fi

    local restore_file="$file"

    # Handle encrypted backups
    if [[ "$file" =~ \.gpg$ ]]; then
        log_info "Decrypting backup..."
        local decrypted="${file%.gpg}"
        gpg --decrypt "$file" > "$decrypted" || {
            log_error "Decryption failed"
            exit $EXIT_RESTORE_FAIL
        }
        restore_file="$decrypted"
    fi

    # Handle compressed backups
    if [[ "$restore_file" =~ \.gz$ ]]; then
        log_info "Decompressing..."
        gunzip -k "$restore_file" || {
            log_error "Decompression failed"
            exit $EXIT_RESTORE_FAIL
        }
        restore_file="${restore_file%.gz}"
    elif [[ "$restore_file" =~ \.xz$ ]]; then
        log_info "Decompressing..."
        xz -dk "$restore_file" || {
            log_error "Decompression failed"
            exit $EXIT_RESTORE_FAIL
        }
        restore_file="${restore_file%.xz}"
    elif [[ "$restore_file" =~ \.lz4$ ]]; then
        log_info "Decompressing..."
        lz4 -d "$restore_file" "${restore_file%.lz4}" || {
            log_error "Decompression failed"
            exit $EXIT_RESTORE_FAIL
        }
        restore_file="${restore_file%.lz4}"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore from $restore_file to $DB_TYPE"
        return 0
    fi

    case "$DB_TYPE" in
        mysql)
            log_info "Restoring MySQL database..."
            if [[ -n "$DATABASE" ]]; then
                mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" \
                    ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} "$DATABASE" < "$restore_file" || {
                    log_error "Restore failed"
                    exit $EXIT_RESTORE_FAIL
                }
            else
                mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" \
                    ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} < "$restore_file" || {
                    log_error "Restore failed"
                    exit $EXIT_RESTORE_FAIL
                }
            fi
            ;;
        postgresql)
            log_info "Restoring PostgreSQL database..."
            if [[ -n "$DATABASE" ]]; then
                PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -U "$PGUSER" -p "$PGPORT" \
                    -d "$DATABASE" -f "$restore_file" || {
                    log_error "Restore failed"
                    exit $EXIT_RESTORE_FAIL
                }
            else
                PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -U "$PGUSER" -p "$PGPORT" \
                    -f "$restore_file" || {
                    log_error "Restore failed"
                    exit $EXIT_RESTORE_FAIL
                }
            fi
            ;;
        mongodb)
            log_info "Restoring MongoDB database..."
            local auth_opts=""
            [[ -n "$MONGO_USER" ]] && auth_opts="--username=$MONGO_USER"
            [[ -n "$MONGO_PASSWORD" ]] && auth_opts="$auth_opts --password=$MONGO_PASSWORD"

            # Handle tar archives
            if [[ "$restore_file" =~ \.tar$ ]]; then
                local tmp_dir="/tmp/mongorestore-$$"
                mkdir -p "$tmp_dir"
                tar -xf "$restore_file" -C "$tmp_dir"
                restore_file="$tmp_dir"
            fi

            mongorestore --host "$MONGO_HOST" --port "$MONGO_PORT" $auth_opts \
                ${DATABASE:+--db "$DATABASE"} "$restore_file" || {
                log_error "Restore failed"
                exit $EXIT_RESTORE_FAIL
            }
            ;;
    esac

    log_ok "Database restored successfully"
}

# =============================================================================
# Interactive Mode
# =============================================================================

run_interactive() {
    print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"
    
    # Main action selection
    local action
    action=$(prompt_select "What would you like to do?" \
        "Backup database(s)" \
        "Restore from backup" \
        "List existing backups" \
        "Auto-detect and backup all databases")
    
    case "$action" in
        "Backup database(s)")
            interactive_backup
            ;;
        "Restore from backup")
            interactive_restore
            ;;
        "List existing backups")
            list_backups
            ;;
        "Auto-detect and backup all databases")
            interactive_auto_backup
            ;;
    esac
}

interactive_backup() {
    echo ""
    
    # Select database type
    local db_type
    db_type=$(prompt_select "Select database type:" \
        "MySQL / MariaDB" \
        "PostgreSQL" \
        "MongoDB")
    
    case "$db_type" in
        "MySQL / MariaDB") DB_TYPE="mysql" ;;
        "PostgreSQL") DB_TYPE="postgresql" ;;
        "MongoDB") DB_TYPE="mongodb" ;;
    esac
    
    echo ""
    
    # Backup scope
    local scope
    scope=$(prompt_select "What would you like to backup?" \
        "All databases" \
        "Specific database")
    
    if [[ "$scope" == "All databases" ]]; then
        ALL_DATABASES=true
    else
        echo ""
        local db_name
        db_name=$(prompt_input "Enter database name" "")
        if [[ -z "$db_name" ]]; then
            log_error "No database name provided"
            return 1
        fi
        DATABASE="$db_name"
    fi
    
    echo ""
    
    # Compression
    local compress_choice
    compress_choice=$(prompt_select "Compression method:" \
        "gzip (fast, good compression)" \
        "xz (slower, best compression)" \
        "lz4 (fastest, moderate compression)" \
        "none (no compression)")
    
    COMPRESS=$(echo "$compress_choice" | cut -d' ' -f1)
    
    echo ""
    
    # Encryption
    if prompt_yes_no "Encrypt backup with GPG?" "n"; then
        DO_ENCRYPT=true
        local key
        key=$(prompt_input "GPG key ID (email or key ID)" "")
        [[ -n "$key" ]] && GPG_KEY="$key"
    fi
    
    echo ""
    
    # Output directory
    local output
    output=$(prompt_input "Output directory" "$OUTPUT_DIR")
    OUTPUT_DIR="$output"
    
    echo ""
    
    # Summary
    log_info "Backup configuration:"
    echo -e "  ${CYAN}•${NC} Database type: $DB_TYPE"
    if [[ "$ALL_DATABASES" == "true" ]]; then
        echo -e "  ${CYAN}•${NC} Scope: All databases"
    else
        echo -e "  ${CYAN}•${NC} Database: $DATABASE"
    fi
    echo -e "  ${CYAN}•${NC} Compression: $COMPRESS"
    [[ "$DO_ENCRYPT" == "true" ]] && echo -e "  ${CYAN}•${NC} Encryption: Yes (GPG key: $GPG_KEY)"
    echo -e "  ${CYAN}•${NC} Output: $OUTPUT_DIR"
    echo ""
    
    if prompt_yes_no "Start backup?" "y"; then
        setup_backup_dir
        
        case "$DB_TYPE" in
            mysql) backup_mysql ;;
            postgresql) backup_postgresql ;;
            mongodb) backup_mongodb ;;
        esac
        
        apply_retention
        
        echo ""
        log_ok "Backup completed successfully!"
    fi
}

interactive_restore() {
    echo ""
    
    # List available backups
    log_info "Available backups in $OUTPUT_DIR:"
    echo ""
    
    local backups
    backups=$(find "$OUTPUT_DIR" -maxdepth 1 -type f \( -name "*.sql*" -o -name "*.dump*" -o -name "*.tar*" -o -name "*.archive*" \) 2>/dev/null | sort -r | head -10)
    
    if [[ -z "$backups" ]]; then
        log_warn "No backups found in $OUTPUT_DIR"
        return 0
    fi
    
    echo "$backups" | while read -r backup; do
        local size
        size=$(ls -lh "$backup" 2>/dev/null | awk '{print $5}')
        echo -e "  ${CYAN}•${NC} $(basename "$backup") ($size)"
    done
    
    echo ""
    local restore_path
    restore_path=$(prompt_input "Enter backup file path to restore" "")
    
    if [[ -z "$restore_path" || ! -f "$restore_path" ]]; then
        log_error "Invalid file path"
        return 1
    fi
    
    # Detect database type from filename
    if [[ "$restore_path" =~ mysql ]]; then
        DB_TYPE="mysql"
    elif [[ "$restore_path" =~ postgres|pg ]]; then
        DB_TYPE="postgresql"
    elif [[ "$restore_path" =~ mongo ]]; then
        DB_TYPE="mongodb"
    else
        local db_type
        db_type=$(prompt_select "Select database type:" "MySQL" "PostgreSQL" "MongoDB")
        case "$db_type" in
            "MySQL") DB_TYPE="mysql" ;;
            "PostgreSQL") DB_TYPE="postgresql" ;;
            "MongoDB") DB_TYPE="mongodb" ;;
        esac
    fi
    
    echo ""
    local target_db
    target_db=$(prompt_input "Target database name (leave empty to use dump's database)" "")
    [[ -n "$target_db" ]] && DATABASE="$target_db"
    
    echo ""
    
    if confirm_destructive "This will restore the backup and may overwrite existing data in the database"; then
        restore_backup "$restore_path"
    fi
}

interactive_auto_backup() {
    echo ""
    log_info "Detecting installed databases..."
    echo ""
    
    local detected
    detected=$(detect_databases 2>/dev/null || echo "")
    
    if [[ -z "$detected" ]]; then
        log_error "No databases detected"
        return 1
    fi
    
    echo ""
    if prompt_yes_no "Backup all detected databases?" "y"; then
        ALL_DATABASES=true
        AUTO_DETECT=true
        setup_backup_dir
        
        for db_type in $detected; do
            DB_TYPE="$db_type"
            case "$db_type" in
                mysql) backup_mysql ;;
                postgresql) backup_postgresql ;;
                mongodb) backup_mongodb ;;
            esac
        done
        
        apply_retention
        
        echo ""
        log_ok "All backups completed!"
    fi
}

# Main function
main() {
    local original_args=("$@")
    parse_args "$@"

    # Determine if interactive mode should be enabled
    if [[ "$INTERACTIVE" == "auto" ]]; then
        if [[ ${#original_args[@]} -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
            INTERACTIVE=true
        else
            INTERACTIVE=false
        fi
    fi

    # Run interactive mode if enabled
    if [[ "$INTERACTIVE" == "true" ]] && type -t rsr_is_interactive &>/dev/null && rsr_is_interactive; then
        run_interactive
        exit $EXIT_OK
    fi

    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo ""

    # Handle list
    if [[ "$LIST_BACKUPS" == "true" ]]; then
        list_backups
        exit $EXIT_OK
    fi

    # Handle restore
    if [[ -n "$RESTORE_FILE" ]]; then
        restore_backup "$RESTORE_FILE"
        exit $EXIT_OK
    fi

    setup_backup_dir

    # Auto-detect if requested
    if [[ "$AUTO_DETECT" == "true" ]]; then
        local detected
        detected=$(detect_databases)

        for db_type in $detected; do
            DB_TYPE="$db_type"
            case "$db_type" in
                mysql) backup_mysql ;;
                postgresql) backup_postgresql ;;
                mongodb) backup_mongodb ;;
            esac
        done
    elif [[ -n "$DB_TYPE" ]]; then
        case "$DB_TYPE" in
            mysql) backup_mysql ;;
            postgresql) backup_postgresql ;;
            mongodb) backup_mongodb ;;
            *)
                log_error "Unknown database type: $DB_TYPE"
                exit $EXIT_INVALID_ARGS
                ;;
        esac
    else
        log_error "Specify --mysql, --postgresql, --mongodb, or --auto"
        exit $EXIT_INVALID_ARGS
    fi

    # Apply retention
    apply_retention

    echo ""
    log_ok "Backup completed successfully"

    exit $EXIT_OK
}

main "$@"
