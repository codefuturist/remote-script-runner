# mgmt (purpleidea) - Evaluation for DNS Management

## Date: 2025-12-09

## Project Overview

**Repository:** https://github.com/purpleidea/mgmt  
**Author:** James Shubin (Red Hat, former Puppet developer)  
**Language:** Go  
**License:** GNU GPL v3.0  
**Latest Release:** 1.0.1 (October 28, 2025)

### Statistics
- ⭐ Stars: 4,094
- 🔱 Forks: 338
- 📅 Created: September 2015 (9+ years)
- 🔄 Last Updated: December 9, 2025 (active)
- 🐛 Open Issues: 169
- 📦 Status: Not archived (active development)

## What is mgmt?

**Tagline:** "Next generation distributed, event-driven, parallel config management"

### Core Philosophy
mgmt represents a paradigm shift in configuration management:
- **Event-driven** instead of poll-based
- **Parallel execution** by default
- **Real-time convergence** (no 30-minute intervals)
- **Graph-based** dependency resolution
- **Reactive** to system changes

### How It's Different

#### Traditional Config Management (Puppet, Ansible, Salt)
```
┌──────────────────────────────────────────────┐
│ 1. Run every N minutes                       │
│ 2. Check all resources                       │
│ 3. Apply changes if needed                   │
│ 4. Sleep until next run                      │
└──────────────────────────────────────────────┘
```

#### mgmt Approach
```
┌──────────────────────────────────────────────┐
│ 1. Watch for events (file change, etc.)     │
│ 2. React immediately                         │
│ 3. Only touch affected resources            │
│ 4. Parallel execution of independent tasks  │
└──────────────────────────────────────────────┘
```

## Architecture

### Event-Driven Engine
```
Git Repository Change
    ↓ (inotify/webhook)
mgmt daemon (watches)
    ↓ (graph evaluation)
Parallel Resource Updates
    ↓ (only what changed)
System Converges Immediately
```

### Resource Graph
mgmt builds a dependency graph of resources and executes them in parallel where possible:

```
        [Git Repo]
            ↓
        [File 1] ──┐
            ↓      │
        [File 2]   │─→ [Exec: Parse]
            ↓      │
        [File 3] ──┘
            ↓
        [Service Restart]
```

## Key Features

### 1. Event-Driven (Real-time)
**Traditional:**
- Poll every N minutes
- 30-minute delay typical
- Wastes CPU checking unchanged resources

**mgmt:**
- Reacts to events (file changes, etc.)
- Convergence in seconds
- Only processes what changed

### 2. Parallel Execution
**Traditional:**
- Sequential execution
- Wait for each task
- Slow on complex configs

**mgmt:**
- Parallel by default
- Respects dependencies
- Maximum throughput

### 3. Distributed
**Traditional:**
- Master-agent architecture
- Centralized orchestration

**mgmt:**
- P2P coordination via etcd
- No single point of failure
- Horizontal scaling

### 4. Language: mcl
mgmt has its own declarative language (mgmt configuration language):

```mcl
# Example: DNS zone management
file "/etc/pihole/zones/pandia.io.zone" {
    state => "exists",
    content => template("zones/pandia.io.zone"),
    mode => "0644",
}

exec "parse-zones" {
    shell => "/usr/local/bin/parse-dns-zones",
    depend => File["/etc/pihole/zones/pandia.io.zone"],
}

svc "pihole-FTL" {
    state => "running",
    startup => "enabled",
    depend => Exec["parse-zones"],
}

# Watch for git changes
exec "git-pull" {
    shell => "cd /opt/dns-repo && git pull",
    pollint => 180, # 3 minutes as backup
}
```

## DNS Management with mgmt

### Potential Architecture

```
GitHub Repository (iac-catalog)
    ↓ (webhook or inotify)
mgmt daemon
    ↓
Resource Graph:
  1. Git pull (if changed)
  2. Zone file validation (parallel)
  3. Parse zones to Pi-hole format
  4. Update pihole.toml
  5. Restart Pi-hole FTL (if changed)
```

### Example mgmt Configuration

```mcl
# DNS GitOps with mgmt

# Git repository resource
git "/opt/mgmt/iac-catalog" {
    repo => "https://github.com/codefuturist/iac-catalog.git",
    branch => "develop",
    state => "latest",
}

# Validate zone files (parallel execution)
exec "validate-pandia-zone" {
    shell => "/usr/local/bin/validate-zone /opt/mgmt/iac-catalog/environments/global/configurations/dns-zones/pandia.io.zone",
    depend => Git["/opt/mgmt/iac-catalog"],
}

# Parse zones to hosts format
exec "parse-dns-zones" {
    shell => "/usr/local/bin/sync-dns-zones.py /opt/mgmt/iac-catalog/environments/global/configurations/dns-zones /etc/pihole/pihole.toml",
    depend => Exec["validate-pandia-zone"],
    watchcmd => "sha256sum /opt/mgmt/iac-catalog/environments/global/configurations/dns-zones/*.zone | sha256sum",
}

# Restart Pi-hole FTL if config changed
svc "pihole-FTL" {
    state => "running",
    startup => "enabled",
    depend => Exec["parse-dns-zones"],
}

# Watch for changes (event-driven)
file "/opt/mgmt/iac-catalog/environments/global/configurations/dns-zones" {
    state => "exists",
    recurse => true,
}
```

### Advantages for DNS Management

#### 1. Real-time Updates
✅ **Immediate convergence** (no 3-minute wait)
✅ **Event-driven** (react to git changes instantly)
✅ **Webhook support** (GitHub webhook → instant update)

#### 2. Parallel Validation
✅ **Validate all zone files simultaneously**
✅ **Faster processing** with multiple zones
✅ **Efficient resource usage**

#### 3. Smart Dependencies
✅ **Only restart if config actually changed**
✅ **Automatic rollback on validation failure**
✅ **Graph-based ordering**

#### 4. Distributed Ready
✅ **Multiple Pi-hole instances** coordinated
✅ **No master node required**
✅ **P2P synchronization**

## Comparison: Custom vs SaltStack vs mgmt

| Feature | Custom GitOps | SaltStack | mgmt |
|---------|---------------|-----------|------|
| **Maturity** | ✅ Proven (custom) | ✅ Mature (2011) | ⚠️ Newer (2015, v1.0 2025) |
| **Installation** | ✅ Simple | ⚠️ Complex | ⚠️ Requires Go |
| **Learning Curve** | ✅ Low | ⚠️ Medium-High | ⚠️ High (new paradigm) |
| **Event-Driven** | ❌ Poll (3 min) | ⚠️ Optional | ✅ Core feature |
| **Real-time** | ❌ No | ⚠️ With reactors | ✅ Yes |
| **Parallel Execution** | ❌ Sequential | ✅ Yes | ✅ By default |
| **Multi-Host** | ❌ No | ✅ Yes | ✅ Yes (P2P) |
| **Dependencies** | ✅ Minimal | ❌ Many | ⚠️ Go runtime |
| **Resource Usage** | ✅ ~50MB | ❌ ~600MB | ⚠️ ~100-200MB |
| **Community** | ❌ None | ✅ Large | ⚠️ Growing (4k stars) |
| **Production Ready** | ✅ Yes | ✅ Yes | ⚠️ v1.0 (recent) |
| **Documentation** | ✅ Custom | ✅ Extensive | ⚠️ Limited |
| **For Single Host** | ✅ Perfect | ❌ Overkill | ❌ Overkill |

## Pros and Cons for DNS Use Case

### Pros ✅

#### Innovation
- ✅ Modern architecture (event-driven)
- ✅ Real-time convergence (immediate updates)
- ✅ Parallel execution (faster with multiple zones)
- ✅ Written in Go (single binary, cross-platform)

#### Features
- ✅ Event-driven (no polling waste)
- ✅ P2P coordination (no master needed)
- ✅ Smart dependencies (graph-based)
- ✅ Webhook support (GitHub integration)

#### Performance
- ✅ Instant convergence (vs 3-minute delay)
- ✅ Parallel validation (multiple zones simultaneously)
- ✅ Lower overhead than SaltStack

### Cons ❌

#### Maturity
- ❌ v1.0 just released (October 2025)
- ❌ Limited production deployments
- ❌ 169 open issues
- ❌ Smaller community than Ansible/Salt/Puppet

#### Adoption
- ❌ Not widely used in production
- ❌ Limited third-party modules
- ❌ Few real-world examples
- ❌ Smaller ecosystem

#### Learning Curve
- ❌ New paradigm (event-driven)
- ❌ Custom language (mcl)
- ❌ Different mental model
- ❌ Limited documentation/tutorials

#### Complexity for Use Case
- ❌ Overkill for single Pi-hole host
- ❌ DNS-only doesn't need distributed features
- ❌ Current solution already works
- ❌ No clear benefit for this specific need

## Technical Evaluation

### Installation
```bash
# mgmt installation (Go required)
wget https://github.com/purpleidea/mgmt/releases/download/1.0.1/mgmt-1.0.1-linux-amd64.tar.gz
tar xzf mgmt-1.0.1-linux-amd64.tar.gz
sudo cp mgmt /usr/local/bin/
```

### Resource Usage
- **Binary Size:** ~40MB
- **Runtime Memory:** 100-200MB (lightweight for Go)
- **CPU:** Event-driven (minimal when idle)
- **Disk:** ~100MB (binary + cache)

### Complexity
- **Configuration:** mcl language (new to learn)
- **Architecture:** Distributed concepts (etcd, graphs)
- **Debugging:** Graph execution tracing
- **Maintenance:** New tool, fewer resources

## Risk Assessment

### High Risk ⚠️
1. **Bleeding Edge:** v1.0 just released (2 months ago)
2. **Limited Production Use:** Few known deployments
3. **Learning Curve:** New paradigm and language
4. **Community:** Smaller than alternatives
5. **Debugging:** Less stack overflow answers

### Medium Risk ⚠️
1. **Documentation:** Improving but limited
2. **Ecosystem:** Few third-party resources
3. **Long-term Support:** Uncertain (single maintainer?)

### Low Risk ✅
1. **Active Development:** Regular commits
2. **Open Source:** GPL v3, can fork if needed
3. **Go Language:** Reliable, cross-platform

## Recommendation for Your Use Case

### Current Situation
- Single Pi-hole host (pi-nvme-1)
- DNS management only
- Working custom solution (3-phase validation)
- 3-minute sync interval (acceptable)
- Production-ready and stable

### Should You Use mgmt?

**NO ❌**

### Reasons:

#### 1. Overkill for Single Host
- Event-driven benefits minimal for 3-minute tolerance
- Parallel execution irrelevant (one zone file)
- Distributed coordination not needed

#### 2. Adds Complexity
- New language to learn (mcl)
- New paradigm (event-driven config management)
- Bleeding edge (v1.0 just released)
- Limited community support

#### 3. No Clear Benefit
- Current solution: Works perfectly
- mgmt advantage: Seconds vs 3 minutes (not critical for DNS)
- Risk: High (new tool) vs Reward: Low (marginal improvement)

#### 4. Production Readiness
- Current solution: Battle-tested
- mgmt: v1.0 (October 2025) - too new
- Limited production deployments
- Uncertain stability

## When Would mgmt Make Sense?

### Use mgmt When:
✅ **Managing 10+ distributed hosts**
- P2P coordination valuable
- No central master needed
- Horizontal scaling important

✅ **Real-time convergence critical**
- Seconds matter (not minutes)
- Immediate response to changes required
- High-frequency updates needed

✅ **Complex dependency graphs**
- Many interconnected resources
- Parallel execution important
- Graph optimization beneficial

✅ **Distributed infrastructure**
- Multi-region deployment
- No single point of failure needed
- Peer-to-peer coordination required

✅ **Greenfield projects**
- No existing config management
- Team willing to learn new paradigm
- Time to experiment and validate

### DON'T Use mgmt When:
❌ **Single or few hosts** (your case)
❌ **Working solution exists** (your case)
❌ **Risk-averse environment**
❌ **Small team with limited time**
❌ **Need proven, mature tooling**
❌ **Minimal improvement vs high learning curve** (your case)

## Alternative Recommendation

### Best Options for Your Use Case (Ranked):

#### 1. ✅ Keep Custom DNS GitOps (BEST)
- **Status:** Production-ready
- **Complexity:** Low
- **Maintenance:** Minimal
- **Risk:** None
- **Benefit:** Perfect fit

#### 2. ⚠️ SaltStack (If Scaling)
- **When:** 3+ Pi-hole hosts
- **Benefit:** Mature, proven
- **Risk:** Medium (setup complexity)
- **Community:** Large

#### 3. ⚠️ Ansible (If Need Orchestration)
- **When:** Broader config management needed
- **Benefit:** Wide adoption, agentless
- **Risk:** Low (mature)
- **Learning curve:** Low

#### 4. ❌ mgmt (Future Consideration)
- **When:** 10+ hosts + real-time critical + greenfield
- **Benefit:** Modern, innovative
- **Risk:** High (bleeding edge)
- **Timeline:** Revisit in 2-3 years (after maturity)

## Interesting Features to Watch

### mgmt Has Innovative Concepts:
1. **Event-driven paradigm** (industry-leading)
2. **Parallel execution by default** (smart)
3. **Graph-based dependencies** (elegant)
4. **P2P coordination** (no SPOF)
5. **Written in Go** (portable, performant)

### But Needs Time to Mature:
- More production deployments
- Larger community
- More documentation
- Proven stability
- Ecosystem growth

## Conclusion

### For Your DNS Management on pi-nvme-1:

**Recommendation: Keep Custom DNS GitOps Solution** ✅

### Reasons (Priority Order):

1. ✅ **Working Solution Exists**
   - Production-ready
   - Well-tested
   - Documented
   - Zero issues

2. ✅ **mgmt is Overkill**
   - Single host (no distributed benefit)
   - DNS-only (no complex orchestration)
   - 3-minute tolerance (real-time not critical)

3. ⚠️ **mgmt is Too New**
   - v1.0 released 2 months ago
   - Limited production use
   - Small community
   - Uncertain stability

4. ❌ **Risk vs Reward**
   - Learning curve: High
   - Implementation time: High
   - Benefit gained: Marginal (seconds faster)
   - Risk introduced: High (bleeding edge)

### mgmt Future Watch 👀

**Revisit mgmt in 2027-2028 when:**
- v2.0+ released
- More production deployments
- Larger community
- Proven stability
- Scaling to 10+ hosts
- Real-time convergence becomes critical

### Current Status

| Tool | Status | Recommendation |
|------|--------|----------------|
| **Custom DNS GitOps** | ✅ ACTIVE | KEEP ✅ |
| **SaltStack** | ❌ Evaluated | REJECT (for now) |
| **mgmt** | 👀 Evaluated | WATCH (future) |

---

## Engineering Principle

> "Don't use bleeding edge technology for production infrastructure unless you have a compelling reason and resources to handle the risk."

**Your situation:**
- ❌ No compelling reason (working solution)
- ❌ No critical need for real-time (3 min OK)
- ❌ No resources for bleeding edge risk
- ✅ Perfect existing solution

**Decision: Keep it simple. Keep it working. ✅**

---

## Documentation

**File:** `~/DNS-MGMT-EVALUATION.md`  
**Size:** ~12KB  
**Status:** ✅ Complete

**Related Files:**
1. `~/DNS-SALTSTACK-EVALUATION.md` (16KB)
2. `~/DNS-SALTSTACK-IMPLEMENTATION-REPORT.md` (6KB)
3. `~/dns-gitops-backup/dns-gitops-backup-20251209-170517.tar.gz` (6.8MB)

**Total Evaluation Effort:**
- SaltStack: 2 hours
- mgmt: 30 minutes
- Value: Confirmed custom solution is optimal

---

*"The best tool is the one that solves your problem simply, reliably, and maintainably. Not the newest, not the fanciest, but the right one for the job."*
