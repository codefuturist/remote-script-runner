# Duplicate Packages Analysis Report

**Generated**: December 11, 2024
**Total Duplicate Issues**: 68 packages

## Executive Summary

Found **68 packages** that appear in multiple YAML profile files:

- 🔴 **5 critical** - Duplicates within the same file
- ⚠️ **10 redundant** - Identical packages in multiple files (can be consolidated)
- ℹ️ **53 intentional** - Same package with different configurations (likely intentional for different use cases)

## 🔴 Critical: Duplicates Within Same File

These packages appear multiple times in the **same YAML file** (likely errors):

### 1. rclone (backup-sync.yaml)

- Appears 3 times in the same file
- **Action Required**: Merge into single entry

### 2. tabby (productivity.yaml)

- Appears 2 times in the same file
- **Action Required**: Remove duplicate

### 3. sshfs (network.yaml)

- Appears 2 times in the same file
- **Action Required**: Remove duplicate

### 4. macfuse (network.yaml)

- Appears 2 times in the same file
- **Action Required**: Remove duplicate

### 5. winfsp (network.yaml)

- Appears 2 times in the same file
- **Action Required**: Remove duplicate

## ⚠️ Redundant: Identical Packages in Multiple Files

These packages have **identical configurations** across multiple files and could be consolidated:

### High Priority (4 files)

#### 1. jq - YAML/JSON processor

**Found in**: core.yaml, development.yaml, example-multimethod.yaml, minimal.yaml

```yaml
name: jq
description: JSON processor
brew: jq
apt: jq
dnf: jq
```

**Recommendation**: Keep in `core.yaml` only (it's already in minimal). Remove from development and example-multimethod.

#### 2. htop - System monitor

**Found in**: development.yaml, example-multimethod.yaml, minimal.yaml, monitoring.yaml

```yaml
name: htop
description: Interactive process viewer
brew: htop
apt: htop
dnf: htop
```

**Recommendation**: Keep in `monitoring.yaml` and `minimal.yaml`. Remove from development and example.

### Medium Priority (3 files)

#### 3. openssl - Cryptography toolkit

**Found in**: network.yaml, security.yaml, webserver.yaml
**Recommendation**: Keep in `security.yaml` only. Reference from other profiles.

#### 4. fd - Fast find alternative

**Found in**: development.yaml, example-multimethod.yaml, productivity.yaml
**Recommendation**: Keep in `productivity.yaml` only.

#### 5. mtr - Network diagnostic tool

**Found in**: monitoring.yaml, network.yaml, server.yaml
**Recommendation**: Keep in `monitoring.yaml` and `network.yaml` (both valid use cases).

#### 6. rsync - File synchronization

**Found in**: backup-sync.yaml, development.yaml, server.yaml
**Recommendation**: Keep in `backup-sync.yaml` (primary use case).

#### 7. unzip - Extract zip archives

**Found in**: core.yaml, development.yaml, minimal.yaml
**Recommendation**: Keep in `core.yaml` only.

#### 8. zip - Create zip archives

**Found in**: core.yaml, development.yaml, minimal.yaml
**Recommendation**: Keep in `core.yaml` only.

#### 9. yq - YAML processor

**Found in**: core.yaml, development.yaml, kubernetes.yaml
**Recommendation**: Keep in `core.yaml` (most complete config).

### Low Priority (2 files)

The following appear in 2 files with identical configs:

- **ansible**: devops.yaml, server.yaml
- **borgbackup**: backup-sync.yaml, server.yaml
- **bzip2**: core.yaml, server.yaml
- **gzip**: core.yaml, server.yaml
- **iproute2**: network.yaml, server.yaml
- **lftp**: backup-sync.yaml, network.yaml
- **ncftp**: backup-sync.yaml, network.yaml
- **restic**: backup-sync.yaml, server.yaml
- **traceroute**: network.yaml, server.yaml
- **net-tools**: network.yaml, server.yaml

**General Recommendation**: Review if both locations are necessary or if one profile can reference the other.

## ℹ️ Intentional: Different Configurations

These 53 packages appear in multiple files but with **different package manager configurations** or descriptions. These are likely intentional to support different platforms or use cases.

### Examples of Valid Duplicates

#### git (development.yaml vs minimal.yaml)

- **development.yaml**: Full configuration with all package managers
- **minimal.yaml**: Basic configuration for minimal installs
- **Status**: ✅ Valid - Different scopes

#### vault (devops.yaml vs kubernetes.yaml)

- **devops.yaml**: Full HashiCorp Vault with Windows support
- **kubernetes.yaml**: Kubernetes-focused subset
- **Status**: ✅ Valid - Different contexts

#### trivy (docker.yaml vs kubernetes.yaml)

- **docker.yaml**: Docker-specific scanner
- **kubernetes.yaml**: Kubernetes-specific scanner with install script
- **Status**: ✅ Valid - Different use cases

### All Packages with Different Configs

<details>
<summary>Click to expand full list (53 packages)</summary>

1. 1password-cli (productivity.yaml, secrets.yaml)
2. act (docker.yaml, productivity.yaml)
3. ansible (devops.yaml, server.yaml)
4. awscli (backup-sync.yaml, devops.yaml)
5. bitwarden-cli (productivity.yaml, secrets.yaml)
6. cypress (nodejs.yaml, productivity.yaml)
7. direnv (development.yaml, productivity.yaml)
8. dnsutils (network.yaml, server.yaml)
9. fnm (languages-extended.yaml, nodejs.yaml)
10. fzf (development.yaml, productivity.yaml)
11. git (development.yaml, minimal.yaml)
12. htop (development.yaml, example-multimethod.yaml, minimal.yaml, monitoring.yaml)
13. iftop (monitoring.yaml, network.yaml)
14. istioctl (devops.yaml, kubernetes.yaml)
15. jenkins (devops.yaml, powershell.yaml)
16. jq (core.yaml, development.yaml, example-multimethod.yaml, minimal.yaml)
17. jupyter (ai-ml.yaml, python.yaml)
18. jupyterlab (ai-ml.yaml, python.yaml)
19. linkerd (devops.yaml, kubernetes.yaml)
20. logrotate (server.yaml, webserver.yaml)
21. n (languages-extended.yaml, nodejs.yaml)
22. netcat (development.yaml, network.yaml)
23. nethogs (monitoring.yaml, network.yaml)
24. nmap (development.yaml, network.yaml)
25. nvm (languages-extended.yaml, nodejs.yaml)
26. oh-my-posh (development.yaml, powershell.yaml)
27. openvpn (network.yaml, productivity.yaml)
28. pass (productivity.yaml, secrets.yaml)
29. php (languages-extended.yaml, webserver.yaml)
30. playwright (nodejs.yaml, productivity.yaml)
31. puppeteer (nodejs.yaml, productivity.yaml)
32. ripgrep (development.yaml, productivity.yaml)
33. screen (development.yaml, productivity.yaml)
34. sops (kubernetes.yaml, secrets.yaml)
35. starship (development.yaml, productivity.yaml)
36. tar (core.yaml, development.yaml)
37. tcpdump (monitoring.yaml, network.yaml)
38. tldr (development.yaml, nodejs.yaml)
39. tmux (development.yaml, productivity.yaml)
40. trivy (docker.yaml, kubernetes.yaml)
41. uv (languages-extended.yaml, python.yaml)
42. vault (devops.yaml, kubernetes.yaml)
43. vim (development.yaml, minimal.yaml)
44. wireguard (network.yaml, productivity.yaml)
45. wireshark (monitoring.yaml, network.yaml)
46. yq (core.yaml, development.yaml, kubernetes.yaml)
47. zellij (development.yaml, productivity.yaml)

</details>

## Recommendations

### Immediate Actions (Critical)

1. **Fix within-file duplicates**:

   ```bash
   # Check and fix these files
   - backup-sync.yaml (rclone - 3 times)
   - productivity.yaml (tabby - 2 times)
   - network.yaml (sshfs, macfuse, winfsp - 2 times each)
   ```

### Short-term Actions (Redundant Duplicates)

1. **Consolidate identical packages**:
   - Move `jq` to `core.yaml` only
   - Move `htop` to `monitoring.yaml` only
   - Move `fd` to `productivity.yaml` only
   - Remove redundant `zip`/`unzip` from development.yaml
   - Consolidate `yq` in `core.yaml`

2. **Create profile inheritance** (if not already supported):

   ```yaml
   # Instead of duplicating packages, reference other profiles
   includes:
     - minimal.yaml  # Gets git, vim, jq automatically
   ```

### Long-term Actions (Documentation)

1. **Document intentional duplicates**:
   - Add comments explaining why packages appear in multiple files
   - Example:

     ```yaml
     # trivy appears in both docker.yaml and kubernetes.yaml
     # with different configurations for each use case
     ```

2. **Create a deduplication policy**:
   - Core utilities → `core.yaml` or `minimal.yaml`
   - Specialized tools → specific profile only
   - Cross-cutting tools → document why duplicated

## Impact Analysis

### Storage/Maintenance Impact

- **10 redundant packages** × average 5 lines each = ~50 lines of duplicate code
- **5 critical duplicates** = potential configuration errors

### User Impact

- Minimal - users typically use specific profiles, not all
- May cause confusion when same package configured differently
- Could lead to installation conflicts if multiple profiles used

### CI/CD Impact

- Package verification runs on all profiles
- Duplicates increase verification time slightly
- May cause confusion in "not found" reports if one location has wrong name

## Automated Detection

The package verification system now includes duplicate detection. Run:

```bash
uv run tools/verify_packages.py --check-duplicates
```

## Next Steps

1. ✅ Generate this report
2. ⬜ Fix critical within-file duplicates
3. ⬜ Consolidate redundant identical packages
4. ⬜ Document intentional different-config duplicates
5. ⬜ Add profile inheritance/reference support (future enhancement)
6. ⬜ Update package verification to flag redundant duplicates

---

**Report Generated By**: Package Verification System
**Analysis Script**: `/tmp/analyze_duplicates.py`
**Total Files Analyzed**: 27 YAML profiles
**Total Packages**: ~1,485 package-manager pairs
