# DNS GitOps Standalone Service

## Overview

The `dns-sync` service is a **standalone systemd service** specifically designed for DNS zone synchronization. It operates **independently** from the main `gitops-sync` service, allowing dedicated DNS management without affecting other GitOps operations.

## Why Standalone?

**Separation of Concerns:**
- ✅ DNS sync runs independently
- ✅ Doesn't interfere with other GitOps operations
- ✅ Can be stopped/started without affecting other services
- ✅ Dedicated logging and monitoring
- ✅ Isolated resource limits
- ✅ Independent timer configuration

## Components

### Service Files

```
/etc/systemd/system/dns-sync.service    # Systemd service
/etc/systemd/system/dns-sync.timer      # Timer (runs every 3 min)
/opt/gitops/dns-sync.sh                 # Main sync script
/opt/gitops/sync-dns-zones.py           # Zone parser (shared)
/var/log/dns-sync.log                   # Dedicated log file
/var/cache/gitops-dns/                  # Cache directory
```

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    dns-sync.timer                       │
│                  (Every 3 minutes)                      │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                  dns-sync.service                       │
│              (Standalone systemd unit)                  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                   dns-sync.sh                           │
│         (Bash orchestration script)                     │
│                                                          │
│  1. Git clone/pull                                      │
│  2. Validate environment                                │
│  3. Call sync-dns-zones.py                              │
│  4. Restart Pi-hole FTL                                 │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│              sync-dns-zones.py                          │
│        (3-phase validation workflow)                    │
│                                                          │
│  Phase 1: Pre-validate all zones                       │
│  Phase 2: Convert & validate CNAMEs                    │
│  Phase 3: Apply to Pi-hole                             │
└─────────────────────────────────────────────────────────┘
```

## Service Configuration

### Environment Variables

The service can be configured via environment variables in the service file:

```ini
# Git Repository
Environment="DNS_REPO_URL=https://github.com/codefuturist/iac-catalog.git"
Environment="DNS_REPO_BRANCH=develop"
Environment="DNS_REPO_PATH=/opt/gitops/iac-catalog"

# Zone Files Location
Environment="DNS_ZONES_PATH=environments/global/configurations/dns-zones"

# Pi-hole Configuration
Environment="PIHOLE_TOML_PATH=/etc/pihole/pihole.toml"

# Cache and Logging
Environment="DNS_CACHE_DIR=/var/cache/gitops-dns"
Environment="DNS_LOG_FILE=/var/log/dns-sync.log"
Environment="DNS_LOG_LEVEL=INFO"
```

### Modifying Configuration

```bash
# Edit service file
sudo systemctl edit dns-sync.service --full

# Reload systemd
sudo systemctl daemon-reload

# Restart service
sudo systemctl restart dns-sync.timer
```

## Usage

### Service Management

```bash
# Enable timer (auto-start on boot)
sudo systemctl enable dns-sync.timer

# Start timer
sudo systemctl start dns-sync.timer

# Stop timer
sudo systemctl stop dns-sync.timer

# Disable timer
sudo systemctl disable dns-sync.timer

# Check timer status
sudo systemctl status dns-sync.timer

# View next scheduled run
systemctl list-timers dns-sync.timer
```

### Manual Sync

```bash
# Trigger immediate sync (bypassing timer)
sudo systemctl start dns-sync.service

# Monitor sync progress
sudo journalctl -u dns-sync.service -f

# Check sync status
sudo systemctl status dns-sync.service
```

### Script Commands

The `dns-sync.sh` script can be run directly with different commands:

```bash
# Full sync (default)
sudo /opt/gitops/dns-sync.sh sync

# Health check only
sudo /opt/gitops/dns-sync.sh health

# Initialize repository only
sudo /opt/gitops/dns-sync.sh init

# Update repository only (no sync)
sudo /opt/gitops/dns-sync.sh update
```

## Monitoring

### Check Service Status

```bash
# Service status
sudo systemctl status dns-sync.service

# Timer status
sudo systemctl status dns-sync.timer

# Last run information
systemctl list-timers dns-sync.timer --all
```

### View Logs

```bash
# Dedicated log file
sudo tail -f /var/log/dns-sync.log

# Systemd journal
sudo journalctl -u dns-sync.service -f

# Show last 100 lines
sudo journalctl -u dns-sync.service -n 100

# Show logs since today
sudo journalctl -u dns-sync.service --since today
```

### Health Check

```bash
# Run health check
sudo /opt/gitops/dns-sync.sh health

# Check cache status
ls -lh /var/cache/gitops-dns/

# View last successful sync
cat /var/cache/gitops-dns/last_dns_sync_success

# View last failure (if any)
cat /var/cache/gitops-dns/last_dns_sync_failure 2>/dev/null
```

## Comparison with gitops-sync

| Feature | dns-sync (Standalone) | gitops-sync |
|---------|----------------------|-------------|
| Purpose | DNS zones only | All GitOps operations |
| Timer | 3 minutes | 3 minutes |
| Log File | `/var/log/dns-sync.log` | `/var/log/gitops-sync.log` |
| Service | `dns-sync.service` | `gitops-sync.service` |
| Can run separately | ✅ Yes | ✅ Yes |
| Dependencies | Pi-hole only | Docker, secrets, etc. |
| Resource limits | 50% CPU, 512MB RAM | Higher limits |

## Integration Scenarios

### Scenario 1: DNS-Only Host

Use **only** `dns-sync` service:

```bash
# Enable DNS sync
sudo systemctl enable dns-sync.timer
sudo systemctl start dns-sync.timer

# Optionally disable gitops-sync if not needed
sudo systemctl disable gitops-sync.timer
sudo systemctl stop gitops-sync.timer
```

**Use Case:** Dedicated DNS server (Pi-hole only)

### Scenario 2: Full GitOps Host

Use **only** `gitops-sync` service (already includes DNS):

```bash
# Keep gitops-sync (includes DNS sync)
sudo systemctl enable gitops-sync.timer
sudo systemctl start gitops-sync.timer

# Disable standalone DNS sync (to avoid duplicate syncs)
sudo systemctl disable dns-sync.timer
sudo systemctl stop dns-sync.timer
```

**Use Case:** Full infrastructure host (Docker + Pi-hole + more)

### Scenario 3: Both Services

Run **both** services (different sync intervals):

```bash
# gitops-sync for everything (3 minutes)
sudo systemctl enable gitops-sync.timer

# dns-sync for more frequent DNS updates (1 minute)
sudo systemctl edit dns-sync.timer
# Change OnUnitActiveSec=1min

sudo systemctl daemon-reload
sudo systemctl enable dns-sync.timer
sudo systemctl start dns-sync.timer
```

**Use Case:** Critical DNS that needs faster propagation

## Troubleshooting

### Service Won't Start

```bash
# Check service status
sudo systemctl status dns-sync.service

# View detailed logs
sudo journalctl -u dns-sync.service -n 50

# Check script syntax
bash -n /opt/gitops/dns-sync.sh

# Test script manually
sudo /opt/gitops/dns-sync.sh sync
```

### Repository Issues

```bash
# Check repository state
cd /opt/gitops/iac-catalog
git status
git remote -v

# Re-initialize repository
sudo rm -rf /opt/gitops/iac-catalog
sudo /opt/gitops/dns-sync.sh init
```

### Permission Issues

```bash
# Check file ownership
ls -la /opt/gitops/dns-sync.sh
ls -la /var/log/dns-sync.log

# Fix ownership
sudo chown root:root /opt/gitops/dns-sync.sh
sudo chmod +x /opt/gitops/dns-sync.sh

# Check sudoers
sudo visudo -c -f /etc/sudoers.d/dns-sync
```

### Timer Not Running

```bash
# Check if timer is enabled
systemctl is-enabled dns-sync.timer

# Check timer status
sudo systemctl status dns-sync.timer

# List all timers
systemctl list-timers --all

# Restart timer
sudo systemctl restart dns-sync.timer
```

## Security

### Resource Limits

The service has built-in resource limits:

```ini
CPUQuota=50%        # Max 50% CPU usage
MemoryMax=512M      # Max 512MB RAM
PrivateTmp=yes      # Isolated /tmp
ProtectHome=yes     # Home directories protected
```

### File System Access

Limited write access to:
- `/opt/gitops` - Scripts and repository
- `/var/log` - Log files
- `/var/run` - Lock files
- `/var/cache/gitops-dns` - Cache
- `/etc/pihole` - Pi-hole configuration
- `/tmp` - Temporary files

### Sudo Permissions

Minimal sudo permissions in `/etc/sudoers.d/dns-sync`:
- Run sync-dns-zones.py
- Backup Pi-hole config
- Restart Pi-hole FTL
- Check Pi-hole status

## Best Practices

### 1. Monitor First Run

```bash
# Watch first sync
sudo systemctl start dns-sync.service
sudo journalctl -u dns-sync.service -f
```

### 2. Check Logs Regularly

```bash
# Add to daily routine
sudo tail /var/log/dns-sync.log

# Or set up log rotation
sudo vi /etc/logrotate.d/dns-sync
```

### 3. Test Before Production

```bash
# Test with dry-run first
sudo python3 /opt/gitops/sync-dns-zones.py --dry-run \
  /opt/gitops/iac-catalog/environments/global/configurations/dns-zones \
  /etc/pihole/pihole.toml
```

### 4. Backup Schedule

```bash
# Backups are automatic, but verify
ls -lh /etc/pihole/pihole.toml.backup-* | tail -10

# Clean old backups if needed
sudo find /etc/pihole -name "pihole.toml.backup-*" -mtime +30 -delete
```

## Advanced Configuration

### Change Sync Interval

```bash
# Edit timer
sudo systemctl edit dns-sync.timer --full

# Change line:
OnUnitActiveSec=1min  # For 1 minute interval

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart dns-sync.timer
```

### Multiple Repositories

```bash
# Create second service
sudo cp /etc/systemd/system/dns-sync.service \
       /etc/systemd/system/dns-sync-prod.service

# Edit environment variables
sudo systemctl edit dns-sync-prod.service --full

# Change:
Environment="DNS_REPO_URL=https://github.com/org/prod-dns.git"
Environment="DNS_LOG_FILE=/var/log/dns-sync-prod.log"

# Create timer
sudo systemctl enable dns-sync-prod.timer
sudo systemctl start dns-sync-prod.timer
```

### Debug Mode

```bash
# Enable debug logging
sudo systemctl edit dns-sync.service --full

# Change:
Environment="DNS_LOG_LEVEL=DEBUG"

# Reload
sudo systemctl daemon-reload
sudo systemctl restart dns-sync.timer
```

## Migration Guide

### From gitops-sync to dns-sync

If you want to use standalone DNS sync:

```bash
# 1. Ensure dns-sync is installed
sudo systemctl status dns-sync.service

# 2. Enable dns-sync
sudo systemctl enable dns-sync.timer
sudo systemctl start dns-sync.timer

# 3. Test it works
sudo systemctl start dns-sync.service
sudo journalctl -u dns-sync.service -n 50

# 4. Optionally disable gitops-sync if only using Pi-hole
sudo systemctl disable gitops-sync.timer
sudo systemctl stop gitops-sync.timer
```

### From standalone back to gitops-sync

```bash
# 1. Stop standalone service
sudo systemctl stop dns-sync.timer
sudo systemctl disable dns-sync.timer

# 2. Enable gitops-sync
sudo systemctl enable gitops-sync.timer
sudo systemctl start gitops-sync.timer

# 3. Verify
sudo systemctl status gitops-sync.timer
```

## Summary

✅ **Standalone Service**: Runs independently of gitops-sync
✅ **Dedicated Logging**: Separate log file for DNS operations
✅ **Resource Limits**: Controlled CPU and memory usage
✅ **Flexible Deployment**: Use alone or with gitops-sync
✅ **Same Validation**: Uses 3-phase validation workflow
✅ **Cache System**: Shares cache with gitops-sync
✅ **Easy Management**: Standard systemd commands

---

**Service**: `dns-sync.service`  
**Timer**: `dns-sync.timer`  
**Log**: `/var/log/dns-sync.log`  
**Script**: `/opt/gitops/dns-sync.sh`  
**Interval**: 3 minutes (configurable)  
**Status**: ✅ Production Ready
