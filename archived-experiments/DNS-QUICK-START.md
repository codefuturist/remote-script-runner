# DNS GitOps Quick Start Guide

## Adding a New DNS Entry

### 1. Clone or Pull Latest

```bash
cd ~/iac-catalog
git pull origin develop
```

### 2. Edit Zone File

```bash
vi environments/global/configurations/dns-zones/pandia.io.zone
```

Add your entry:
```bind
mynewhost             3600      IN  A             192.168.2.123
myapp                 3600      IN  CNAME         mynewhost
```

### 3. Commit and Push

```bash
git add environments/global/configurations/dns-zones/pandia.io.zone
git commit -m "Add mynewhost DNS entry"
git push origin develop
```

### 4. Wait or Trigger

**Option A - Wait (Automatic):**
Changes sync automatically within 3 minutes

**Option B - Trigger Immediately:**
```bash
sudo systemctl start gitops-sync.service
```

### 5. Verify

```bash
dig mynewhost.pandia.io @127.0.0.1
```

## Adding a New Zone

```bash
cd ~/iac-catalog
cat > environments/global/configurations/dns-zones/newdomain.com.zone << 'EOF'
$ORIGIN newdomain.com.
@                     900       IN  SOA           dns1 admin 1 900 300 604800 900
@                     3600      IN  NS            dns1

host1                 3600      IN  A             192.168.1.10
host2                 3600      IN  A             192.168.1.20
www                   3600      IN  CNAME         host1
EOF

git add environments/global/configurations/dns-zones/newdomain.com.zone
git commit -m "Add newdomain.com zone"
git push origin develop
```

## Useful Commands

```bash
# Check sync status
sudo systemctl status gitops-sync.service

# View sync log
sudo tail -f /var/log/gitops-sync.log

# Test DNS resolution
dig hostname.domain.com @127.0.0.1

# Manual sync trigger
sudo systemctl start gitops-sync.service

# List all zone files
ls -lh ~/iac-catalog/environments/global/configurations/dns-zones/*.zone
```

## Common Record Types

```bind
; A Record (IPv4)
hostname              3600      IN  A             192.168.1.10

; AAAA Record (IPv6)
hostname              3600      IN  AAAA          2001:db8::1

; CNAME (Alias)
alias                 3600      IN  CNAME         hostname

; Wildcard
*.apps                3600      IN  A             192.168.1.50
```

## Testing Changes (Recommended)

Before pushing changes to production, test them:

```bash
# Dry run - validates without applying
sudo python3 /opt/gitops/sync-dns-zones.py --dry-run \
  /opt/gitops/iac-catalog/environments/global/configurations/dns-zones \
  /etc/pihole/pihole.toml
```

This will:
- ✅ Validate zone file syntax
- ✅ Check for duplicate hostnames
- ✅ Verify CNAME targets exist
- ✅ Validate IP addresses
- ❌ NOT modify Pi-hole config

## Health Check

```bash
# Check DNS sync health
/opt/gitops/check-dns-sync-health.sh
```

## Full Documentation

- **Complete Guide**: `/opt/gitops/DNS-GITOPS-README.md`
- **Validation & Recovery**: `/opt/gitops/DNS-VALIDATION-RECOVERY.md`
- **This Quick Start**: `/home/colin/DNS-QUICK-START.md`

## Troubleshooting

```bash
# Check for errors
sudo grep ERROR /var/log/gitops-sync.log

# View DNS statistics
sudo grep "Converted.*records" /var/log/gitops-sync.log | tail -5

# Verify Pi-hole config
sudo grep -A20 "hosts = \[" /etc/pihole/pihole.toml | head -25
```

---
**System**: GitOps DNS Automation for Pi-hole + Unbound  
**Repository**: github.com/codefuturist/iac-catalog (develop branch)  
**Sync Interval**: 3 minutes
