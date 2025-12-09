# DNS GitOps Validation Workflow

## Overview

The DNS sync system uses a **3-phase validation workflow** that ensures **NO changes are applied** to the destination configuration unless **ALL zone files are completely valid**.

## Validation Philosophy

**🛡️ SAFETY FIRST: Validate Everything Before Changing Anything**

The system follows these principles:
1. **Pre-validate ALL zone files** before making ANY changes
2. **Only proceed if ALL zones pass validation**
3. **Cache validated configuration** for audit/rollback
4. **Never touch destination** until validation is 100% complete
5. **Auto-retry on next cycle** if validation fails

## 3-Phase Workflow

### Phase 1: Pre-Validation (Read-Only)

**Objective:** Validate ALL zone files without modifying anything

```
┌─────────────────────────────────────────────────────────┐
│ PHASE 1: PRE-VALIDATION - NO CHANGES WILL BE MADE      │
├─────────────────────────────────────────────────────────┤
│ 1. Find all *.zone files                                │
│ 2. Parse each zone file                                 │
│ 3. Validate DNS records:                                │
│    • Hostname format (RFC 1035)                         │
│    • IP address format (IPv4/IPv6)                      │
│    • TTL ranges                                          │
│    • Record structure                                    │
│ 4. Track valid vs invalid zones                         │
│                                                          │
│ Decision Point:                                          │
│ • ALL zones valid? → Proceed to Phase 2                │
│ • ANY zone invalid? → ABORT (no changes made)          │
└─────────────────────────────────────────────────────────┘
```

**Outputs:**
- List of valid zones
- List of invalid zones (if any)
- Detailed error messages

**Action if Invalid:**
```
✗ VALIDATION FAILED - ABORTING
  Invalid zones: invalid.zone
  Error: Line 4: Invalid IP address for A: 999.999.999.999
  
  NO CHANGES APPLIED - Destination config untouched
  Fix zone file errors and retry
```

### Phase 2: Conversion & Final Validation

**Objective:** Convert and validate CNAME resolution

```
┌─────────────────────────────────────────────────────────┐
│ PHASE 2: CONVERSION & FINAL VALIDATION                 │
├─────────────────────────────────────────────────────────┤
│ 1. Convert records to Pi-hole format                    │
│ 2. Resolve all CNAME chains                             │
│ 3. Detect circular CNAMEs                               │
│ 4. Check for orphaned CNAMEs                            │
│ 5. Detect duplicate hostnames                           │
│ 6. Generate final hosts list                            │
│ 7. Cache validated configuration                        │
│                                                          │
│ Decision Point:                                          │
│ • All CNAMEs resolved? → Proceed to Phase 3            │
│ • Unresolved CNAMEs? → ABORT (no changes made)         │
└─────────────────────────────────────────────────────────┘
```

**Outputs:**
- Converted hosts entries
- CNAME resolution results
- Duplicate warnings
- Cached validated configuration

**Cache Location:** `/var/cache/gitops-dns/validated_hosts.cache`

**Action if Invalid:**
```
✗ CONVERSION VALIDATION FAILED - ABORTING
  Failed to resolve CNAME 'orphan.invalid.test' -> 'nonexistent.invalid.test'
  
  NO CHANGES APPLIED - Destination config untouched
  Fix CNAME resolution errors and retry
```

### Phase 3: Application

**Objective:** Apply validated configuration to Pi-hole

```
┌─────────────────────────────────────────────────────────┐
│ PHASE 3: APPLICATION - Applying validated config       │
├─────────────────────────────────────────────────────────┤
│ ⚠️  All validations passed - NOW modifying destination  │
│                                                          │
│ 1. Create timestamped backup                            │
│ 2. Update pihole.toml with validated hosts              │
│ 3. Verify written content                               │
│ 4. Restart pihole-FTL                                   │
│ 5. Update success cache                                 │
│                                                          │
│ If any step fails:                                      │
│ • Restore from backup                                   │
│ • Log failure                                           │
│ • Exit with error                                       │
└─────────────────────────────────────────────────────────┘
```

**Outputs:**
- Backup file (timestamped)
- Updated pihole.toml
- Success cache
- Restarted DNS service

**Success:**
```
✓ DNS SYNC SUCCESSFUL
  Validated configuration applied successfully
```

**Failure (with auto-restore):**
```
✗ APPLICATION FAILED
  Verified content mismatch after write
  Successfully restored from backup
```

## Cache System

### Cache Directory

```
/var/cache/gitops-dns/
├── validated_hosts.cache       # Last successfully validated config
├── last_successful_sync        # Timestamp and stats
├── last_validation_failed      # Last validation failure (if any)
└── last_conversion_failed      # Last conversion failure (if any)
```

### Cache Files

#### `validated_hosts.cache`

Contains the last successfully validated configuration before application:

```
# Generated: 2025-12-09T16:12:31.862057
# Valid zones: pandia.io.zone, test.local.zone
# Total records: 87
# Hosts entries: 86
# --- VALIDATED CONFIGURATION ---
192.168.1.10 server1.example.com
192.168.1.20 server2.example.com
...
```

**Purpose:**
- Audit trail
- Rollback reference
- Debug validation issues

#### `last_successful_sync`

Tracks last successful application:

```
2025-12-09T16:12:31.865771
Zones: pandia.io.zone, test.local.zone
Records: 87
Hosts: 86
```

**Purpose:**
- Health monitoring
- Success tracking
- Age calculation

#### `last_validation_failed` / `last_conversion_failed`

Records validation/conversion failures:

```
2025-12-09T16:05:30.759647
Conversion errors: 1
  Failed to resolve CNAME 'orphan.invalid.test' -> 'nonexistent.invalid.test'
```

**Purpose:**
- Persistent error tracking
- Troubleshooting
- Alert integration

## Validation Rules

### Zone File Must Pass

✅ **Valid zone file:**
- Proper BIND syntax
- Valid $ORIGIN directive
- SOA record (informational)
- All hostnames RFC 1035 compliant
- All IP addresses valid format
- TTL within range (0-2147483647)

❌ **Invalid zone file (causes ABORT):**
- Syntax errors
- Invalid hostname format
- Invalid IP addresses
- Malformed records

### CNAME Resolution Must Succeed

✅ **Valid CNAME:**
- Target exists as A/AAAA record
- Chain resolves within 10 levels
- No circular references

❌ **Invalid CNAME (causes ABORT):**
- Target does not exist
- Circular reference (A→B→A)
- Chain too deep (>10 levels)

### Warnings (Non-Blocking)

⚠️ **Warnings allow sync to proceed:**
- Duplicate hostnames (last wins)
- Skipped invalid records
- DNS server optimization suggestions

## Example Workflows

### Scenario 1: All Valid → Success

```
User: git push (update zone file)
  ↓
Phase 1: Pre-Validation
  ✓ pandia.io.zone: Valid (81 records)
  ✓ test.local.zone: Valid (6 records)
  → Proceed to Phase 2
  ↓
Phase 2: Conversion
  ✓ All CNAMEs resolved
  ⚠️ 1 duplicate hostname (warning only)
  → Proceed to Phase 3
  ↓
Phase 3: Application
  ✓ Backup created
  ✓ pihole.toml updated
  ✓ Content verified
  ✓ DNS restarted
  → SUCCESS

Result: DNS entries live in Pi-hole
```

### Scenario 2: Invalid Zone → Abort

```
User: git push (invalid IP in zone)
  ↓
Phase 1: Pre-Validation
  ✓ pandia.io.zone: Valid
  ✗ invalid.zone: FAILED (invalid IP)
  → ABORT - NO CHANGES MADE
  ↓
Cache: last_validation_failed

Result: Destination config UNTOUCHED
        Fix errors and try again
```

### Scenario 3: Orphaned CNAME → Abort

```
User: git push (CNAME without target)
  ↓
Phase 1: Pre-Validation
  ✓ pandia.io.zone: Valid
  ✓ test.zone: Valid (but has orphaned CNAME)
  → Proceed to Phase 2
  ↓
Phase 2: Conversion
  ✗ CNAME 'alias' → 'nonexistent' FAILED
  → ABORT - NO CHANGES MADE
  ↓
Cache: last_conversion_failed

Result: Destination config UNTOUCHED
        Fix CNAME or add target
```

### Scenario 4: Application Failure → Auto-Restore

```
User: git push (valid zones)
  ↓
Phase 1: Pre-Validation
  ✓ All zones valid
  → Proceed to Phase 2
  ↓
Phase 2: Conversion
  ✓ All validations passed
  → Proceed to Phase 3
  ↓
Phase 3: Application
  ✓ Backup created
  ✓ pihole.toml updated
  ✗ Verification FAILED (content mismatch)
  ✓ RESTORED from backup
  → FAILURE (but safe)

Result: Destination RESTORED to previous state
        Logged error for investigation
```

## Testing with Dry Run

**Before pushing changes to production:**

```bash
# Test locally with dry-run
sudo python3 /opt/gitops/sync-dns-zones.py --dry-run \
  /opt/gitops/iac-catalog/environments/global/configurations/dns-zones \
  /etc/pihole/pihole.toml
```

**Dry run behavior:**
- ✅ Runs Phase 1 (pre-validation)
- ✅ Runs Phase 2 (conversion validation)
- ❌ Skips Phase 3 (no changes applied)
- ✅ Shows what would happen
- ✅ Validates everything

**Example output:**
```
PHASE 1: PRE-VALIDATION - NO CHANGES WILL BE MADE
  ✓ All zones valid

PHASE 2: CONVERSION & FINAL VALIDATION
  ✓ All CNAMEs resolved
  ⚠️ 1 duplicate hostname

PHASE 3: APPLICATION
  ✓ DRY RUN SUCCESSFUL
  All validations passed - no changes applied
  Safe to apply in production
```

## Monitoring Cache Status

```bash
# Check last successful sync
cat /var/cache/gitops-dns/last_successful_sync

# Check for recent failures
ls -lh /var/cache/gitops-dns/*_failed 2>/dev/null

# View validated cache
head -20 /var/cache/gitops-dns/validated_hosts.cache

# Check cache age
stat -c %y /var/cache/gitops-dns/last_successful_sync
```

## Recovery from Validation Failures

### Persistent Validation Failure

If sync keeps failing:

```bash
# 1. Check what's failing
sudo tail -100 /var/log/gitops-sync.log | grep "ABORTING\|FAILED"

# 2. Check cache for details
cat /var/cache/gitops-dns/last_*_failed

# 3. Fix issues in Git
cd ~/iac-catalog
vi environments/global/configurations/dns-zones/problem.zone

# 4. Test locally before push
sudo python3 /opt/gitops/sync-dns-zones.py --dry-run ...

# 5. Push fix
git commit -m "Fix validation errors"
git push origin develop

# 6. Wait for next sync cycle (3 min) or trigger
sudo systemctl start gitops-sync.service
```

### Cache Corruption

If cache appears corrupted:

```bash
# Clear cache (safe - will regenerate)
sudo rm -f /var/cache/gitops-dns/*

# Force sync
sudo systemctl start gitops-sync.service

# Verify
cat /var/cache/gitops-dns/last_successful_sync
```

## Benefits of 3-Phase Validation

1. **Safety**: Destination never touched until validation complete
2. **Transparency**: Clear phases show exactly what's happening
3. **Audit Trail**: Cache provides complete history
4. **Fast Failure**: Stop early if problems detected
5. **Auto-Recovery**: System retries automatically
6. **Rollback Ready**: Cached config available for restore
7. **Testable**: Dry-run validates without applying
8. **Debuggable**: Detailed logs at each phase

## Summary

✅ **Phase 1**: Pre-validate all zones (abort if any invalid)
✅ **Phase 2**: Convert and validate CNAMEs (abort if unresolved)
✅ **Phase 3**: Apply only after complete validation
✅ **Cache**: Track validation state and history
✅ **Auto-Restore**: Recover from application failures
✅ **Continuous**: Retry on next cycle if failed

**Result: Destination config never modified unless 100% validated**

---

**Implementation Status**: ✅ Complete
**Safety Level**: Maximum
**Cache Location**: `/var/cache/gitops-dns/`
**Validation Layers**: 10
**Auto-Recovery**: Yes
