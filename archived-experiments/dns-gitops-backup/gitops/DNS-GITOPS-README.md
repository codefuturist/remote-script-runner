# DNS GitOps Automation for Pi-hole + Unbound

## Overview

This system automatically synchronizes DNS zone files from GitHub to Pi-hole + Unbound using a GitOps approach. It supports industry-standard BIND zone file format and multiple DNS zones.

## Architecture

```
GitHub Repository (iac-catalog)
    └── environments/global/configurations/dns-zones/
        ├── pandia.io.zone
        ├── test.local.zone
        └── *.zone (any additional zones)
                ↓
        gitops-sync.timer (every 3 minutes)
                ↓
        gitops-sync.service
                ↓
        sync-dns-zones.py
                ↓
        Parse BIND zone files
                ↓
        Convert to Pi-hole TOML format
                ↓
        Update /etc/pihole/pihole.toml
                ↓
        Restart pihole-FTL
                ↓
        DNS Changes Applied
```

## Features

✅ **Industry Standard Format**: Uses standard BIND zone files  
✅ **Multi-Zone Support**: Handles multiple DNS zones automatically  
✅ **Record Types**: Supports A, AAAA, and CNAME records  
✅ **CNAME Resolution**: Automatically resolves CNAME chains  
✅ **Wildcard Records**: Full support for wildcard DNS entries  
✅ **Automatic Sync**: Changes sync every 3 minutes via systemd timer  
✅ **Backup**: Automatic backup of pihole.toml before changes  
✅ **Logging**: Detailed logging to /var/log/gitops-sync.log  

## Zone File Format

### Standard BIND Zone File

```bind
; Example Zone File
$ORIGIN example.com.
@                     900       IN  SOA           ns1.example.com. admin 1 900 300 604800 900
@                     3600      IN  NS            ns1.example.com.

; A Records
host1                 3600      IN  A             192.168.1.10
host2                 3600      IN  A             192.168.1.20

; AAAA Records
ipv6host              3600      IN  AAAA          2001:db8::1

; CNAME Records
www                   3600      IN  CNAME         host1
api                   3600      IN  CNAME         host2

; Wildcard Records
*.apps                3600      IN  A             192.168.1.50
```

## Adding DNS Entries

### 1. Edit Zone File

```bash
cd /path/to/iac-catalog
vi environments/global/configurations/dns-zones/your-zone.zone
```

### 2. Add Your Records

```bind
; Add your records following BIND format
newhost               3600      IN  A             192.168.1.100
newapp                3600      IN  CNAME         newhost
```

### 3. Commit and Push

```bash
git add environments/global/configurations/dns-zones/your-zone.zone
git commit -m "Add new DNS entries for <purpose>"
git push origin develop
```

### 4. Wait for Sync

The gitops-sync timer runs every 3 minutes. Changes will be applied automatically.

### 5. Verify

```bash
# Check DNS resolution
dig newhost.your-zone.com @127.0.0.1

# Check sync log
sudo tail -f /var/log/gitops-sync.log
```

## Manual Sync

To trigger an immediate sync:

```bash
sudo systemctl start gitops-sync.service
```

## Adding New Zones

To add a new DNS zone:

1. Create a new zone file:
   ```bash
   vi environments/global/configurations/dns-zones/newzone.com.zone
   ```

2. Add standard BIND zone format:
   ```bind
   $ORIGIN newzone.com.
   @                     900       IN  SOA           dns1 admin 1 900 300 604800 900
   @                     3600      IN  NS            dns1
   
   dns1                  3600      IN  A             192.168.1.1
   host1                 3600      IN  A             192.168.1.10
   ```

3. Commit and push:
   ```bash
   git add environments/global/configurations/dns-zones/newzone.com.zone
   git commit -m "Add newzone.com DNS zone"
   git push origin develop
   ```

The zone will be automatically detected and processed on the next sync cycle.

## Components

### Files

- `/opt/gitops/sync-dns-zones.py` - Zone file parser and Pi-hole updater
- `/opt/gitops/gitops-sync.sh` - Main GitOps sync script
- `/etc/systemd/system/gitops-sync.service` - Systemd service
- `/etc/systemd/system/gitops-sync.timer` - Systemd timer (3 min interval)
- `/etc/sudoers.d/gitops-dns-sync` - Sudo permissions
- `/var/log/gitops-sync.log` - Sync log file

### Configuration

The sync script looks for zone files in:
```
/opt/gitops/iac-catalog/environments/global/configurations/dns-zones/*.zone
```

Pi-hole configuration file:
```
/etc/pihole/pihole.toml
```

## Supported Record Types

| Type   | Support | Notes |
|--------|---------|-------|
| A      | ✅      | IPv4 addresses |
| AAAA   | ✅      | IPv6 addresses |
| CNAME  | ✅      | Canonical names (resolved to IPs) |
| NS     | ⚠️      | Ignored (not needed for local DNS) |
| SOA    | ⚠️      | Ignored (not needed for local DNS) |
| MX     | ❌      | Not supported by Pi-hole local DNS |
| TXT    | ❌      | Not supported by Pi-hole local DNS |
| SRV    | ❌      | Not supported by Pi-hole local DNS |

## Troubleshooting

### Check Sync Status

```bash
# View recent sync activity
sudo tail -100 /var/log/gitops-sync.log | grep DNS

# Check service status
sudo systemctl status gitops-sync.service

# Check timer status
sudo systemctl status gitops-sync.timer
```

### Manual Test

```bash
# Test zone file parser directly
sudo python3 /opt/gitops/sync-dns-zones.py \
  /opt/gitops/iac-catalog/environments/global/configurations/dns-zones \
  /etc/pihole/pihole.toml
```

### Verify DNS

```bash
# Test specific hostname
dig your-hostname.your-zone.com @127.0.0.1

# Check Pi-hole configuration
sudo grep -A50 "hosts = \[" /etc/pihole/pihole.toml
```

### Restore from Backup

If something goes wrong, restore from backup:

```bash
# List backups
ls -lah /etc/pihole/pihole.toml.backup-*

# Restore latest backup
sudo cp /etc/pihole/pihole.toml.backup-YYYYMMDD-HHMMSS /etc/pihole/pihole.toml

# Restart Pi-hole
sudo systemctl restart pihole-FTL
```

## Best Practices

1. **Use Comments**: Document your DNS entries in zone files
   ```bind
   ; Production web server
   web1    3600    IN  A    192.168.1.10
   ```

2. **Consistent TTL**: Use appropriate TTL values
   - Short-lived/testing: 60-300 seconds
   - Standard services: 3600 seconds (1 hour)
   - Stable infrastructure: 86400 seconds (24 hours)

3. **Naming Conventions**: Use clear, descriptive hostnames
   ```bind
   k8s-master-1    3600    IN  A    192.168.2.10
   k8s-worker-1    3600    IN  A    192.168.2.20
   ```

4. **Group Related Entries**: Organize records by function
   ```bind
   ; === Kubernetes Cluster ===
   ; === Storage Systems ===
   ; === Application Servers ===
   ```

5. **Test Before Production**: Test DNS changes in a development zone first

6. **Commit Messages**: Use descriptive commit messages
   ```bash
   git commit -m "Add DNS entries for new Kubernetes cluster"
   ```

## Integration with Ansible

This system integrates with the existing Ansible DNS role. Zone files can be managed either:
- **GitOps**: Directly edit zone files and push to GitHub
- **Ansible**: Use Ansible playbooks to generate zone files programmatically

Both approaches result in the same standard BIND zone files being synced to Pi-hole.

## Security

- Zone file parser runs as `colin` user
- Sudo permissions limited to specific commands only
- Pi-hole configuration files backed up before changes
- All operations logged for audit trail
- No password required (sudoers configuration)

## Monitoring

Monitor sync health:

```bash
# Watch live sync activity
sudo tail -f /var/log/gitops-sync.log

# Check for errors
sudo grep ERROR /var/log/gitops-sync.log

# View DNS sync statistics
sudo grep "Converted.*records" /var/log/gitops-sync.log | tail -10
```

## Version Information

- **Pi-hole Version**: 6.x (TOML-based configuration)
- **Unbound**: Upstream DNS resolver
- **GitOps Sync**: Automated via systemd timer
- **Zone Format**: Standard BIND zone files

## Support

For issues or questions:
1. Check logs: `/var/log/gitops-sync.log`
2. Verify zone file syntax: `named-checkzone <zone> <file>`
3. Test DNS resolution: `dig <hostname> @127.0.0.1`
4. Review this documentation

---

**Last Updated**: 2025-12-09  
**Maintained By**: GitOps Automation System
