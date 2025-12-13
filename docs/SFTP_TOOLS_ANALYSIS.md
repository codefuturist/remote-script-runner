# SFTP/SCP Console Tools Analysis

**Generated**: December 11, 2024
**Analysis**: File transfer tools for SFTP, SCP, FTP protocols

## Executive Summary

**Current Coverage**: ✅ **GOOD** - Basic SFTP/SCP functionality covered
**Missing Tools**: 4 notable Windows-specific tools
**Recommendation**: Add Windows-specific tools (PuTTY suite, WinSCP)

## Current SFTP/FTP Console Tools

### ✅ Available in Configurations

| Tool | Type | File | Console | Description |
|------|------|------|---------|-------------|
| **sftp** | SFTP | network.yaml | ✅ Yes | OpenSSH built-in SFTP client (interactive) |
| **lftp** | FTP/SFTP | backup-sync.yaml | ✅ Yes | Advanced scripting client (HTTP/FTP/SFTP) |
| **ncftp** | FTP | backup-sync.yaml | ✅ Yes | Enhanced FTP client |
| **rclone** | Cloud/SFTP | backup-sync.yaml | ✅ Yes | Multi-cloud sync tool (includes SFTP) |
| **rsync** | SSH-based | backup-sync.yaml | ✅ Yes | Fast incremental transfer over SSH |
| **sshfs** | SSH-based | network.yaml | ✅ Yes | Mount remote filesystem over SSH |
| **curlftpfs** | FTP | network.yaml | ✅ Yes | Mount FTP as filesystem |
| **openssh-client** | SSH | network.yaml | ✅ Yes | Includes scp, sftp, ssh |
| **curl** | Multi | backup-sync.yaml | ✅ Yes | Supports SFTP/FTP protocols |
| **wget** | Multi | backup-sync.yaml | ✅ Yes | Supports FTP downloads |

### ❌ GUI Tools (Not Console)

| Tool | Type | File | Description |
|------|------|------|-------------|
| filezilla | GUI | network.yaml | Popular GUI FTP/SFTP client |
| cyberduck | GUI | network.yaml | macOS GUI client |
| transmit | GUI | network.yaml | macOS commercial client |

## Missing Console SFTP/SCP Tools

### 🟡 Medium Priority - Windows-Specific Tools

#### 1. WinSCP (Windows)
**Status**: ⚠️ Missing
**Priority**: HIGH
**Why Add**: Most popular Windows SFTP/SCP client

```yaml
- name: winscp
  description: WinSCP - SFTP/SCP/FTP client for Windows (GUI + console)
  recommended:
    windows: winget
  winget: WinSCP.WinSCP
  choco: winscp
  scoop: winscp
  note: "Console mode available via winscp.com"
```

**Use Cases**:
- Windows users needing SFTP/SCP
- Scripted file transfers on Windows
- Both GUI and command-line usage

#### 2. PuTTY (Windows)
**Status**: ⚠️ Missing
**Priority**: MEDIUM
**Why Add**: Standard SSH/SFTP toolkit for Windows

```yaml
- name: putty
  description: PuTTY - SSH/Telnet client and tools (includes pscp, psftp)
  recommended:
    windows: winget
  winget: PuTTY.PuTTY
  choco: putty
  scoop: putty
  note: "Includes pscp (SCP client) and psftp (SFTP client)"
```

**Tools Included**:
- `putty.exe` - SSH client
- `pscp.exe` - SCP command-line client
- `psftp.exe` - SFTP command-line client
- `puttygen.exe` - Key generator

#### 3. pscp (PuTTY SCP)
**Status**: ⚠️ Missing (bundled with PuTTY)
**Priority**: LOW
**Note**: Should be mentioned in PuTTY description

#### 4. psftp (PuTTY SFTP)
**Status**: ⚠️ Missing (bundled with PuTTY)
**Priority**: LOW
**Note**: Should be mentioned in PuTTY description

### 🟢 Low Priority - Already Covered

#### 5. scp (OpenSSH)
**Status**: ✅ Already available via `openssh-client`
**Location**: network.yaml
**Note**: Could add explicit entry or clarify in description

```yaml
# Option: Add explicit scp entry
- name: scp
  description: Secure copy - file transfer over SSH (OpenSSH)
  brew: openssh
  apt: openssh-client
  dnf: openssh-clients
  note: "Usually pre-installed on Linux/macOS"
```

#### 6. ftp (basic)
**Status**: ⚠️ Not explicitly listed
**Priority**: VERY LOW
**Note**: Usually pre-installed, not recommended (insecure)

## Feature Gaps

### 1. SFTP Support Documentation

**Issue**: `curl` and `wget` support SFTP but descriptions don't mention it

**Current**:
```yaml
- name: curl
  description: Data transfer tool supporting multiple protocols
```

**Recommended**:
```yaml
- name: curl
  description: Data transfer tool (HTTP, FTP, SFTP, SCP, and more)
  note: "Supports SFTP via curl sftp://user@host/path"
```

**Current**:
```yaml
- name: wget
  description: Non-interactive network downloader
```

**Recommended**:
```yaml
- name: wget
  description: Non-interactive downloader (HTTP, HTTPS, FTP)
  note: "Limited SFTP support - use curl for SFTP"
```

### 2. SCP Clarification

**Issue**: `scp` not explicitly mentioned

**Recommendation**: Add note to `openssh-client`:
```yaml
- name: openssh-client
  description: OpenSSH client (includes ssh, scp, sftp, ssh-keygen)
  brew: openssh
  apt: openssh-client
  dnf: openssh-clients
  note: "Provides scp for secure file copy and sftp client"
```

## Recommendations by Platform

### Linux/macOS ✅ Well Covered

**Available**:
- ✅ `sftp` - Interactive SFTP
- ✅ `scp` - Quick file copy (via openssh-client)
- ✅ `lftp` - Advanced scripting
- ✅ `rsync` - Sync over SSH
- ✅ `sshfs` - Mount remote FS
- ✅ `curl` - SFTP/FTP support

**Assessment**: Excellent coverage for Unix-like systems

### Windows ⚠️ Gaps

**Available**:
- ✅ `lftp` - Advanced scripting
- ✅ `rsync` - Via Cygwin/WSL
- ✅ `curl` - SFTP support
- ✅ `openssh` - Windows 10+ includes OpenSSH

**Missing**:
- ❌ `winscp` - Most popular Windows SFTP tool
- ❌ `putty` - Standard SSH/SCP/SFTP toolkit

**Assessment**: Should add Windows-specific tools

## Use Case Coverage

| Use Case | Tools Available | Status |
|----------|----------------|--------|
| Interactive SFTP browsing | sftp, lftp | ✅ Good |
| Simple file copy | scp (openssh-client) | ✅ Good |
| Scripted file transfer | lftp, rclone, rsync | ✅ Excellent |
| Batch file sync | rsync, rclone | ✅ Excellent |
| Mount remote FS | sshfs | ✅ Good |
| Windows SFTP | openssh, curl | ⚠️ Basic |
| Windows GUI+Console | - | ❌ Missing |
| Cloud + SFTP | rclone | ✅ Excellent |

## Proposed Additions

### High Priority

Add to `network.yaml` or create `windows-network.yaml`:

```yaml
- name: winscp
  description: WinSCP - Windows SFTP/SCP/FTP/WebDAV client
  recommended:
    windows: winget
  winget: WinSCP.WinSCP
  choco: winscp
  scoop: winscp
  note: "GUI + command-line mode (winscp.com). Most popular Windows SFTP tool."

- name: putty
  description: PuTTY - SSH/Telnet/SCP/SFTP toolkit for Windows
  recommended:
    windows: winget
  winget: PuTTY.PuTTY
  choco: putty
  scoop: putty
  portable: https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html
  note: "Includes pscp (SCP), psftp (SFTP), puttygen (key gen)"
```

### Medium Priority

Update existing entries to clarify SFTP capabilities:

```yaml
- name: openssh-client
  description: OpenSSH client (ssh, scp, sftp, ssh-keygen)
  brew: openssh
  apt: openssh-client
  dnf: openssh-clients
  note: "Primary SSH/SCP/SFTP client for Unix/Linux/macOS"

- name: curl
  description: Data transfer tool (HTTP, FTP, SFTP, SCP, and 20+ protocols)
  brew: curl
  winget: cURL.cURL
  choco: curl
  scoop: curl
  note: "Supports SFTP: curl sftp://user@host/path -u user:pass"
```

### Low Priority

Add explicit `scp` entry (optional):

```yaml
- name: scp
  description: Secure copy - OpenSSH file transfer command
  brew: openssh
  apt: openssh-client
  dnf: openssh-clients
  note: "Usually included with openssh-client. Use rsync for advanced needs."
```

## Comparison Matrix

### Console SFTP Clients

| Feature | sftp | lftp | winscp (console) | putty (psftp) |
|---------|------|------|------------------|---------------|
| Platform | Unix/Linux/macOS/Win10+ | Unix/Linux | Windows | Windows |
| Interactive | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| Scripting | ⚠️ Basic | ✅ Excellent | ✅ Good | ⚠️ Basic |
| Protocol | SFTP | FTP/SFTP/HTTP | SFTP/SCP/FTP | SFTP |
| Resume transfers | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| Sync/mirror | ❌ No | ✅ Yes | ✅ Yes | ❌ No |
| Bookmarks | ❌ No | ✅ Yes | ✅ Yes | ❌ No |
| Tab completion | ✅ Yes | ✅ Yes | ⚠️ Limited | ✅ Yes |

### File Transfer Methods

| Method | Command | Use Case | Speed | Compression |
|--------|---------|----------|-------|-------------|
| scp | `scp file user@host:` | Quick copy | Fast | Optional (-C) |
| sftp | `sftp user@host` | Interactive browse | Medium | Automatic |
| rsync | `rsync -avz file user@host:` | Sync/backup | Fast | ✅ Yes (-z) |
| lftp | `lftp sftp://user@host` | Scripted transfer | Medium | Optional |
| rclone | `rclone copy file sftp:` | Cloud/multi-dest | Fast | Optional |

## Best Practices

### For Linux/macOS Users

1. **Quick file copy**: Use `scp`
   ```bash
   scp file.txt user@server:/path/
   ```

2. **Directory sync**: Use `rsync`
   ```bash
   rsync -avz /local/dir/ user@server:/remote/dir/
   ```

3. **Interactive browsing**: Use `sftp` or `lftp`
   ```bash
   lftp sftp://user@server
   ```

4. **Mount remote FS**: Use `sshfs`
   ```bash
   sshfs user@server:/path /local/mount
   ```

### For Windows Users

1. **GUI + scripting**: Use WinSCP (once added)
   ```cmd
   winscp.com /command "open sftp://user@server" "get file.txt" "exit"
   ```

2. **Quick command-line**: Use PuTTY pscp (once added)
   ```cmd
   pscp file.txt user@server:/path/
   ```

3. **Modern Windows 10+**: Use built-in OpenSSH
   ```cmd
   scp file.txt user@server:/path/
   ```

## Conclusion

**Current State**: ✅ **GOOD**
- Excellent Unix/Linux/macOS coverage
- Basic Windows coverage via OpenSSH

**Recommended Actions**:
1. ✅ **Add WinSCP** to network.yaml (High Priority)
2. ✅ **Add PuTTY** to network.yaml (Medium Priority)
3. ✅ **Update curl description** to mention SFTP support
4. ✅ **Update openssh-client description** to list included tools
5. ⚠️ (Optional) Add explicit `scp` entry for clarity

**Impact**: Adding these 2 tools will provide complete SFTP/SCP coverage for all platforms.

---

**Analysis By**: Package Verification System
**Total SFTP/FTP Tools**: 14 (10 console + 4 GUI)
**Coverage Rating**: 8/10 (Good)
**With Additions**: 10/10 (Excellent)
