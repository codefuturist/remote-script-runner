# mgmt DNS Configuration Management - Evaluation

## Date
2025-12-09

## Overview
Evaluated using `mgmt` (by purpleidea) for DNS configuration management in Pi-hole + Unbound setup.

## What is mgmt?
- Next-generation configuration management tool
- Built on a reactive, event-driven engine with a domain-specific language (MCL)
- Designed for real-time, parallel execution with automatic dependency resolution
- Extremely concise code (~1,000 LOC for full provisioning tool vs 50k-235k for competitors)
- Single binary distribution

## Key Features
- **Event-driven architecture**: Reacts to changes in real-time
- **Parallel execution**: Resources run concurrently with proper dependency management
- **Type-safe DSL (MCL)**: Provides safety and expressiveness
- **Embedded deployments**: Can build custom standalone binaries with embedded MCL code
- **Real-time reactivity**: Can respond to time, load, errors, and other events programmatically

## DNS Use Case Fit

### Strengths
1. **Real-time synchronization**: Could watch Git repo and apply changes immediately
2. **Event-driven**: React to zone file changes, validation failures, service health
3. **Concise code**: DNS sync logic would be ~50-100 lines vs hundreds in shell/ansible
4. **Built-in resources**: File, exec, http resources available
5. **Programmatic logic**: Could provision based on conditions (time, load, etc.)

### Example MCL for DNS Sync (Conceptual)
```mcl
# Watch git repository for changes
vcs:git "/etc/pihole/dns-repo" {
    remote => "https://github.com/YourOrg/dns-zones.git",
    branch => "develop",
}

# Validate zone files before applying
exec "validate-zones" {
    cmd => "/usr/bin/named-checkzone",
    args => ["example.com", "/etc/pihole/dns-repo/zones/example.com.zone"],
    watchcmd => "/usr/bin/stat",
    watchargs => ["/etc/pihole/dns-repo/zones/"],
    
    Before => Exec["apply-zones"],
}

# Parse zones and update pihole.toml
exec "apply-zones" {
    cmd => "/usr/local/bin/zone-to-pihole.sh",
    watchcmd => "/usr/bin/stat",
    watchargs => ["/etc/pihole/dns-repo/zones/"],
    
    Before => Svc["pihole-FTL"],
}

# Restart Pi-hole if needed
svc "pihole-FTL" {
    state => "running",
    startup => "enabled",
}
```

## Critical Issues Encountered

### 1. **No ARM64 Pre-built Binaries**
- Only x86_64 binaries available in releases
- Our system is aarch64
- Would require building from source

### 2. **Building from Source Requirements**
- Requires Go toolchain
- Need to compile for ARM64
- Additional complexity for deployment

### 3. **Maturity Concerns**
- Version 1.0.1 but still relatively new in production environments
- Smaller community compared to Ansible, Salt, etc.
- Limited examples for DNS/Pi-hole use cases

### 4. **Learning Curve**
- New DSL (MCL) to learn
- Different paradigm from imperative tools
- Team training required

### 5. **Integration Complexity**
- Need to write custom resources or scripts for Pi-hole v6 TOML format
- Zone file parsing would need custom tooling
- Less "batteries included" than Ansible

## Comparison with Other Solutions

### vs Ansible Pull
| Feature | mgmt | Ansible Pull |
|---------|------|--------------|
| Real-time reactivity | ✅ Native | ❌ Cron-based |
| ARM64 support | ❌ Build from source | ✅ Pre-built |
| Community/maturity | ⚠️ Smaller | ✅ Large |
| Code complexity | ✅ Very concise | ⚠️ More verbose |
| Learning curve | ⚠️ New paradigm | ✅ Well-known |
| DNS examples | ❌ Limited | ✅ Many |

### vs Custom Systemd Service
| Feature | mgmt | Custom Service |
|---------|------|----------------|
| Complexity | ⚠️ Higher | ✅ Lower |
| Flexibility | ✅ Very high | ⚠️ Limited |
| Maintenance | ⚠️ New tool | ✅ Standard tools |
| Portability | ⚠️ mgmt-specific | ✅ Portable |

### vs SaltStack
| Feature | mgmt | SaltStack |
|---------|------|-----------|
| Event-driven | ✅ Core feature | ✅ Available |
| ARM64 support | ❌ Build required | ✅ Available |
| Agent overhead | ⚠️ New runtime | ⚠️ Python + Salt |
| Simplicity | ✅ Single binary | ❌ Complex install |

## Recommendation

### For Production: ❌ Not Recommended Currently
**Reasons:**
1. ARM64 build requirement adds deployment complexity
2. Smaller community means less DNS-specific examples
3. Would need to develop custom tooling anyway
4. Team would need training on MCL

### Future Consideration: ✅ Monitor for Future Use
**Reasons:**
1. Architecture is compelling for event-driven config management
2. Could be excellent for complex, reactive infrastructure
3. May provide ARM64 binaries in future releases
4. Perfect for environments needing real-time response to conditions

## Better Alternatives for Our Use Case

### 1. ✅ **Ansible Pull** (Current Choice)
- Well-understood tool
- ARM64 support out of the box
- Large community with DNS examples
- Cron/timer based is sufficient for DNS updates
- Already have Ansible infrastructure

### 2. ✅ **Custom Systemd Service + inotify**
- Simple, maintainable
- Uses only standard Linux tools
- Fast to implement
- Easy to debug
- No new dependencies

### 3. ⚠️ **SaltStack**
- Good event-driven capabilities
- More complex than needed
- Additional agent to manage

## Conclusion

While `mgmt` is an innovative and technically impressive tool with excellent architectural decisions, it's **not practical for our current DNS management needs** due to:

1. Lack of ARM64 binaries
2. Overkill for simple DNS zone synchronization
3. Small community/ecosystem for troubleshooting
4. Would still need custom scripts for zone file parsing

**Recommendation**: Stick with **Ansible Pull** solution already implemented. It's proven, well-supported, and sufficient for DNS zone synchronization needs.

## Code Preserved
- Ansible Pull implementation in: `/home/colin/ansible-infrastructure/`
- Custom service implementation backed up in various backup directories
- All evaluation documents preserved for future reference

## Future Use Cases for mgmt
Consider mgmt for:
- Complex multi-service orchestration needing real-time reaction
- Infrastructure that needs to respond to load/time/external events
- When building custom provisioning or deployment tools
- Environments where <1000 LOC tools are needed vs 50k+ LOC alternatives

## References
- mgmt Website: https://mgmtconfig.com/
- mgmt GitHub: https://github.com/purpleidea/mgmt/
- Provisioning Article: https://purpleidea.com/blog/2024/03/27/a-new-provisioning-tool-built-with-mgmt/
- Documentation: https://github.com/purpleidea/mgmt/tree/master/docs
