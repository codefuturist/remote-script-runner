#!/bin/bash
#
# DNS GitOps Installation Script
# This script sets up automatic DNS synchronization from Git to Pi-hole + Unbound
#
# Usage: curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/sh/install-dns-gitops.sh | sudo bash
#

set -euo pipefail

# Configuration
REPO_URL="${DNS_REPO_URL:-https://github.com/codefuturist/ansible-infrastructure.git}"
REPO_BRANCH="${DNS_REPO_BRANCH:-develop}"
DNS_ZONES_PATH="${DNS_ZONES_PATH:-dns-zones}"
INSTALL_DIR="/opt/dns-gitops"
CACHE_DIR="/var/cache/dns-gitops"
STATE_DIR="/var/lib/dns-gitops"
LOG_DIR="/var/log/dns-gitops"
SERVICE_NAME="dns-gitops-sync"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_dependencies() {
    log_info "Checking dependencies..."
    
    local deps=("git" "named-checkzone" "systemctl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Installing missing dependencies..."
        
        if command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y git bind9-utils systemd
        elif command -v dnf &> /dev/null; then
            dnf install -y git bind-utils systemd
        else
            log_error "Unsupported package manager. Please install: ${missing[*]}"
            exit 1
        fi
    fi
}

check_pihole() {
    log_info "Checking Pi-hole installation..."
    
    if [[ ! -f /etc/pihole/pihole.toml ]]; then
        log_error "Pi-hole v6 not found. Please install Pi-hole first."
        log_info "Visit: https://pi-hole.net"
        exit 1
    fi
    
    log_info "Pi-hole v6 detected"
}

create_directories() {
    log_info "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CACHE_DIR"
    mkdir -p "$STATE_DIR"
    mkdir -p "$LOG_DIR"
    
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$CACHE_DIR"
    chmod 755 "$STATE_DIR"
    chmod 755 "$LOG_DIR"
}

install_sync_script() {
    log_info "Installing DNS sync script..."
    
    cat > "$INSTALL_DIR/dns-sync.sh" << 'SYNCSCRIPT'
#!/bin/bash
set -euo pipefail

REPO_URL="__REPO_URL__"
REPO_BRANCH="__REPO_BRANCH__"
DNS_ZONES_PATH="__DNS_ZONES_PATH__"
CACHE_DIR="__CACHE_DIR__"
STATE_DIR="__STATE_DIR__"
LOG_FILE="__LOG_DIR__/dns-sync.log"

REPO_DIR="$CACHE_DIR/repo"
ZONES_CACHE="$CACHE_DIR/zones"
LAST_COMMIT_FILE="$STATE_DIR/last_commit"
PIHOLE_CONFIG="/etc/pihole/pihole.toml"
UNBOUND_CONF_DIR="/etc/unbound/unbound.conf.d"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

clone_or_update_repo() {
    if [[ ! -d "$REPO_DIR/.git" ]]; then
        log "Cloning repository..."
        GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR" 2>&1 || {
            error "Failed to clone repository"
            return 1
        }
    else
        log "Updating repository..."
        cd "$REPO_DIR"
        GIT_TERMINAL_PROMPT=0 git fetch origin "$REPO_BRANCH" 2>&1 || {
            error "Failed to fetch updates"
            return 1
        }
        git reset --hard "origin/$REPO_BRANCH"
    fi
}

get_current_commit() {
    cd "$REPO_DIR"
    git rev-parse HEAD
}

has_changes() {
    local current_commit
    current_commit=$(get_current_commit)
    
    if [[ ! -f "$LAST_COMMIT_FILE" ]]; then
        return 0
    fi
    
    local last_commit
    last_commit=$(cat "$LAST_COMMIT_FILE")
    
    [[ "$current_commit" != "$last_commit" ]]
}

validate_zone_file() {
    local zone_file=$1
    local zone_name=$2
    
    if ! named-checkzone "$zone_name" "$zone_file" > /dev/null 2>&1; then
        error "Zone file validation failed: $zone_file"
        return 1
    fi
    
    return 0
}

extract_records_from_zone() {
    local zone_file=$1
    local output_file=$2
    
    > "$output_file"
    
    grep -E "^[^;#].*\s+(A|AAAA)\s+" "$zone_file" | while read -r line; do
        local hostname=$(echo "$line" | awk '{print $1}')
        local record_type=$(echo "$line" | awk '{print $3}')
        local ip=$(echo "$line" | awk '{print $4}')
        
        if [[ "$hostname" == "@" ]]; then
            continue
        fi
        
        hostname=$(echo "$hostname" | sed 's/\.$//')
        
        echo "$ip $hostname" >> "$output_file"
    done
}

process_zone_files() {
    local zones_dir="$REPO_DIR/$DNS_ZONES_PATH"
    
    if [[ ! -d "$zones_dir" ]]; then
        error "DNS zones directory not found: $zones_dir"
        return 1
    fi
    
    mkdir -p "$ZONES_CACHE"
    local temp_hosts="$ZONES_CACHE/hosts.tmp"
    > "$temp_hosts"
    
    local valid_zones=0
    local invalid_zones=0
    
    for zone_file in "$zones_dir"/*.zone; do
        if [[ ! -f "$zone_file" ]]; then
            continue
        fi
        
        local zone_name
        zone_name=$(basename "$zone_file" .zone)
        
        log "Processing zone: $zone_name"
        
        if validate_zone_file "$zone_file" "$zone_name"; then
            extract_records_from_zone "$zone_file" "$ZONES_CACHE/${zone_name}.hosts"
            cat "$ZONES_CACHE/${zone_name}.hosts" >> "$temp_hosts"
            ((valid_zones++))
            log "Successfully processed zone: $zone_name"
        else
            ((invalid_zones++))
            error "Skipping invalid zone: $zone_name"
        fi
    done
    
    if [[ $valid_zones -eq 0 ]]; then
        error "No valid zone files found"
        return 1
    fi
    
    log "Processed $valid_zones valid zones, $invalid_zones invalid zones"
    
    sort -u "$temp_hosts" > "$ZONES_CACHE/hosts"
    
    return 0
}

apply_to_pihole() {
    local hosts_file="$ZONES_CACHE/hosts"
    
    if [[ ! -f "$hosts_file" ]]; then
        error "No hosts file to apply"
        return 1
    fi
    
    log "Backing up Pi-hole configuration..."
    cp "$PIHOLE_CONFIG" "$PIHOLE_CONFIG.backup-$(date +%Y%m%d-%H%M%S)"
    
    log "Updating Pi-hole configuration..."
    
    python3 - <<EOF
import tomli
import tomli_w
from pathlib import Path

config_file = Path("$PIHOLE_CONFIG")
hosts_file = Path("$hosts_file")

with open(config_file, "rb") as f:
    config = tomli.load(f)

if "dns" not in config:
    config["dns"] = {}
if "hosts" not in config["dns"]:
    config["dns"]["hosts"] = []

gitops_hosts = []
with open(hosts_file) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#"):
            gitops_hosts.append(line)

config["dns"]["hosts"] = [h for h in config["dns"]["hosts"] if "# gitops" not in h]
config["dns"]["hosts"].extend([f"{h} # gitops" for h in gitops_hosts])

with open(config_file, "wb") as f:
    tomli_w.dump(config, f)

print(f"Added {len(gitops_hosts)} DNS records to Pi-hole")
EOF
    
    log "Restarting Pi-hole DNS..."
    pihole restartdns
    
    return 0
}

main() {
    log "Starting DNS GitOps sync..."
    
    clone_or_update_repo
    
    if ! has_changes; then
        log "No changes detected, skipping sync"
        exit 0
    fi
    
    log "Changes detected, processing..."
    
    if ! process_zone_files; then
        error "Failed to process zone files"
        exit 1
    fi
    
    if ! apply_to_pihole; then
        error "Failed to apply changes to Pi-hole"
        exit 1
    fi
    
    get_current_commit > "$LAST_COMMIT_FILE"
    
    log "DNS GitOps sync completed successfully"
}

main "$@"
SYNCSCRIPT

    # Replace placeholders
    sed -i "s|__REPO_URL__|$REPO_URL|g" "$INSTALL_DIR/dns-sync.sh"
    sed -i "s|__REPO_BRANCH__|$REPO_BRANCH|g" "$INSTALL_DIR/dns-sync.sh"
    sed -i "s|__DNS_ZONES_PATH__|$DNS_ZONES_PATH|g" "$INSTALL_DIR/dns-sync.sh"
    sed -i "s|__CACHE_DIR__|$CACHE_DIR|g" "$INSTALL_DIR/dns-sync.sh"
    sed -i "s|__STATE_DIR__|$STATE_DIR|g" "$INSTALL_DIR/dns-sync.sh"
    sed -i "s|__LOG_DIR__|$LOG_DIR|g" "$INSTALL_DIR/dns-sync.sh"
    
    chmod +x "$INSTALL_DIR/dns-sync.sh"
}

install_python_deps() {
    log_info "Installing Python dependencies..."
    
    if command -v apt-get &> /dev/null; then
        apt-get install -y python3-tomli python3-tomli-w 2>/dev/null || log_warn "Could not install via apt, trying pip..."
    fi
    
    if ! python3 -c "import tomli, tomli_w" 2>/dev/null; then
        if command -v pip3 &> /dev/null; then
            pip3 install --break-system-packages tomli tomli-w 2>/dev/null || log_warn "Could not install Python TOML libraries via pip"
        else
            log_warn "Could not install Python TOML libraries. Please install tomli and tomli-w manually."
        fi
    else
        log_info "Python TOML libraries already installed"
    fi
}

install_systemd_service() {
    log_info "Installing systemd service..."
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=DNS GitOps Sync Service
After=network-online.target pihole-FTL.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/dns-sync.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

    cat > "/etc/systemd/system/${SERVICE_NAME}.timer" << EOF
[Unit]
Description=DNS GitOps Sync Timer
Requires=${SERVICE_NAME}.service

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.timer"
    systemctl start "${SERVICE_NAME}.timer"
}

print_summary() {
    log_info ""
    log_info "╔═══════════════════════════════════════════════════════════╗"
    log_info "║         DNS GitOps Installation Complete!                ║"
    log_info "╚═══════════════════════════════════════════════════════════╝"
    log_info ""
    log_info "Configuration:"
    log_info "  Repository: $REPO_URL"
    log_info "  Branch: $REPO_BRANCH"
    log_info "  DNS Zones Path: $DNS_ZONES_PATH"
    log_info "  Install Directory: $INSTALL_DIR"
    log_info "  Log File: $LOG_DIR/dns-sync.log"
    log_info ""
    log_info "Service Status:"
    systemctl status "${SERVICE_NAME}.timer" --no-pager || true
    log_info ""
    log_info "Useful Commands:"
    log_info "  Manual sync:  sudo $INSTALL_DIR/dns-sync.sh"
    log_info "  View logs:    sudo journalctl -u $SERVICE_NAME -f"
    log_info "  Service logs: sudo tail -f $LOG_DIR/dns-sync.log"
    log_info "  Check timer:  sudo systemctl status ${SERVICE_NAME}.timer"
    log_info ""
}

main() {
    log_info "DNS GitOps Installation Starting..."
    log_info ""
    
    check_root
    check_dependencies
    check_pihole
    create_directories
    install_sync_script
    install_python_deps
    install_systemd_service
    
    log_info "Running initial sync..."
    "$INSTALL_DIR/dns-sync.sh" || log_warn "Initial sync failed, will retry automatically"
    
    print_summary
}

main "$@"
