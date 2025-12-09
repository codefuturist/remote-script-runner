# DNS GitOps Validation and Error Recovery

## Overview

The DNS GitOps system includes comprehensive validation and error recovery mechanisms to ensure reliability and prevent misconfiguration.

## Validation Layers

### 1. Pre-Parse Validation

**File System Checks:**
- Zone directory exists and is readable
- Pi-hole TOML file exists and is writable
- Zone files have .zone extension
- Proper file permissions

### 2. Parse-Time Validation

**Zone File Syntax:**
- Valid BIND zone file format
- Proper $ORIGIN directive
- Correct SOA and NS records (informational only)
- Valid record structure

**Record Validation:**
- Hostname validation (RFC 1035)
  - Maximum 253 characters total
  - Maximum 63 characters per label
  - Valid characters (alphanumeric and hyphen)
  - Must start/end with alphanumeric
- IP address validation
  - IPv4: Valid dotted decimal (A records)
  - IPv6: Valid colon-hexadecimal (AAAA records)
- TTL validation (0 to 2,147,483,647 seconds)
- CNAME target validation

**Error Handling:**
- Invalid records are logged and skipped
- Parsing continues for remaining records
- Critical errors abort the sync

### 3. Conversion-Time Validation

**Hostname Conflicts:**
- Duplicate hostname detection
- Multiple IPs for same hostname (last wins)
- Warning logged for duplicates

**CNAME Resolution:**
- Validates CNAME targets exist
- Resolves CNAME chains (max 10 depth)
- Detects circular CNAMEs
- Fails sync if CNAME cannot be resolved

**Data Integrity:**
- Ensures all CNAMEs resolve to IPs
- Validates final hosts list
- Checks for empty results

### 4. Application-Time Validation

**TOML Syntax:**
- Validates TOML structure before write
- Checks bracket balance
- Verifies hosts array exists

**File Operations:**
- Creates backup before changes
- Verifies write success
- Validates content after write
- Auto-restore on failure

## Error Recovery

### Automatic Recovery

**Backup and Restore:**
```
1. Create timestamped backup: pihole.toml.backup-YYYYMMDD-HHMMSS
2. Apply changes to pihole.toml
3. Verify written content
4. If verification fails → Restore from backup
5. Keep last 10 backups (configurable)
```

**Retry Logic:**
The gitops-sync service will automatically retry on the next cycle (every 3 minutes) if:
- Zone files are temporarily unavailable
- Network issues prevent Git pull
- Transient file system errors

**Continuous Operation:**
- Non-critical errors don't stop processing
- Service continues on timer schedule
- Manual intervention only needed for critical issues

### Manual Recovery

#### Scenario 1: Invalid Zone File

**Problem:** Zone file has syntax errors

**Detection:**
```bash
# Check logs for validation errors
sudo grep "ABORTING\|validation" /var/log/gitops-sync.log | tail -20
```

**Resolution:**
```bash
# Fix zone file in Git
cd ~/iac-catalog
vi environments/global/configurations/dns-zones/problematic.zone

# Test locally before push
sudo python3 /opt/gitops/sync-dns-zones.py --dry-run \
  /opt/gitops/iac-catalog/environments/global/configurations/dns-zones \
  /etc/pihole/pihole.toml

# If valid, commit and push
git add -A
git commit -m "Fix zone file syntax errors"
git push origin develop
```

#### Scenario 2: CNAME Resolution Failure

**Problem:** CNAME points to non-existent target

**Detection:**
```bash
# Check for unresolved CNAMEs
sudo grep "Failed to resolve CNAME" /var/log/gitops-sync.log | tail -10
```

**Resolution:**
```bash
# Option A: Add missing A record
vi environments/global/configurations/dns-zones/your-zone.zone
# Add: target-host    3600    IN  A    192.168.1.100

# Option B: Change CNAME to point to existing host
# Edit CNAME to point to valid target

# Option C: Convert CNAME to A record
# Replace: alias  3600  IN  CNAME  target
# With:    alias  3600  IN  A      192.168.1.100
```

#### Scenario 3: Corrupted Pi-hole Config

**Problem:** Pi-hole TOML file is corrupted

**Detection:**
```bash
# Pi-hole FTL fails to start
sudo systemctl status pihole-FTL

# Or TOML syntax errors in logs
sudo grep "TOML.*invalid" /var/log/gitops-sync.log
```

**Resolution:**
```bash
# List available backups
ls -lh /etc/pihole/pihole.toml.backup-*

# Restore from most recent backup
sudo cp /etc/pihole/pihole.toml.backup-20251209-143000 \
         /etc/pihole/pihole.toml

# Restart Pi-hole
sudo systemctl restart pihole-FTL

# Verify DNS resolution
dig test.pandia.io @127.0.0.1
```

#### Scenario 4: Git Repository Issues

**Problem:** Cannot pull from GitHub

**Detection:**
```bash
# Check gitops-sync logs
sudo grep "git pull\|git clone" /var/log/gitops-sync.log | tail -5
```

**Resolution:**
```bash
# Check Git repository status
cd /opt/gitops/iac-catalog
git status
git remote -v

# Reset to remote state (if needed)
git fetch origin develop
git reset --hard origin/develop

# Verify credentials
ls -la ~/.git-credentials /opt/gitops/.git-credentials

# Manual sync to test
sudo systemctl start gitops-sync.service
```

## Dry Run Mode

Test changes without applying them:

```bash
# Test zone file changes locally
sudo python3 /opt/gitops/sync-dns-zones.py --dry-run \
  /opt/gitops/iac-catalog/environments/global/configurations/dns-zones \
  /etc/pihole/pihole.toml
```

**Dry Run Output:**
- Shows all validation steps
- Reports errors and warnings
- Displays summary statistics
- Does NOT modify pihole.toml
- Does NOT restart DNS services

## Health Monitoring

### Automated Health Check

```bash
# Run health check
/opt/gitops/check-dns-sync-health.sh
```

**Exit Codes:**
- `0` = Healthy
- `1` = Warnings (degraded)
- `2` = Critical (service down)

### Integration with Monitoring Systems

**Cron Job Example:**
```bash
# Add to crontab: Check every 10 minutes
*/10 * * * * /opt/gitops/check-dns-sync-health.sh || \
  echo "DNS sync health check failed" | \
  mail -s "Alert: DNS GitOps Issue" admin@example.com
```

**Nagios/Icinga Check:**
```bash
#!/bin/bash
/opt/gitops/check-dns-sync-health.sh
exit $?
```

## Validation Rules

### Hostname Validation

✅ **Valid:**
```bind
server1              3600    IN  A    192.168.1.10
web-server-01        3600    IN  A    192.168.1.20
*.apps               3600    IN  A    192.168.1.30
test.example.com.    3600    IN  A    192.168.1.40
```

❌ **Invalid:**
```bind
-invalid             3600    IN  A    192.168.1.10    ; Can't start with hyphen
server-              3600    IN  A    192.168.1.20    ; Can't end with hyphen
very_long_label      3600    IN  A    192.168.1.30    ; Underscore not allowed
```

### IP Address Validation

✅ **Valid:**
```bind
server1    3600    IN  A       192.168.1.10
server2    3600    IN  A       10.0.0.1
server3    3600    IN  AAAA    2001:db8::1
server4    3600    IN  AAAA    fe80::1
```

❌ **Invalid:**
```bind
server1    3600    IN  A       999.999.999.999
server2    3600    IN  A       192.168.1.256
server3    3600    IN  A       192.168.1
server4    3600    IN  AAAA    gggg::1
```

### CNAME Validation

✅ **Valid:**
```bind
; Target exists as A record
target     3600    IN  A       192.168.1.10
alias      3600    IN  CNAME   target

; Chain resolution (max 10 deep)
server     3600    IN  A       192.168.1.10
www        3600    IN  CNAME   server
web        3600    IN  CNAME   www
```

❌ **Invalid:**
```bind
; Target doesn't exist
orphan     3600    IN  CNAME   nonexistent

; Circular reference
a          3600    IN  CNAME   b
b          3600    IN  CNAME   a

; Chain too deep (>10)
c1         3600    IN  CNAME   c2
c2         3600    IN  CNAME   c3
; ... 11+ levels
```

## Best Practices

### 1. Test Before Production

```bash
# Always test changes with dry-run
sudo python3 /opt/gitops/sync-dns-zones.py --dry-run \
  /path/to/zones /etc/pihole/pihole.toml

# Review validation output
# Only push if no errors
```

### 2. Incremental Changes

```bash
# Make small, focused changes
# One change per commit
git add zone-file.zone
git commit -m "Add webserver DNS entry"
git push origin develop

# Wait for sync and verify
dig webserver.example.com @127.0.0.1
```

### 3. Monitor Sync Health

```bash
# Watch logs during changes
sudo tail -f /var/log/gitops-sync.log

# Run health check regularly
/opt/gitops/check-dns-sync-health.sh
```

### 4. Keep Backups

```bash
# Backups are automatic, but verify
ls -lh /etc/pihole/pihole.toml.backup-*

# Keep at least 10 recent backups
# Cleanup old backups periodically
```

### 5. Document Changes

```bash
# Use descriptive commit messages
git commit -m "Add production web servers (web01-05)"
git commit -m "Update load balancer IP for maintenance"
git commit -m "Remove decommissioned test environment"
```

## Troubleshooting Guide

| Symptom | Likely Cause | Resolution |
|---------|--------------|------------|
| "ABORTING: Cannot proceed with parsing errors" | Invalid zone file syntax | Fix syntax in Git, test with --dry-run |
| "Failed to resolve CNAME" | Missing target record | Add target A record or fix CNAME |
| "Duplicate hostname" | Same hostname in multiple places | Remove duplicate or rename one |
| "No write permission" | Permission issue | Check sudoers, file permissions |
| "Failed to create backup" | Disk space or permissions | Check disk space, permissions |
| Sync doesn't run | Timer not active | `sudo systemctl start gitops-sync.timer` |
| Changes not applied | Git pull failed | Check Git repo, credentials |

## Emergency Procedures

### Complete Rollback

```bash
# 1. Stop timer
sudo systemctl stop gitops-sync.timer

# 2. Restore last known good backup
sudo cp /etc/pihole/pihole.toml.backup-YYYYMMDD-HHMMSS \
        /etc/pihole/pihole.toml

# 3. Restart Pi-hole
sudo systemctl restart pihole-FTL

# 4. Verify DNS works
dig test.example.com @127.0.0.1

# 5. Fix issue in Git
cd ~/iac-catalog
# ... make fixes ...
git commit -m "Fix critical DNS issue"
git push origin develop

# 6. Re-enable timer
sudo systemctl start gitops-sync.timer
```

### Force Manual Sync

```bash
# Skip timer, run immediately
sudo systemctl start gitops-sync.service

# Watch logs
sudo journalctl -u gitops-sync.service -f
```

## Validation Summary

The DNS GitOps system provides multiple layers of protection:

1. ✅ **Pre-flight checks** - File system and permissions
2. ✅ **Parse-time validation** - Zone file syntax and records
3. ✅ **Conversion validation** - CNAME resolution, duplicates
4. ✅ **Pre-write validation** - TOML syntax check
5. ✅ **Automatic backup** - Before every change
6. ✅ **Post-write verification** - Content validation
7. ✅ **Auto-recovery** - Restore on failure
8. ✅ **Continuous retry** - Automatic healing
9. ✅ **Health monitoring** - Status checks
10. ✅ **Detailed logging** - Complete audit trail

---

**System Status**: Production Ready with Validation  
**Safety Level**: High - Multiple validation layers  
**Recovery**: Automatic with manual override available  
**Documentation**: Complete with troubleshooting guide
