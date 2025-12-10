# DNS GitOps Installation

Automated installation script for DNS GitOps system compatible with Pi-hole v6 + Unbound.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/scripts/bash/install-dns-gitops.sh | bash
```

## What Gets Installed

- ✅ DNS zone parser (`sync-dns-zones.py`)
- ✅ Standalone DNS sync service (`dns-sync.service`)
- ✅ Systemd timer (every 3 minutes)
- ✅ Health check script
- ✅ Automatic backups
- ✅ 3-phase validation workflow
- ✅ Cache system

## Features

### Industry Standard
- Uses standard BIND zone files
- Compatible with existing DNS tools
- RFC 1035 compliant

### Validation & Safety
- Pre-validates ALL zones before applying
- Only applies if 100% valid
- Destination config never touched until validated
- Automatic backup before changes
- Auto-restore on failure

### Monitoring
- Dedicated log file (`/var/log/dns-sync.log`)
- Health check command
- Systemd integration
- Cache tracking

## Prerequisites

- Pi-hole v6+ (with TOML configuration)
- Python 3.6+
- Git
- Systemd
- Sudo access

## Installation Options

The installer will ask:

1. **Repository URL** - Where your DNS zone files are stored
2. **Branch** - Which branch to sync from (default: develop)
3. **Service Type**:
   - **Standalone** - DNS sync only (recommended for DNS-only servers)
   - **Integrated** - Part of full GitOps (for infrastructure servers)
4. **Sync Interval** - How often to sync (default: 3 minutes)

## Manual Installation

```bash
# Download the installer
curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/scripts/bash/install-dns-gitops.sh \
  -o install-dns-gitops.sh

# Make executable
chmod +x install-dns-gitops.sh

# Run installer
./install-dns-gitops.sh install
```

## Post-Installation

### Check Status

```bash
# Service status
sudo systemctl status dns-sync.timer

# View logs
sudo tail -f /var/log/dns-sync.log

# Health check
sudo /opt/gitops/check-dns-sync-health.sh
```

### Test DNS Resolution

```bash
dig your-hostname.your-zone.com @127.0.0.1
```

### Manual Sync

```bash
sudo systemctl start dns-sync.service
```

## Zone File Format

Create standard BIND zone files:

```bind
$ORIGIN example.com.
@     900    IN  SOA    ns1 admin 1 900 300 604800 900
@     3600   IN  NS     ns1

; A Records
server1       3600    IN  A      192.168.1.10
server2       3600    IN  A      192.168.1.20

; AAAA Records
ipv6host      3600    IN  AAAA   2001:db8::1

; CNAME Records
www           3600    IN  CNAME  server1
api           3600    IN  CNAME  server2

; Wildcards
*.apps        3600    IN  A      192.168.1.50
```

Place zone files in:
```
/opt/gitops/iac-catalog/environments/global/configurations/dns-zones/
```

## Validation

The system validates in 3 phases:

**Phase 1: Pre-Validation**
- Parse all zone files
- Validate DNS records
- Check hostname format
- Verify IP addresses

**Phase 2: Conversion**
- Convert to Pi-hole format
- Resolve CNAME chains
- Detect circular references
- Cache validated config

**Phase 3: Application**
- Create backup
- Apply changes
- Verify written content
- Restart DNS service

**CRITICAL**: If ANY validation fails, NO changes are applied!

## Dry Run Testing

Test changes before applying:

```bash
sudo python3 /opt/gitops/sync-dns-zones.py --dry-run \
  /opt/gitops/iac-catalog/environments/global/configurations/dns-zones \
  /etc/pihole/pihole.toml
```

## Configuration

### Change Sync Interval

```bash
# Edit timer
sudo systemctl edit dns-sync.timer --full

# Change line:
OnUnitActiveSec=1min  # For 1 minute interval

# Reload
sudo systemctl daemon-reload
sudo systemctl restart dns-sync.timer
```

### Change Repository

```bash
# Edit service
sudo systemctl edit dns-sync.service --full

# Update environment variables
Environment="DNS_REPO_URL=https://github.com/your/repo.git"
Environment="DNS_REPO_BRANCH=main"

# Reload
sudo systemctl daemon-reload
sudo systemctl restart dns-sync.service
```

## Uninstall

```bash
./install-dns-gitops.sh uninstall
```

Or manually:

```bash
# Stop service
sudo systemctl stop dns-sync.timer
sudo systemctl disable dns-sync.timer

# Remove files
sudo rm /etc/systemd/system/dns-sync.{service,timer}
sudo rm /etc/sudoers.d/dns-sync
sudo rm /opt/gitops/{dns-sync.sh,sync-dns-zones.py,check-dns-sync-health.sh}

# Reload
sudo systemctl daemon-reload
```

## Troubleshooting

### Service Won't Start

```bash
# Check status
sudo systemctl status dns-sync.service

# View logs
sudo journalctl -u dns-sync.service -n 50

# Test script manually
sudo /opt/gitops/dns-sync.sh sync
```

### Validation Errors

```bash
# Check what failed
sudo grep "ABORTING\|FAILED" /var/log/dns-sync.log

# View cache
cat /var/cache/gitops-dns/last_*_failed
```

### Repository Issues

```bash
# Re-initialize repository
sudo rm -rf /opt/gitops/iac-catalog
sudo /opt/gitops/dns-sync.sh init
```

## Files & Directories

```
/opt/gitops/
├── dns-sync.sh                 # Main sync script
├── sync-dns-zones.py           # Zone parser
├── check-dns-sync-health.sh    # Health check
└── iac-catalog/                # Git repository
    └── environments/global/configurations/dns-zones/
        └── *.zone              # Your zone files

/etc/systemd/system/
├── dns-sync.service            # Service definition
└── dns-sync.timer              # Timer (3 min)

/var/log/
└── dns-sync.log                # Dedicated log file

/var/cache/gitops-dns/
├── validated_hosts.cache       # Last validated config
├── last_successful_sync        # Success timestamp
├── last_validation_failed      # Parse errors (if any)
└── last_conversion_failed      # CNAME errors (if any)

/etc/pihole/
├── pihole.toml                 # Pi-hole config
└── pihole.toml.backup-*        # Automatic backups
```

## Support & Documentation

- **GitHub**: https://github.com/codefuturist/remote-script-runner
- **Issues**: https://github.com/codefuturist/remote-script-runner/issues

## Features Summary

✅ **Industry Standard**: BIND zone files
✅ **Multi-Zone**: Unlimited zones supported
✅ **Record Types**: A, AAAA, CNAME, wildcards
✅ **Validation**: 3-phase workflow
✅ **Safety**: No changes until 100% valid
✅ **Auto-Backup**: Before every change
✅ **Auto-Restore**: On failure
✅ **Cache System**: Audit trail
✅ **Health Monitoring**: Status checks
✅ **Resource Limits**: 50% CPU, 512MB RAM

## License

This script is part of the remote-script-runner project.
