# DNS Management with SaltStack + GitFS

## Overview

Evaluation of replacing custom DNS GitOps solution with **SaltStack + GitFS** for managing Pi-hole v6 DNS configuration.

## Current Implementation (Custom)

### Architecture
```
GitHub Repository (iac-catalog)
    ↓ (git pull every 3 min)
DNS Sync Service (dns-sync.sh)
    ↓
Zone Parser (sync-dns-zones.py)
    ↓ (3-phase validation)
Pi-hole TOML (pihole.toml)
    ↓ (restart)
Pi-hole FTL Service
```

### Components
- Custom bash orchestration
- Python zone parser (800+ lines)
- 3-phase validation workflow
- Systemd service + timer
- Manual cache management
- Custom health checks

### Pros
- ✅ Lightweight (minimal dependencies)
- ✅ Direct BIND zone file support
- ✅ Comprehensive validation
- ✅ Simple to understand
- ✅ No agent required

### Cons
- ❌ Custom code to maintain
- ❌ Limited to DNS only
- ❌ No rollback built-in
- ❌ No orchestration across hosts
- ❌ No configuration management features

## SaltStack + GitFS Implementation

### Architecture
```
GitHub Repository (iac-catalog)
    ↓ (GitFS backend)
Salt Master (saltmaster.pandia.io)
    ↓ (event-driven or scheduled)
Salt Minion (each Pi-hole host)
    ↓ (salt states)
Pi-hole Configuration Management
    ↓
Pi-hole FTL Service
```

### Components

#### 1. Salt Master Setup
```yaml
# /etc/salt/master.d/gitfs.conf
fileserver_backend:
  - gitfs
  - roots

gitfs_remotes:
  - https://github.com/codefuturist/iac-catalog.git:
      - base: develop
      - root: salt/states
      - mountpoint: salt://

gitfs_update_interval: 180  # 3 minutes (same as current)

gitfs_provider: gitpython
gitfs_ssl_verify: True
gitfs_base: develop

# Cache GitFS data
gitfs_cachedir: /var/cache/salt/gitfs

# File ignore patterns
gitfs_file_ignore:
  - '\.git.*'
  - '\.md$'
```

#### 2. Salt State Structure
```
iac-catalog/
└── salt/
    └── states/
        └── dns/
            ├── init.sls              # Main orchestration
            ├── pihole/
            │   ├── init.sls          # Pi-hole specific
            │   ├── config.sls        # TOML management
            │   └── service.sls       # FTL service
            ├── zones/
            │   ├── parser.py         # Zone file parser (Jinja filter)
            │   └── validator.py      # Validation module
            └── files/
                └── zones/
                    └── pandia.io.zone
```

#### 3. Main DNS State (`dns/init.sls`)
```yaml
# Install dependencies
dns-dependencies:
  pkg.installed:
    - pkgs:
      - python3-pip
      - python3-dnspython

# Install custom zone parser module
dns-zone-parser:
  file.managed:
    - name: /usr/local/lib/salt/modules/dns_zones.py
    - source: salt://dns/zones/parser.py
    - makedirs: True
    - user: root
    - group: root
    - mode: 644

# Sync custom modules
dns-sync-modules:
  saltutil.sync_all:
    - refresh: True
    - onchanges:
      - file: dns-zone-parser

# Include Pi-hole configuration
include:
  - dns.pihole
```

#### 4. Pi-hole Configuration State (`dns/pihole/config.sls`)
```yaml
{% set zone_files = salt['cp.list_master_dirs']('dns/files/zones') %}
{% set parsed_zones = [] %}

# Parse and validate all zone files
{% for zone_file in salt['cp.list_master']('dns/files/zones/*.zone') %}
  {% set zone_data = salt['cp.get_file_str'](zone_file) %}
  {% set parsed = salt['dns_zones.parse_bind_zone'](zone_data) %}
  {% if parsed.valid %}
    {% do parsed_zones.append(parsed) %}
  {% else %}
    # VALIDATION FAILED - ABORT
    dns-validation-failed-{{ zone_file }}:
      test.fail_without_changes:
        - name: "Zone validation failed: {{ zone_file }}"
        - comment: "{{ parsed.errors }}"
  {% endif %}
{% endfor %}

# Only proceed if all zones are valid
{% if parsed_zones|length > 0 %}

# Generate hosts entries from validated zones
{% set hosts_entries = [] %}
{% for zone in parsed_zones %}
  {% for record in zone.records %}
    {% if record.type in ['A', 'AAAA'] %}
      {% do hosts_entries.append(record.ip + ' ' + record.hostname) %}
    {% endif %}
  {% endfor %}
{% endfor %}

# Backup current Pi-hole config
pihole-config-backup:
  file.copy:
    - name: /etc/pihole/pihole.toml.backup-{{ salt['cmd.run']('date +%Y%m%d-%H%M%S') }}
    - source: /etc/pihole/pihole.toml
    - preserve: True

# Update Pi-hole TOML with validated hosts
pihole-hosts-config:
  pihole_toml.hosts_managed:
    - hosts: {{ hosts_entries | tojson }}
    - require:
      - file: pihole-config-backup

# Restart Pi-hole FTL if config changed
pihole-ftl-service:
  service.running:
    - name: pihole-FTL
    - enable: True
    - watch:
      - pihole_toml: pihole-hosts-config

{% else %}

dns-no-valid-zones:
  test.fail_without_changes:
    - name: "No valid zone files found"
    - comment: "Check zone file syntax and validation"

{% endif %}
```

#### 5. Custom Execution Module (`dns_zones.py`)
```python
"""
Salt execution module for parsing BIND zone files
"""

import re
import ipaddress
from typing import Dict, List, Any

def parse_bind_zone(zone_content: str) -> Dict[str, Any]:
    """
    Parse BIND zone file and validate records
    
    Returns:
        dict: {
            'valid': bool,
            'records': list,
            'errors': list
        }
    """
    result = {
        'valid': True,
        'records': [],
        'errors': []
    }
    
    # Parse zone file (simplified - use dnspython in production)
    lines = zone_content.split('\n')
    current_origin = ''
    
    for line in lines:
        line = line.strip()
        if not line or line.startswith(';'):
            continue
            
        # Handle $ORIGIN
        if line.startswith('$ORIGIN'):
            current_origin = line.split()[1].rstrip('.')
            continue
        
        # Parse records
        parts = line.split()
        if len(parts) >= 4:
            hostname = parts[0]
            if hostname == '@':
                hostname = current_origin
            elif not hostname.endswith('.'):
                hostname = f"{hostname}.{current_origin}"
            
            record_type = parts[3]
            
            if record_type in ['A', 'AAAA']:
                ip = parts[4]
                try:
                    ipaddress.ip_address(ip)
                    result['records'].append({
                        'hostname': hostname,
                        'type': record_type,
                        'ip': ip
                    })
                except ValueError:
                    result['errors'].append(f"Invalid IP: {ip}")
                    result['valid'] = False
            
            elif record_type == 'CNAME':
                target = parts[4].rstrip('.')
                result['records'].append({
                    'hostname': hostname,
                    'type': record_type,
                    'target': target
                })
    
    return result
```

#### 6. Custom State Module (`pihole_toml.py`)
```python
"""
Salt state module for managing Pi-hole TOML configuration
"""

import toml
from pathlib import Path

def hosts_managed(name, hosts):
    """
    Manage hosts section in pihole.toml
    
    Args:
        name: State name
        hosts: List of "IP hostname" strings
    """
    ret = {
        'name': name,
        'changes': {},
        'result': False,
        'comment': ''
    }
    
    toml_path = Path('/etc/pihole/pihole.toml')
    
    try:
        # Read current config
        config = toml.load(toml_path)
        
        # Get current hosts
        current_hosts = config.get('hosts', [])
        
        # Compare
        if set(current_hosts) == set(hosts):
            ret['result'] = True
            ret['comment'] = 'Hosts already configured'
            return ret
        
        # Update hosts
        config['hosts'] = hosts
        
        # Test mode
        if __opts__['test']:
            ret['result'] = None
            ret['comment'] = 'Would update hosts configuration'
            ret['changes'] = {
                'old': len(current_hosts),
                'new': len(hosts)
            }
            return ret
        
        # Write config
        with open(toml_path, 'w') as f:
            toml.dump(config, f)
        
        ret['result'] = True
        ret['comment'] = 'Hosts configuration updated'
        ret['changes'] = {
            'old': len(current_hosts),
            'new': len(hosts)
        }
        
    except Exception as e:
        ret['result'] = False
        ret['comment'] = f"Failed to update config: {str(e)}"
    
    return ret
```

#### 7. Reactor for Auto-Sync (`/etc/salt/master.d/reactor.conf`)
```yaml
# React to GitFS updates
reactor:
  - 'salt/fileserver/gitfs/update':
    - /srv/reactor/dns_update.sls

# Schedule regular updates
schedule:
  dns-sync:
    function: state.apply
    args:
      - dns
    minutes: 3
    splay: 30
```

#### 8. Reactor State (`/srv/reactor/dns_update.sls`)
```yaml
# Apply DNS states when GitFS updates
dns-auto-update:
  local.state.apply:
    - tgt: 'role:pihole'
    - arg:
      - dns
    - kwarg:
        pillar:
          auto_update: True
```

### SaltStack Benefits

#### 1. Configuration Management
✅ **Built-in orchestration**
- State dependencies
- Requisites (require, watch, onchanges)
- Ordering guarantees

✅ **Idempotent operations**
- Only apply changes when needed
- Test mode (dry-run) built-in
- State verification

✅ **Templating with Jinja**
- Dynamic configuration
- Conditional logic
- Data transformation

#### 2. GitFS Integration
✅ **Automatic sync from Git**
- No custom git operations
- Built-in caching
- Multiple branch support

✅ **File serving**
- Efficient file distribution
- Checksums and verification
- Template rendering

✅ **Version control**
- Git history tracking
- Easy rollback
- Branch strategies

#### 3. Multi-Host Management
✅ **Targeting**
- Manage multiple Pi-hole instances
- Grain-based targeting
- Role-based deployment

✅ **Orchestration**
- Coordinate updates across hosts
- Sequential or parallel execution
- Failure handling

✅ **Event system**
- Real-time updates
- Event-driven automation
- Custom reactors

#### 4. Extensibility
✅ **Custom modules**
- Execution modules (functions)
- State modules (states)
- Runners (master-side)

✅ **Returners**
- Store results in database
- Send to monitoring systems
- Custom logging

✅ **Beacons**
- Watch for system changes
- Trigger reactions
- Health monitoring

#### 5. Testing & Validation
✅ **Test mode**
```bash
salt 'pihole-1' state.apply dns test=True
```

✅ **State validation**
```bash
salt 'pihole-1' state.show_sls dns
```

✅ **Dry run**
```bash
salt 'pihole-1' state.apply dns test=True pillar='{"debug": true}'
```

#### 6. Rollback Capabilities
✅ **State reversals**
```yaml
# Rollback to previous version
dns-rollback:
  file.managed:
    - name: /etc/pihole/pihole.toml
    - source: /etc/pihole/pihole.toml.backup-previous
```

✅ **Git history**
```bash
# Revert GitFS to previous commit
salt-run fileserver.update backend=gitfs branch=develop commit=abc123
```

### Best Practices Implementation

#### 1. State Organization
```
salt/states/
├── top.sls                    # State tree
├── dns/
│   ├── init.sls              # Main entry point
│   ├── map.jinja             # OS-specific mappings
│   ├── pihole/
│   │   ├── init.sls
│   │   ├── install.sls       # Installation
│   │   ├── config.sls        # Configuration
│   │   └── service.sls       # Service management
│   └── zones/
│       ├── validate.sls      # Validation states
│       └── apply.sls         # Application states
└── _modules/                  # Custom modules
    ├── dns_zones.py
    └── pihole_config.py
```

#### 2. Pillar for Secrets
```yaml
# pillar/dns.sls
dns:
  pihole:
    api_key: {{ salt['vault'].read_secret('secret/pihole/api_key') }}
    admin_password: {{ salt['vault'].read_secret('secret/pihole/password') }}
  
  zones:
    repository: https://github.com/codefuturist/iac-catalog.git
    branch: develop
    path: environments/global/configurations/dns-zones
```

#### 3. Grains for Targeting
```yaml
# /etc/salt/minion.d/grains.conf
grains:
  role: pihole
  environment: production
  dns_provider: pihole-v6
```

```bash
# Target by role
salt -G 'role:pihole' state.apply dns

# Target by environment
salt -G 'environment:production' state.apply dns
```

#### 4. Testing Strategy
```yaml
# tests/integration/dns/init.sls
dns-test-resolution:
  cmd.run:
    - name: dig +short pve3.pandia.io @127.0.0.1
    - require:
      - state: dns

dns-test-service:
  service.running:
    - name: pihole-FTL
```

#### 5. Monitoring Integration
```yaml
# Enable returner for monitoring
/etc/salt/minion.d/returner.conf:
  file.managed:
    - contents: |
        return: influxdb
        influxdb.host: influxdb.pandia.io
        influxdb.db: salt_metrics
```

### Comparison Matrix

| Feature | Custom GitOps | SaltStack + GitFS |
|---------|---------------|-------------------|
| **Setup Complexity** | Low | Medium |
| **Learning Curve** | Low | Medium-High |
| **Dependencies** | Minimal | Salt Master + Minion |
| **Multi-Host Support** | No | Yes |
| **Rollback** | Manual | Built-in |
| **Validation** | Custom (comprehensive) | Extensible |
| **Configuration Management** | DNS only | Everything |
| **Event-Driven** | No | Yes |
| **Dry Run** | Custom | Built-in |
| **Secrets Management** | Manual | Integrated (Vault) |
| **Monitoring** | Custom | Built-in returners |
| **Community Support** | None | Large |
| **Maintenance Burden** | High (custom code) | Low (standard tool) |

### Resource Requirements

#### Current Implementation
- **Disk**: ~100MB (scripts + repo)
- **Memory**: ~50MB (during sync)
- **CPU**: Minimal
- **Network**: Git pull (small)

#### SaltStack Implementation
- **Disk**: ~500MB (Salt + GitFS cache)
- **Memory**: 
  - Master: ~200-500MB
  - Minion: ~50-100MB
- **CPU**: Minimal (event-driven)
- **Network**: 
  - Initial: Larger (Salt packages)
  - Ongoing: Similar (GitFS sync)

### Migration Path

#### Phase 1: Parallel Testing
1. Keep current system running
2. Install Salt Master
3. Install Salt Minion on test Pi-hole
4. Implement DNS states
5. Test in parallel for 2 weeks

#### Phase 2: Production Validation
1. Apply to staging Pi-hole
2. Validate all DNS records
3. Performance testing
4. Failover testing

#### Phase 3: Production Rollout
1. Apply to production Pi-hole instances
2. Monitor for 1 week
3. Disable custom service
4. Remove custom scripts

#### Phase 4: Cleanup
1. Archive custom implementation
2. Document SaltStack approach
3. Train team on Salt

### Recommendation

#### Stay with Custom Solution If:
- ✅ Only managing DNS
- ✅ Single or few Pi-hole instances
- ✅ No plans for broader automation
- ✅ Team unfamiliar with SaltStack
- ✅ Minimal resource overhead critical

#### Migrate to SaltStack If:
- ✅ Managing multiple Pi-hole instances
- ✅ Need broader configuration management
- ✅ Want event-driven automation
- ✅ Team knows or willing to learn Salt
- ✅ Need enterprise features (rollback, monitoring)
- ✅ Want to standardize on single tool

### Hybrid Approach

**Best of Both Worlds:**

1. **Keep custom solution for DNS-only hosts**
2. **Use SaltStack for infrastructure hosts** that need:
   - DNS management
   - Docker configuration
   - System configuration
   - Multi-service orchestration

3. **Share zone files** between both systems:
   - Same Git repository
   - Same zone file format
   - Different consumption methods

### Conclusion

**For Your Use Case (Single Pi-hole, DNS-only):**

**Recommendation: Stick with custom solution**

**Reasons:**
1. ✅ Already working and validated
2. ✅ Minimal dependencies
3. ✅ Comprehensive validation
4. ✅ Lightweight resource usage
5. ✅ Well-documented
6. ✅ No learning curve

**Consider SaltStack when:**
- Scaling to multiple Pi-hole instances
- Need configuration management beyond DNS
- Want to standardize on enterprise tooling
- Team grows and needs collaboration

**Current Status:**
- ✅ Custom solution: Production-ready, lightweight, effective
- ℹ️ SaltStack: More powerful, but overkill for current needs
- 💡 Future: Revisit when scaling or adding complexity

---

**Backup Location:** `~/dns-gitops-backup/dns-gitops-backup-20251209-170517.tar.gz`
**Backup Size:** 6.8MB
**Backup Contains:** Scripts, configs, logs, systemd units
