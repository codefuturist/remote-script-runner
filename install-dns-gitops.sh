#!/bin/bash
# DNS GitOps Installer
# Installs and configures automatic DNS zone file sync from Git to Pi-hole + Unbound
set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="${DNS_REPO_URL:-https://github.com/codefuturist/dns-zones.git}"
REPO_BRANCH="${DNS_REPO_BRANCH:-main}"
ZONE_PATH="${DNS_ZONE_PATH:-zones}"
CACHE_DIR="${DNS_CACHE_DIR:-/var/cache/dns-gitops}"
SCRIPT_INSTALL_PATH="/usr/local/bin/dns-gitops-sync.sh"
SERVICE_NAME="dns-gitops-sync"
TIMER_INTERVAL="${DNS_SYNC_INTERVAL:-5min}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_dependencies() {
    log_info "Checking dependencies..."
    local missing=()
    
    for cmd in git named-checkzone pihole-FTL; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Please install: git, bind-utils (for named-checkzone), and Pi-hole"
        exit 1
    fi
    
    log_info "All dependencies found"
}

create_sync_script() {
    log_info "Creating DNS sync script..."
    
    cat > "$SCRIPT_INSTALL_PATH" << 'SYNCEOF'
#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/codefuturist/ansible-automations.git"
REPO_BRANCH="develop"
ZONE_PATH="dns-zones"
CACHE_DIR="/var/cache/dns-gitops"
PIHOLE_CONFIG="/etc/pihole/pihole.toml"
UNBOUND_CONF_DIR="/etc/unbound/unbound.conf.d"
STATE_FILE="$CACHE_DIR/.last-sync"
LOG_FILE="/var/log/dns-gitops-sync.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

ensure_cache_dir() {
    mkdir -p "$CACHE_DIR"
    if [[ ! -d "$CACHE_DIR/repo" ]]; then
        log "Cloning repository..."
        git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$CACHE_DIR/repo"
    fi
}

update_repo() {
    cd "$CACHE_DIR/repo"
    local before_hash=$(git rev-parse HEAD)
    git fetch origin "$REPO_BRANCH"
    git reset --hard "origin/$REPO_BRANCH"
    local after_hash=$(git rev-parse HEAD)
    
    if [[ "$before_hash" != "$after_hash" ]]; then
        log "Repository updated: $before_hash -> $after_hash"
        echo "$after_hash" > "$STATE_FILE"
        return 0
    else
        log "No changes detected"
        return 1
    fi
}

validate_zone_file() {
    local zone_file="$1"
    local zone_name=$(basename "$zone_file" .zone)
    
    if named-checkzone "$zone_name" "$zone_file" &>/dev/null; then
        return 0
    else
        log "ERROR: Zone file $zone_file failed validation"
        return 1
    fi
}

extract_hosts_from_zone() {
    local zone_file="$1"
    local zone_name=$(basename "$zone_file" .zone)
    
    awk -v zone="$zone_name" '
        /^[^;]/ && /IN[ \t]+A[ \t]+/ {
            if ($1 == "@") {
                print $NF " " zone
            } else if ($1 !~ /\.$/) {
                print $NF " " $1 "." zone
            }
        }
    ' "$zone_file"
}

apply_to_pihole() {
    local temp_hosts="$CACHE_DIR/hosts.tmp"
    > "$temp_hosts"
    
    for zone_file in "$CACHE_DIR/repo/$ZONE_PATH"/*.zone; do
        if [[ -f "$zone_file" ]]; then
            if validate_zone_file "$zone_file"; then
                log "Processing zone: $(basename "$zone_file")"
                extract_hosts_from_zone "$zone_file" >> "$temp_hosts"
            fi
        fi
    done
    
    if [[ -s "$temp_hosts" ]]; then
        local host_count=$(wc -l < "$temp_hosts")
        log "Applying $host_count DNS entries to Pi-hole..."
        
        if python3 -c "
import tomli_w
import tomli
import sys

with open('$PIHOLE_CONFIG', 'rb') as f:
    config = tomli.load(f)

new_hosts = []
with open('$temp_hosts', 'r') as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) == 2:
            new_hosts.append(f'{parts[0]} {parts[1]}')

config['dns'] = config.get('dns', {})
config['dns']['hosts'] = new_hosts

with open('$PIHOLE_CONFIG', 'wb') as f:
    tomli_w.dump(config, f)
" 2>&1; then
            log "Successfully updated Pi-hole configuration"
            pihole restartdns reload-lists
            return 0
        else
            log "ERROR: Failed to update Pi-hole configuration"
            return 1
        fi
    fi
}

main() {
    log "Starting DNS GitOps sync..."
    
    ensure_cache_dir
    
    if update_repo; then
        apply_to_pihole
        log "DNS sync completed successfully"
    else
        log "No changes to apply"
    fi
}

main "$@"
SYNCEOF

    chmod +x "$SCRIPT_INSTALL_PATH"
    log_info "Sync script created at $SCRIPT_INSTALL_PATH"
}

create_systemd_service() {
    log_info "Creating systemd service..."
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=DNS GitOps Sync Service
Documentation=https://github.com/codefuturist/remote-script-runner
After=network-online.target pihole-FTL.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_INSTALL_PATH
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$CACHE_DIR /etc/pihole /etc/unbound /var/log

[Install]
WantedBy=multi-user.target
EOF

    log_info "Service file created"
}

create_systemd_timer() {
    log_info "Creating systemd timer..."
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.timer" << EOF
[Unit]
Description=DNS GitOps Sync Timer
Documentation=https://github.com/codefuturist/remote-script-runner

[Timer]
OnBootSec=2min
OnUnitActiveSec=${TIMER_INTERVAL}
AccuracySec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    log_info "Timer file created"
}

install_python_deps() {
    log_info "Installing Python dependencies..."
    pip3 install --quiet tomli tomli-w 2>/dev/null || {
        log_warn "Could not install Python packages with pip3, trying apt..."
        apt-get update -qq && apt-get install -y -qq python3-tomli python3-tomli-w 2>/dev/null || {
            log_error "Failed to install Python dependencies"
            exit 1
        }
    }
}

enable_and_start() {
    log_info "Enabling and starting service..."
    
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.timer"
    systemctl start "${SERVICE_NAME}.timer"
    
    log_info "Running initial sync..."
    systemctl start "${SERVICE_NAME}.service" || log_warn "Initial sync failed (may be normal on first run)"
}

show_status() {
    echo ""
    log_info "Installation complete!"
    echo ""
    echo "Service: ${SERVICE_NAME}.service"
    echo "Timer: ${SERVICE_NAME}.timer"
    echo "Script: $SCRIPT_INSTALL_PATH"
    echo "Cache: $CACHE_DIR"
    echo "Sync interval: $TIMER_INTERVAL"
    echo ""
    echo "Commands:"
    echo "  Check status: systemctl status ${SERVICE_NAME}.timer"
    echo "  View logs: journalctl -u ${SERVICE_NAME}.service -f"
    echo "  Manual sync: systemctl start ${SERVICE_NAME}.service"
    echo "  Disable: systemctl stop ${SERVICE_NAME}.timer && systemctl disable ${SERVICE_NAME}.timer"
    echo ""
}

main() {
    log_info "DNS GitOps Installer v${VERSION}"
    echo ""
    
    check_root
    check_dependencies
    install_python_deps
    create_sync_script
    create_systemd_service
    create_systemd_timer
    enable_and_start
    show_status
}

main "$@"
