# CFEngine - Evaluation for DNS Management

## Date: 2025-12-09

## Project Overview

**Website:** https://cfengine.com/  
**Repository:** https://github.com/cfengine/core  
**Organization:** Northern.tech (formerly CFEngine AS)  
**Author:** Mark Burgess (Promise Theory pioneer)  
**Language:** C  
**License:** GPLv3 (Community), Commercial (Enterprise)  
**Latest Version:** 3.6.x (active development)

### Statistics
- ⭐ Stars: 514
- 🔱 Forks: 196
- 📅 Created: 1993 (32 years old!)
- 📅 GitHub Repo: 2012
- 🔄 Last Commit: December 8, 2025 (yesterday!)
- 🐛 Open Issues: 9
- 📦 Status: Active (commits every few days)
- 🏢 Company: Northern.tech (Oslo, Norway)

## What is CFEngine?

**Tagline:** "The first configuration management tool - still leading in autonomy"

### Historical Significance

CFEngine is the **grandfather of all configuration management tools**:

```
1993: CFEngine created by Mark Burgess
  ↓
2005: Puppet (inspired by CFEngine)
  ↓
2008: Chef (Ruby-based)
  ↓
2011: SaltStack (Python-based)
  ↓
2012: Ansible (agentless)
  ↓
2015: mgmt (event-driven)
```

### Core Philosophy: Promise Theory

Mark Burgess developed **Promise Theory** - a mathematical model for autonomous systems:

**Traditional Approach (Imperative):**
```
"Do this, then do that, then do this other thing"
- System told what to do
- Central control
- Sequential execution
```

**CFEngine Approach (Promise-based):**
```
"I promise this file exists"
"I promise this service is running"
"I promise this permission is set"
- System declares desired state
- Autonomous convergence
- Self-healing
```

## Architecture

### Autonomous Agent Model

```
┌─────────────────────────────────────────────┐
│ CFEngine Agent (cf-agent)                   │
│                                             │
│ 1. Reads policy files (promises)           │
│ 2. Evaluates current state                 │
│ 3. Converges autonomously                  │
│ 4. Reports results (optional)              │
│                                             │
│ Runs every 5 minutes by default            │
│ No master required (can work standalone)   │
└─────────────────────────────────────────────┘
```

### Three Editions

#### 1. CFEngine Community (Open Source)
- Free and open source (GPLv3)
- Core functionality
- Standalone operation
- Manual policy distribution
- Command-line only

#### 2. CFEngine Enterprise
- Commercial license
- Web-based UI (Mission Portal)
- Centralized policy hub
- Reporting and compliance
- Role-based access control
- Support and training

#### 3. CFEngine Nova (Enterprise+)
- Advanced features
- Enhanced reporting
- Better scalability
- Premium support

### Components

```
cf-agent      → Main execution agent (runs policies)
cf-serverd    → Policy server (distributes policies)
cf-execd      → Scheduler (runs cf-agent periodically)
cf-monitord   → System monitoring
cf-promises   → Policy validation
cf-runagent   → Remote execution trigger
cf-key        → Key management (authentication)
```

## Key Features

### 1. Autonomous Operation
**Traditional (Master-Agent):**
- Master tells agents what to do
- Agents wait for instructions
- Central point of failure

**CFEngine:**
- Agents work independently
- Pull policies on schedule
- Continue working if hub is down
- Self-healing

### 2. Lightweight & Fast
- **Written in C** (not Python/Ruby)
- **Low memory footprint** (~10MB)
- **Fast execution** (compiled, not interpreted)
- **Minimal dependencies**
- **Scales to 100,000+ nodes**

### 3. Convergence Model
- **Idempotent** operations
- **Self-healing** by default
- **Convergence** over time
- **Non-disruptive** changes

### 4. Promise Language
CFEngine has its own declarative language based on Promise Theory:

```cfengine3
bundle agent dns_management
{
  files:
    # Promise: DNS zone files exist with correct content
    "/etc/pihole/zones/pandia.io.zone"
      copy_from => secure_cp("/opt/dns-repo/zones/pandia.io.zone","localhost"),
      perms => mog("644","root","root"),
      classes => if_repaired("zone_updated");

  commands:
    # Promise: Zone parser runs if zones updated
    zone_updated::
      "/usr/local/bin/sync-dns-zones.py"
        args => "/opt/dns-repo/zones /etc/pihole/pihole.toml",
        classes => if_repaired("config_updated");

  services:
    # Promise: Pi-hole service is running
    "pihole-FTL"
      service_policy => "restart",
      if => "config_updated";

  # Promise: Git repo is up to date
  commands:
    "/usr/bin/git"
      args => "-C /opt/dns-repo pull origin develop",
      contain => in_shell,
      action => if_elapsed("180"); # Every 3 minutes
}
```

## DNS Management with CFEngine

### Potential Architecture

```
GitHub Repository (iac-catalog)
    ↓ (cf-agent pulls every 3 min)
CFEngine Agent (cf-agent)
    ↓
Policy Execution:
  1. Git pull (if 3+ min elapsed)
  2. Copy zone files
  3. Validate zones
  4. Parse to Pi-hole format
  5. Update pihole.toml
  6. Restart Pi-hole FTL (if changed)
    ↓
System Converges Autonomously
```

### Example CFEngine Policy

```cfengine3
body common control
{
  bundlesequence => { "dns_gitops" };
  inputs => { "lib/stdlib.cf" };
}

bundle agent dns_gitops
{
  vars:
    "repo_dir" string => "/opt/dns-repo";
    "zone_dir" string => "$(repo_dir)/environments/global/configurations/dns-zones";
    "pihole_config" string => "/etc/pihole/pihole.toml";

  methods:
    # Promise: Git repo exists and is current
    "git_repo" usebundle => git_sync("$(repo_dir)", "https://github.com/codefuturist/iac-catalog.git", "develop");

  files:
    # Promise: Zone files are present
    "$(zone_dir)/.*\.zone"
      copy_from => local_cp("$(repo_dir)/environments/global/configurations/dns-zones"),
      depth_search => recurse("1"),
      file_select => by_name(".*\.zone"),
      classes => if_repaired("zones_changed");

  commands:
    # Promise: Zones are validated (before applying)
    zones_changed::
      "/usr/local/bin/named-checkzone"
        args => "pandia.io $(zone_dir)/pandia.io.zone",
        classes => if_ok("zones_valid");

    # Promise: DNS config is generated from validated zones
    zones_valid::
      "/usr/local/bin/sync-dns-zones.py"
        args => "$(zone_dir) $(pihole_config)",
        classes => if_repaired("config_changed");

  services:
    # Promise: Pi-hole service is running and restarted if needed
    config_changed::
      "pihole-FTL"
        service_policy => "restart",
        service_method => systemd;
}

bundle agent git_sync(path, repo, branch)
{
  classes:
    "git_repo_exists" expression => fileexists("$(path)/.git");

  commands:
    # Clone if doesn't exist
    !git_repo_exists::
      "/usr/bin/git"
        args => "clone -b $(branch) $(repo) $(path)";

    # Pull if exists (every 3 minutes)
    git_repo_exists::
      "/usr/bin/git"
        args => "-C $(path) pull origin $(branch)",
        action => if_elapsed("180");
}
```

### Advantages for DNS Management

#### 1. Autonomous & Resilient
✅ **Works without master** (standalone)
✅ **Self-healing** (continuous convergence)
✅ **Continues if GitHub is down** (uses last good config)
✅ **Predictable execution** (every 5 minutes)

#### 2. Lightweight
✅ **~10MB memory** (vs 50MB custom, 600MB Salt)
✅ **Written in C** (fast, efficient)
✅ **Minimal dependencies** (no Python stack)
✅ **Low CPU usage** (compiled)

#### 3. Proven at Scale
✅ **32 years in production** (since 1993)
✅ **Used by Facebook** (managed 1M+ servers)
✅ **LinkedIn, Yahoo, others** (proven)
✅ **Scales to 100,000+ nodes**

#### 4. Promise Theory
✅ **Declarative** (what, not how)
✅ **Idempotent** (safe to re-run)
✅ **Self-documenting** (promises are clear)
✅ **Convergent** (eventual consistency)

## Comparison: Custom vs Salt vs mgmt vs CFEngine

| Feature | Custom GitOps | SaltStack | mgmt | CFEngine |
|---------|---------------|-----------|------|----------|
| **Age** | New (2025) | 2011 | 2015 (v1.0 2025) | **1993** |
| **Maturity** | ✅ Proven | ✅ Mature | ⚠️ New | ✅ **Ancient** |
| **Stars** | N/A | ~14k | 4,094 | 514 |
| **Installation** | ✅ Simple | ❌ Complex | ⚠️ Go binary | ⚠️ Package/compile |
| **Language** | Python/Bash | Python | Go | **C** |
| **Learning Curve** | ✅ Low | ⚠️ Medium | ❌ High | ❌ **High** |
| **Memory** | ✅ 50MB | ❌ 600MB | ⚠️ 100-200MB | ✅ **~10MB** |
| **Autonomous** | ❌ No | ❌ No | ⚠️ Partial | ✅ **Yes** |
| **Event-Driven** | ❌ Poll | ⚠️ Optional | ✅ Yes | ❌ Poll |
| **Convergence** | ❌ 3 min | ⚠️ Configurable | ✅ Real-time | ⚠️ 5 min |
| **Multi-Host** | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |
| **Community** | ❌ None | ✅ Large | ⚠️ Growing | ⚠️ **Small** |
| **Commercial** | ❌ No | ⚠️ Optional | ❌ No | ✅ **Yes** |
| **For Single Host** | ✅ Perfect | ❌ Overkill | ❌ Overkill | ⚠️ **Capable** |
| **Complexity** | ✅ Simple | ❌ High | ❌ High | ❌ **Very High** |

## Pros and Cons for DNS Use Case

### Pros ✅

#### Maturity & Stability
- ✅ 32 years in production (since 1993)
- ✅ Proven at massive scale (Facebook, LinkedIn)
- ✅ Extremely stable and reliable
- ✅ Well-understood behavior

#### Performance
- ✅ Lightweight (~10MB memory)
- ✅ Written in C (fast, efficient)
- ✅ Low overhead
- ✅ Minimal dependencies

#### Architecture
- ✅ Autonomous (works without master)
- ✅ Self-healing (continuous convergence)
- ✅ Resilient (continues if hub down)
- ✅ Scales infinitely

#### Promise Theory
- ✅ Declarative model
- ✅ Idempotent operations
- ✅ Mathematical foundation
- ✅ Predictable behavior

### Cons ❌

#### Complexity
- ❌ **Very steep learning curve**
- ❌ **Unique language** (not YAML, not Python)
- ❌ **Complex concepts** (Promise Theory)
- ❌ **Different paradigm** (takes time to learn)

#### Community
- ❌ **Small community** (514 stars vs 14k Salt, 4k mgmt)
- ❌ **Limited resources** (fewer tutorials, examples)
- ❌ **Less active discussions** (smaller user base)
- ❌ **Declining popularity** (vs Ansible, Terraform)

#### Modern Features
- ❌ **No event-driven** (poll-based like custom)
- ❌ **No real-time** (5-minute convergence)
- ❌ **Old-school architecture** (vs modern tools)
- ❌ **No YAML** (custom language)

#### Overkill for Use Case
- ❌ **Single Pi-hole host** (autonomous features wasted)
- ❌ **DNS-only** (enterprise tool for simple need)
- ❌ **Working solution exists** (no compelling reason)
- ❌ **5-min convergence** (vs 3-min current - worse!)

#### Commercial Focus
- ⚠️ **Community edition limited** (basic features)
- ⚠️ **Enterprise upsell** (best features paid)
- ⚠️ **Less community investment** (company-driven)

## Technical Evaluation

### Installation Options

#### Option 1: Package (Debian/Ubuntu)
```bash
# Add CFEngine repository
wget -qO- https://cfengine-package-repos.s3.amazonaws.com/pub/gpg.key | apt-key add -
echo "deb https://cfengine-package-repos.s3.amazonaws.com/pub/apt/packages stable main" > /etc/apt/sources.list.d/cfengine-community.list

# Install
apt update
apt install cfengine-community
```

#### Option 2: Compile from Source
```bash
# Dependencies
apt install build-essential libssl-dev libpcre3-dev

# Compile
git clone https://github.com/cfengine/core.git
cd core
./autogen.sh
./configure
make
make install
```

### Resource Usage
- **Binary Size:** ~5MB (cf-agent)
- **Runtime Memory:** ~10MB (minimal)
- **CPU:** Very low (C, not interpreted)
- **Disk:** ~50MB (binaries + policies)

### Complexity Assessment
- **Learning Curve:** **STEEP** (6-12 months to mastery)
- **Language:** Unique (not Python/YAML/Ruby)
- **Concepts:** Promise Theory (new paradigm)
- **Documentation:** Good but dense
- **Community:** Smaller (less help available)

## Real-World Usage

### Who Uses CFEngine?

#### Major Deployments (Historical)
- **Facebook** - Managed 1M+ servers (later moved to Chef)
- **LinkedIn** - Infrastructure management
- **Yahoo** - Early adopter
- **Zynga** - Game infrastructure
- **Various Telcos** - Network equipment

#### Current Status
- Still used in enterprise/telco
- Declining market share
- Ansible/Terraform taking over
- Niche use cases (very large scale, autonomous)

### Why People Choose CFEngine
1. ✅ **Massive scale** (100,000+ nodes)
2. ✅ **Autonomous operation** (no master needed)
3. ✅ **Extreme efficiency** (C, not Python/Ruby)
4. ✅ **Proven stability** (32 years)
5. ✅ **Self-healing** (continuous convergence)

### Why People DON'T Choose CFEngine
1. ❌ **Steep learning curve** (unique language)
2. ❌ **Small community** (vs Ansible, Salt)
3. ❌ **Complex** (vs YAML-based tools)
4. ❌ **Declining popularity** (market trend)
5. ❌ **Limited modern features** (no event-driven, etc.)

## Risk Assessment

### Low Risk ✅
1. **Maturity:** 32 years in production
2. **Stability:** Extremely stable
3. **Performance:** Proven efficient
4. **Scalability:** Handles massive deployments

### Medium Risk ⚠️
1. **Learning Curve:** Very steep (6+ months)
2. **Community:** Small (limited help)
3. **Commercial:** Company-driven (not community)
4. **Popularity:** Declining trend

### High Risk ❌
1. **Overkill:** Enterprise tool for simple need
2. **Complexity:** Much harder than current solution
3. **No clear benefit:** Similar convergence time
4. **Lock-in:** Unique language (hard to migrate away)

## Recommendation for Your Use Case

### Current Situation
- Single Pi-hole host (pi-nvme-1)
- DNS management only
- Working custom solution (3-phase validation)
- 3-minute sync interval (acceptable)
- Production-ready and stable

### Should You Use CFEngine?

**ABSOLUTELY NOT ❌**

### Reasons (Priority Order):

#### 1. Massive Overkill
- CFEngine designed for **100,000+ servers**
- You have **1 Pi-hole**
- Like using a nuclear reactor to heat your coffee

#### 2. Extreme Complexity
- **6-12 months** to learn properly
- **Unique language** (steep curve)
- **Promise Theory** (new paradigm)
- Current solution: **Works in 5 minutes**

#### 3. No Benefit
- CFEngine: 5-minute convergence
- Your custom: 3-minute convergence
- **You'd be SLOWER with CFEngine!**

#### 4. Declining Ecosystem
- Small community (514 stars)
- Limited tutorials
- Fewer users
- Market moving to Ansible/Terraform

#### 5. Working Solution Exists
- Custom solution: **Perfect**
- CFEngine advantage: **None**
- Risk: **High**
- Benefit: **Zero**

## When Would CFEngine Make Sense?

### Use CFEngine When:
✅ **Managing 10,000+ distributed nodes**
- Autonomous operation critical
- Massive scale needed
- Extreme efficiency required

✅ **No central infrastructure**
- Nodes must work independently
- Hub can be down
- Self-healing critical

✅ **Telco/Network equipment**
- Embedded systems
- Minimal resources
- High reliability needed

✅ **Already using CFEngine**
- Legacy infrastructure
- Team expertise exists
- Migration cost too high

✅ **Enterprise contract**
- Support required
- Compliance needed
- Budget available

### DON'T Use CFEngine When:
❌ **Small scale** (< 100 nodes) - **YOUR CASE**
❌ **Single host** - **YOUR CASE**
❌ **Simple use case** - **YOUR CASE**
❌ **Working solution exists** - **YOUR CASE**
❌ **Need quick wins** (steep learning curve)
❌ **Want modern features** (event-driven, etc.)
❌ **Prefer standard tools** (YAML, Python)
❌ **Need large community** (tutorials, support)

## Alternative Recommendation

### Best Options for Your Use Case (Ranked):

#### 1. ✅ Keep Custom DNS GitOps (BEST)
- **Status:** Production-ready
- **Complexity:** Low
- **Maintenance:** Minimal
- **Risk:** None
- **Benefit:** Perfect fit
- **Time to deploy:** Already done!

#### 2. ⚠️ Ansible (If Broader Needs)
- **When:** Need more than DNS
- **Benefit:** Simple, popular, agentless
- **Risk:** Low (mature, standard)
- **Learning curve:** Low (YAML)
- **Community:** Huge

#### 3. ⚠️ SaltStack (If Scaling)
- **When:** 3+ Pi-hole hosts
- **Benefit:** Mature, proven
- **Risk:** Medium (setup complexity)
- **Community:** Large

#### 4. 👀 mgmt (Future, Greenfield)
- **When:** 10+ hosts + real-time critical
- **Benefit:** Modern, innovative
- **Risk:** High (v1.0 recent)
- **Timeline:** 2027+ (after maturity)

#### 5. ❌ CFEngine (Extreme Scale Only)
- **When:** 10,000+ nodes + autonomous critical
- **Benefit:** Proven at massive scale
- **Risk:** Very high (complexity, learning)
- **Timeline:** **Never for your use case**

## Interesting Historical Context

### CFEngine's Place in History

```
1993: CFEngine invented config management
  → Introduced Promise Theory
  → Autonomous agent model
  → Declarative configuration
  ↓
2005: Puppet (inspired by CFEngine)
  → Made it easier (Ruby DSL)
  → Focused on usability
  ↓
2008: Chef (Ruby-based)
  → Procedural approach
  → Developer-friendly
  ↓
2011: SaltStack (Python)
  → Event-driven option
  → Remote execution
  ↓
2012: Ansible (Python)
  → Agentless (SSH)
  → YAML (simple)
  → Won the market
  ↓
2015: mgmt (Go)
  → Real-time convergence
  → Parallel execution
  → Next generation?
```

### CFEngine's Legacy
- **Invented the category** (1993)
- **Academic foundation** (Promise Theory)
- **Proven at scale** (Facebook, etc.)
- **Still relevant** (niche use cases)
- **Declining popularity** (simpler tools won)

### Why Ansible Won the Market
1. ✅ **Agentless** (SSH-based)
2. ✅ **YAML** (easy to read/write)
3. ✅ **Low barrier** (quick start)
4. ✅ **Large community** (Red Hat backing)
5. ✅ **Good enough** (pragmatic)

### Why CFEngine Didn't
1. ❌ **Too complex** (unique language)
2. ❌ **Steep curve** (months to learn)
3. ❌ **Over-engineered** (for most needs)
4. ❌ **Small community** (relative)
5. ❌ **Not "good enough"** (simpler tools sufficed)

## Conclusion

### For Your DNS Management on pi-nvme-1:

**Recommendation: Keep Custom DNS GitOps Solution** ✅

### Reasons (Final):

1. ✅ **CFEngine is MASSIVE overkill**
   - Designed for 100,000+ servers
   - You have 1 Pi-hole
   - Nuclear reactor for coffee

2. ❌ **No benefit whatsoever**
   - CFEngine: 5-min convergence
   - Custom: 3-min convergence
   - **You'd be SLOWER!**

3. ❌ **Extreme complexity**
   - 6-12 months to learn
   - Unique language
   - Promise Theory
   - Custom works NOW

4. ❌ **Working solution exists**
   - Production-ready
   - Well-tested
   - Zero issues
   - Perfect fit

5. ❌ **Declining ecosystem**
   - Small community
   - Limited resources
   - Market moving away

### CFEngine Summary

**CFEngine is:**
- ✅ Mature (32 years)
- ✅ Proven (Facebook scale)
- ✅ Efficient (C, ~10MB)
- ✅ Autonomous (self-healing)

**But for you:**
- ❌ Massive overkill
- ❌ No benefit
- ❌ Extreme complexity
- ❌ Wrong tool for job

### Final Comparison

| Tool | Age | Use Case | Verdict |
|------|-----|----------|---------|
| **Custom DNS GitOps** | New | Single host DNS | ✅ **KEEP** |
| **SaltStack** | 2011 | 3+ hosts | ⚠️ Future |
| **mgmt** | v1.0 2025 | 10+ hosts + real-time | 👀 Watch |
| **CFEngine** | 1993 | 10,000+ hosts | ❌ **Never** |

---

## Engineering Wisdom

> "CFEngine is like a Formula 1 race car. Incredibly powerful, proven at the highest level, but completely impractical for your daily commute to the grocery store."

**Your need:** Grocery run (single Pi-hole, DNS)  
**Custom solution:** Toyota Corolla (reliable, efficient, perfect)  
**CFEngine:** Formula 1 car (overkill, expensive, impractical)

**Decision: Drive the Corolla. ✅**

---

## Documentation

**File:** `~/DNS-CFENGINE-EVALUATION.md`  
**Size:** ~18KB  
**Status:** ✅ Complete

**All Config Management Tools Evaluated:**
1. Custom DNS GitOps ✅ KEEP
2. SaltStack ⚠️ Overkill (evaluated)
3. mgmt 👀 Too new (evaluated)
4. CFEngine ❌ MASSIVE overkill (evaluated)

**Total Evaluation:** 4 tools, 34KB documentation

**Conclusion:** Custom solution is optimal. ✅

---

*"Don't bring a nuclear reactor to a campfire."*
