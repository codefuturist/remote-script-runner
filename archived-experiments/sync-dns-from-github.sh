#!/bin/bash
set -e

REPO_URL="https://github.com/codefuturist/iac-catalog.git"
REPO_DIR="/tmp/iac-catalog-dns-sync"
DNS_FILE="environments/global/configurations/dns-zones/custom-dns.list"
PIHOLE_CUSTOM_LIST="/etc/pihole/custom.list"
LOG_FILE="/var/log/dns-sync.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting DNS sync from GitHub..."

# Clone or update the repository
if [ -d "$REPO_DIR" ]; then
    log "Updating existing repository..."
    cd "$REPO_DIR"
    git pull origin main
else
    log "Cloning repository..."
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
fi

# Check if DNS file exists
if [ ! -f "$DNS_FILE" ]; then
    log "ERROR: DNS file not found: $DNS_FILE"
    exit 1
fi

# Backup current Pi-hole custom.list
log "Backing up current Pi-hole custom.list..."
cp "$PIHOLE_CUSTOM_LIST" "${PIHOLE_CUSTOM_LIST}.backup-$(date +%Y%m%d-%H%M%S)"

# Copy new DNS file to Pi-hole
log "Updating Pi-hole custom DNS entries..."
cp "$DNS_FILE" "$PIHOLE_CUSTOM_LIST"

# Restart Pi-hole DNS
log "Restarting Pi-hole DNS..."
pihole restartdns reload-lists

log "DNS sync completed successfully!"
