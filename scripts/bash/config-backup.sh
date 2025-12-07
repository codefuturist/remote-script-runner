#!/bin/bash
# =============================================================================
# @id           backup
# @name         config-backup
# @displayName  Configuration Backup
# @description  Backup system configs: /etc, crontabs, packages, databases
# @category     maintenance
# @version      1.0.0
# @author       codefuturist
# @tags         backup,config,etc,crontab,packages,restore,maintenance
# @shells       bash
# =============================================================================

set -euo pipefail

# Script metadata
SCRIPT_NAME="Configuration Backup"
SCRIPT_VERSION="1.0.0"

# Default values
VERBOSE=false
DRY_RUN=false
SECTIONS=()
OUTPUT_DIR="/var/backups/rsr"
COMPRESS="gzip"
DO_ENCRYPT=false
GPG_KEY=""
UPLOAD_DEST=""
RETENTION=7
EXCLUDE_PATTERNS=()
DO_VERIFY=false
LIST_BACKUPS=false
RESTORE_FILE=""

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
EXIT_DISK_SPACE=4
EXIT_COMPRESS_FAIL=5
EXIT_ENCRYPT_FAIL=6
EXIT_UPLOAD_FAIL=7
EXIT_RESTORE_FAIL=8

# Tracking
BACKUP_FILES=()
TOTAL_SIZE=0

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Backup system configurations: /etc, crontabs, packages, and more.

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${BOLD}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -a, --all               Backup everything
    -s, --section SECTION   Backup specific section (can repeat)
    -o, --output DIR        Output directory (default: /var/backups/rsr)
    --compress METHOD       Compression: gzip, xz, none (default: gzip)
    --encrypt               Encrypt with GPG
    --gpg-key KEY           GPG key ID for encryption
    --upload DEST           Upload to remote (s3://, rsync://, scp://)
    --retention N           Keep N most recent backups (default: 7)
    --exclude PATTERN       Exclude files matching pattern
    --verify                Verify backup after creation
    --list                  List existing backups
    --restore FILE          Restore from backup file
    -d, --dry-run           Show what would be backed up

${BOLD}Sections:${NC}
    etc         /etc directory (system configuration)
    packages    Installed package list with versions
    crontabs    All user and system crontabs
    systemd     Custom systemd units
    ssh         SSH keys and authorized_keys
    nginx       Nginx configuration
    apache      Apache configuration
    database    Database configs (not data)

${BOLD}Examples:${NC}
    ${DIM}# Dry run full backup${NC}
    $0 -a -d

    ${DIM}# Full backup${NC}
    sudo $0 -a

    ${DIM}# Backup etc and packages${NC}
    sudo $0 -s etc -s packages

    ${DIM}# Backup with encryption${NC}
    sudo $0 -a --encrypt --gpg-key admin@example.com

    ${DIM}# Upload to S3${NC}
    sudo $0 -a --upload s3://mybucket/backups/

    ${DIM}# List existing backups${NC}
    $0 --list

    ${DIM}# Restore from backup${NC}
    sudo $0 --restore /var/backups/rsr/backup-20240120.tar.gz

${BOLD}Exit Codes:${NC}
    0 - Backup completed successfully
    1 - General error
    2 - Invalid arguments
    3 - Permission denied (need root)
    4 - Insufficient disk space
    5 - Compression failed
    6 - Encryption failed
    7 - Upload failed
    8 - Restore failed

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
            -a | --all)
                SECTIONS=("etc" "packages" "crontabs" "systemd" "ssh" "nginx" "apache" "database")
                shift
                ;;
            -s | --section)
                SECTIONS+=("$2")
                shift 2
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
            --upload)
                UPLOAD_DEST="$2"
                shift 2
                ;;
            --retention)
                RETENTION="$2"
                shift 2
                ;;
            --exclude)
                EXCLUDE_PATTERNS+=("$2")
                shift 2
                ;;
            --verify)
                DO_VERIFY=true
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
            -d | --dry-run)
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

    # Default to etc if no sections specified
    if [[ ${#SECTIONS[@]} -eq 0 && "$LIST_BACKUPS" != "true" && -z "$RESTORE_FILE" ]]; then
        SECTIONS=("etc")
    fi
}

# Check disk space
check_disk_space() {
    local available
    available=$(df -P "$OUTPUT_DIR" 2> /dev/null | tail -1 | awk '{print $4}')

    # Require at least 100MB
    if [[ -n "$available" && "$available" -lt 102400 ]]; then
        log_error "Insufficient disk space. Only $((available / 1024))MB available"
        exit $EXIT_DISK_SPACE
    fi
}

# Create backup directory
setup_backup_dir() {
    mkdir -p "$OUTPUT_DIR"
    chmod 700 "$OUTPUT_DIR"
}

# Generate backup filename
get_backup_filename() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local hostname
    hostname=$(hostname -s 2> /dev/null || echo "server")

    echo "backup-${hostname}-${timestamp}"
}

# Backup /etc directory
backup_etc() {
    print_header "Backing up /etc"

    local tmp_file="/tmp/etc-backup-$$.tar"

    log_info "Creating /etc archive..."

    local exclude_args=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_args="$exclude_args --exclude=$pattern"
    done

    # Exclude large/unnecessary files
    exclude_args="$exclude_args --exclude=*.cache --exclude=*.tmp --exclude=ssl/private"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup /etc"
        tar -cvf /dev/null /etc $exclude_args 2>&1 | head -20
        return 0
    fi

    tar -cf "$tmp_file" /etc $exclude_args 2> /dev/null || {
        log_warn "Some files could not be read (permission denied)"
    }

    local size
    size=$(stat -f%z "$tmp_file" 2> /dev/null || stat -c%s "$tmp_file" 2> /dev/null || echo "0")
    TOTAL_SIZE=$((TOTAL_SIZE + size))

    BACKUP_FILES+=("$tmp_file")
    log_ok "/etc backed up ($(human_size $size))"
}

# Backup package list
backup_packages() {
    print_header "Backing up Package List"

    local tmp_file="/tmp/packages-$$.txt"

    log_info "Exporting installed packages..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would export package list"
        return 0
    fi

    {
        echo "# Package list generated on $(date)"
        echo "# Hostname: $(hostname)"
        echo ""

        if command -v dpkg &> /dev/null; then
            echo "# Debian/Ubuntu packages (dpkg)"
            dpkg-query -W -f='${Package}\t${Version}\n' 2> /dev/null
        fi

        if command -v rpm &> /dev/null; then
            echo ""
            echo "# RPM packages"
            rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\n' 2> /dev/null
        fi

        if command -v pacman &> /dev/null; then
            echo ""
            echo "# Arch packages (pacman)"
            pacman -Q 2> /dev/null
        fi

        if command -v brew &> /dev/null; then
            echo ""
            echo "# Homebrew packages"
            brew list --versions 2> /dev/null
        fi

        # Also save pip packages if available
        if command -v pip3 &> /dev/null; then
            echo ""
            echo "# Python packages (pip3)"
            pip3 list --format=freeze 2> /dev/null || true
        fi

        # npm global packages
        if command -v npm &> /dev/null; then
            echo ""
            echo "# NPM global packages"
            npm list -g --depth=0 2> /dev/null || true
        fi
    } > "$tmp_file"

    local size
    size=$(stat -f%z "$tmp_file" 2> /dev/null || stat -c%s "$tmp_file" 2> /dev/null || echo "0")
    TOTAL_SIZE=$((TOTAL_SIZE + size))

    BACKUP_FILES+=("$tmp_file")
    log_ok "Package list exported ($(human_size $size))"
}

# Backup crontabs
backup_crontabs() {
    print_header "Backing up Crontabs"

    local tmp_dir="/tmp/crontabs-$$"
    mkdir -p "$tmp_dir"

    log_info "Exporting crontabs..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup crontabs"
        return 0
    fi

    local count=0

    # System crontabs
    for file in /etc/crontab /etc/cron.d/*; do
        if [[ -f "$file" ]]; then
            cp "$file" "$tmp_dir/" 2> /dev/null || true
            ((count++)) || true
        fi
    done

    # User crontabs
    if [[ -d /var/spool/cron/crontabs ]]; then
        cp -r /var/spool/cron/crontabs "$tmp_dir/user-crontabs" 2> /dev/null || true
    elif [[ -d /var/spool/cron ]]; then
        cp -r /var/spool/cron "$tmp_dir/user-crontabs" 2> /dev/null || true
    fi

    # Export current user's crontab
    crontab -l > "$tmp_dir/current-user-crontab" 2> /dev/null || true

    # Create archive
    local tmp_file="/tmp/crontabs-$$.tar"
    tar -cf "$tmp_file" -C /tmp "crontabs-$$" 2> /dev/null
    rm -rf "$tmp_dir"

    local size
    size=$(stat -f%z "$tmp_file" 2> /dev/null || stat -c%s "$tmp_file" 2> /dev/null || echo "0")
    TOTAL_SIZE=$((TOTAL_SIZE + size))

    BACKUP_FILES+=("$tmp_file")
    log_ok "Crontabs backed up ($count files)"
}

# Backup systemd units
backup_systemd() {
    print_header "Backing up Systemd Units"

    local tmp_file="/tmp/systemd-$$.tar"

    if [[ ! -d /etc/systemd ]]; then
        log_info "Systemd not found, skipping"
        return 0
    fi

    log_info "Backing up custom systemd units..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup systemd units"
        return 0
    fi

    # Backup custom units from /etc/systemd
    tar -cf "$tmp_file" /etc/systemd/system/*.service /etc/systemd/system/*.timer \
        /etc/systemd/system/*.mount 2> /dev/null || true

    local size
    size=$(stat -f%z "$tmp_file" 2> /dev/null || stat -c%s "$tmp_file" 2> /dev/null || echo "0")

    if [[ $size -gt 0 ]]; then
        TOTAL_SIZE=$((TOTAL_SIZE + size))
        BACKUP_FILES+=("$tmp_file")
        log_ok "Systemd units backed up ($(human_size $size))"
    else
        log_info "No custom systemd units found"
        rm -f "$tmp_file"
    fi
}

# Backup SSH configuration
backup_ssh() {
    print_header "Backing up SSH Configuration"

    local tmp_file="/tmp/ssh-config-$$.tar"

    log_info "Backing up SSH configs and keys..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup SSH configuration"
        return 0
    fi

    # Backup SSH config (not private keys by default)
    tar -cf "$tmp_file" \
        /etc/ssh/sshd_config \
        /etc/ssh/ssh_config \
        /etc/ssh/*.pub \
        2> /dev/null || true

    # Backup user authorized_keys
    for home in /home/* /root; do
        if [[ -f "$home/.ssh/authorized_keys" ]]; then
            tar -rf "$tmp_file" "$home/.ssh/authorized_keys" 2> /dev/null || true
        fi
    done

    local size
    size=$(stat -f%z "$tmp_file" 2> /dev/null || stat -c%s "$tmp_file" 2> /dev/null || echo "0")
    TOTAL_SIZE=$((TOTAL_SIZE + size))

    BACKUP_FILES+=("$tmp_file")
    log_ok "SSH configuration backed up ($(human_size $size))"
}

# Backup Nginx configuration
backup_nginx() {
    print_header "Backing up Nginx"

    if [[ ! -d /etc/nginx ]]; then
        log_info "Nginx not found, skipping"
        return 0
    fi

    local tmp_file="/tmp/nginx-$$.tar"

    log_info "Backing up Nginx configuration..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup Nginx"
        return 0
    fi

    tar -cf "$tmp_file" /etc/nginx 2> /dev/null || {
        log_warn "Some Nginx files could not be read"
    }

    local size
    size=$(stat -f%z "$tmp_file" 2> /dev/null || stat -c%s "$tmp_file" 2> /dev/null || echo "0")
    TOTAL_SIZE=$((TOTAL_SIZE + size))

    BACKUP_FILES+=("$tmp_file")
    log_ok "Nginx backed up ($(human_size $size))"
}

# Backup Apache configuration
backup_apache() {
    print_header "Backing up Apache"

    local apache_dir=""
    if [[ -d /etc/apache2 ]]; then
        apache_dir="/etc/apache2"
    elif [[ -d /etc/httpd ]]; then
        apache_dir="/etc/httpd"
    else
        log_info "Apache not found, skipping"
        return 0
    fi

    local tmp_file="/tmp/apache-$$.tar"

    log_info "Backing up Apache configuration..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup Apache"
        return 0
    fi

    tar -cf "$tmp_file" "$apache_dir" 2> /dev/null || {
        log_warn "Some Apache files could not be read"
    }

    local size
    size=$(stat -f%z "$tmp_file" 2> /dev/null || stat -c%s "$tmp_file" 2> /dev/null || echo "0")
    TOTAL_SIZE=$((TOTAL_SIZE + size))

    BACKUP_FILES+=("$tmp_file")
    log_ok "Apache backed up ($(human_size $size))"
}

# Backup database configurations
backup_database() {
    print_header "Backing up Database Configs"

    local tmp_dir="/tmp/db-config-$$"
    mkdir -p "$tmp_dir"
    local found=false

    log_info "Backing up database configurations..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup database configs"
        return 0
    fi

    # MySQL/MariaDB
    for conf in /etc/mysql/my.cnf /etc/my.cnf /etc/mysql/mysql.conf.d/*.cnf; do
        if [[ -f "$conf" ]]; then
            cp "$conf" "$tmp_dir/" 2> /dev/null || true
            found=true
        fi
    done

    # PostgreSQL
    for conf in /etc/postgresql/*/main/*.conf; do
        if [[ -f "$conf" ]]; then
            mkdir -p "$tmp_dir/postgresql"
            cp "$conf" "$tmp_dir/postgresql/" 2> /dev/null || true
            found=true
        fi
    done

    # MongoDB
    if [[ -f /etc/mongod.conf ]]; then
        cp /etc/mongod.conf "$tmp_dir/" 2> /dev/null || true
        found=true
    fi

    # Redis
    if [[ -f /etc/redis/redis.conf ]]; then
        cp /etc/redis/redis.conf "$tmp_dir/" 2> /dev/null || true
        found=true
    fi

    if [[ "$found" == "true" ]]; then
        local tmp_file="/tmp/db-config-$$.tar"
        tar -cf "$tmp_file" -C /tmp "db-config-$$" 2> /dev/null
        rm -rf "$tmp_dir"

        local size
        size=$(stat -f%z "$tmp_file" 2> /dev/null || stat -c%s "$tmp_file" 2> /dev/null || echo "0")
        TOTAL_SIZE=$((TOTAL_SIZE + size))

        BACKUP_FILES+=("$tmp_file")
        log_ok "Database configs backed up ($(human_size $size))"
    else
        log_info "No database configurations found"
        rm -rf "$tmp_dir"
    fi
}

# Create final backup archive
create_final_backup() {
    print_header "Creating Final Backup"

    if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
        log_warn "No files to backup"
        return 1
    fi

    local filename
    filename=$(get_backup_filename)
    local final_file="$OUTPUT_DIR/$filename.tar"

    log_info "Combining backup files..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create $final_file"
        return 0
    fi

    # Create manifest
    local manifest="/tmp/manifest-$$.txt"
    {
        echo "Backup Manifest"
        echo "==============="
        echo "Date: $(date)"
        echo "Hostname: $(hostname)"
        echo "Sections: ${SECTIONS[*]}"
        echo ""
        echo "Contents:"
        for file in "${BACKUP_FILES[@]}"; do
            echo "  - $(basename "$file")"
        done
    } > "$manifest"

    # Combine all files
    tar -cf "$final_file" -C /tmp "manifest-$$.txt" 2> /dev/null || true
    for file in "${BACKUP_FILES[@]}"; do
        tar -rf "$final_file" "$file" 2> /dev/null || true
    done

    rm -f "$manifest"

    # Compress
    case "$COMPRESS" in
        gzip)
            log_info "Compressing with gzip..."
            gzip -9 "$final_file"
            final_file="${final_file}.gz"
            ;;
        xz)
            log_info "Compressing with xz..."
            xz -9 "$final_file"
            final_file="${final_file}.xz"
            ;;
        none)
            log_debug "Skipping compression"
            ;;
    esac

    # Encrypt
    if [[ "$DO_ENCRYPT" == "true" ]]; then
        log_info "Encrypting backup..."
        if [[ -n "$GPG_KEY" ]]; then
            gpg --encrypt --recipient "$GPG_KEY" "$final_file" || {
                log_error "Encryption failed"
                exit $EXIT_ENCRYPT_FAIL
            }
            rm -f "$final_file"
            final_file="${final_file}.gpg"
        else
            gpg --symmetric --cipher-algo AES256 "$final_file" || {
                log_error "Encryption failed"
                exit $EXIT_ENCRYPT_FAIL
            }
            rm -f "$final_file"
            final_file="${final_file}.gpg"
        fi
    fi

    # Create checksum
    local checksum_file="${final_file}.sha256"
    sha256sum "$final_file" > "$checksum_file" 2> /dev/null \
        || shasum -a 256 "$final_file" > "$checksum_file" 2> /dev/null || true

    local final_size
    final_size=$(stat -f%z "$final_file" 2> /dev/null || stat -c%s "$final_file" 2> /dev/null || echo "0")

    log_ok "Backup created: $final_file ($(human_size $final_size))"

    # Cleanup temp files
    for file in "${BACKUP_FILES[@]}"; do
        rm -f "$file"
    done

    # Verify if requested
    if [[ "$DO_VERIFY" == "true" ]]; then
        verify_backup "$final_file"
    fi

    # Upload if requested
    if [[ -n "$UPLOAD_DEST" ]]; then
        upload_backup "$final_file"
    fi

    # Apply retention
    apply_retention

    echo ""
    log_ok "Backup completed successfully"
    echo "    File: $final_file"
    echo "    Size: $(human_size $final_size)"
}

# Verify backup
verify_backup() {
    local file="$1"

    log_info "Verifying backup integrity..."

    # Check if file exists and is readable
    if [[ ! -r "$file" ]]; then
        log_error "Cannot read backup file"
        return 1
    fi

    # Try to list contents
    if [[ "$file" =~ \.gpg$ ]]; then
        log_info "Encrypted backup - skipping content verification"
    elif [[ "$file" =~ \.gz$ ]]; then
        if tar -tzf "$file" &> /dev/null; then
            log_ok "Backup verified (gzip archive valid)"
        else
            log_error "Backup verification failed"
            return 1
        fi
    elif [[ "$file" =~ \.xz$ ]]; then
        if tar -tJf "$file" &> /dev/null; then
            log_ok "Backup verified (xz archive valid)"
        else
            log_error "Backup verification failed"
            return 1
        fi
    else
        if tar -tf "$file" &> /dev/null; then
            log_ok "Backup verified (tar archive valid)"
        else
            log_error "Backup verification failed"
            return 1
        fi
    fi

    return 0
}

# Upload backup
upload_backup() {
    local file="$1"

    log_info "Uploading backup to $UPLOAD_DEST..."

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
    elif [[ "$UPLOAD_DEST" =~ ^rsync:// ]]; then
        local dest
        dest="${UPLOAD_DEST#rsync://}"
        rsync -avz "$file" "$dest" || {
            log_error "Rsync upload failed"
            exit $EXIT_UPLOAD_FAIL
        }
        log_ok "Uploaded via rsync"
    elif [[ "$UPLOAD_DEST" =~ ^scp:// ]]; then
        local dest
        dest="${UPLOAD_DEST#scp://}"
        scp "$file" "$dest" || {
            log_error "SCP upload failed"
            exit $EXIT_UPLOAD_FAIL
        }
        log_ok "Uploaded via SCP"
    else
        log_error "Unknown upload destination: $UPLOAD_DEST"
        exit $EXIT_UPLOAD_FAIL
    fi
}

# Apply retention policy
apply_retention() {
    log_info "Applying retention policy (keeping $RETENTION backups)..."

    local backups
    backups=$(ls -t "$OUTPUT_DIR"/backup-*.tar* 2> /dev/null | tail -n +$((RETENTION + 1)) || true)

    if [[ -n "$backups" ]]; then
        local count
        count=$(echo "$backups" | wc -l)
        log_info "Removing $count old backup(s)..."
        echo "$backups" | while read -r file; do
            rm -f "$file" "${file}.sha256" 2> /dev/null || true
            log_debug "Removed: $file"
        done
    fi
}

# List existing backups
list_backups() {
    print_header "Existing Backups"

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_info "No backups found in $OUTPUT_DIR"
        return 0
    fi

    printf "${BOLD}%-45s %10s %s${NC}\n" "FILENAME" "SIZE" "DATE"
    echo "─────────────────────────────────────────────────────────────────────"

    local count=0
    for file in "$OUTPUT_DIR"/backup-*.tar*; do
        [[ -f "$file" ]] || continue
        [[ "$file" =~ \.sha256$ ]] && continue

        local size date
        size=$(stat -f%z "$file" 2> /dev/null || stat -c%s "$file" 2> /dev/null || echo "?")
        date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" 2> /dev/null || stat -c "%y" "$file" 2> /dev/null | cut -d. -f1 || echo "?")

        printf "%-45s %10s %s\n" "$(basename "$file")" "$(human_size $size)" "$date"
        ((count++)) || true
    done

    echo ""
    log_info "Total: $count backup(s)"
}

# Restore from backup
restore_backup() {
    local file="$1"

    print_header "Restore from Backup"

    if [[ ! -f "$file" ]]; then
        log_error "Backup file not found: $file"
        exit $EXIT_RESTORE_FAIL
    fi

    log_warn "This will restore configuration files from backup!"
    log_warn "Existing files may be overwritten."

    if [[ "$DRY_RUN" != "true" ]]; then
        read -p "Continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Restore cancelled"
            exit 0
        fi
    fi

    log_info "Restoring from $file..."

    # Handle encrypted backups
    if [[ "$file" =~ \.gpg$ ]]; then
        log_info "Decrypting backup..."
        local decrypted="${file%.gpg}"
        gpg --decrypt "$file" > "$decrypted" || {
            log_error "Decryption failed"
            exit $EXIT_RESTORE_FAIL
        }
        file="$decrypted"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore from $file"
        log_info "Contents:"
        if [[ "$file" =~ \.gz$ ]]; then
            tar -tzvf "$file" | head -20
        elif [[ "$file" =~ \.xz$ ]]; then
            tar -tJvf "$file" | head -20
        else
            tar -tvf "$file" | head -20
        fi
        return 0
    fi

    # Extract
    if [[ "$file" =~ \.gz$ ]]; then
        tar -xzvf "$file" -C / 2> /dev/null || {
            log_error "Extraction failed"
            exit $EXIT_RESTORE_FAIL
        }
    elif [[ "$file" =~ \.xz$ ]]; then
        tar -xJvf "$file" -C / 2> /dev/null || {
            log_error "Extraction failed"
            exit $EXIT_RESTORE_FAIL
        }
    else
        tar -xvf "$file" -C / 2> /dev/null || {
            log_error "Extraction failed"
            exit $EXIT_RESTORE_FAIL
        }
    fi

    log_ok "Restore completed"
    log_warn "You may need to restart services for changes to take effect"
}

# Main function
main() {
    parse_args "$@"

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

    # Check permissions for backup
    if [[ $EUID -ne 0 && "$DRY_RUN" != "true" ]]; then
        log_warn "Running without root - some files may not be backed up"
    fi

    setup_backup_dir
    check_disk_space

    # Run backup sections
    for section in "${SECTIONS[@]}"; do
        case "$section" in
            etc) backup_etc ;;
            packages) backup_packages ;;
            crontabs) backup_crontabs ;;
            systemd) backup_systemd ;;
            ssh) backup_ssh ;;
            nginx) backup_nginx ;;
            apache) backup_apache ;;
            database) backup_database ;;
            *) log_warn "Unknown section: $section" ;;
        esac
    done

    # Create final backup
    create_final_backup

    exit $EXIT_OK
}

main "$@"
