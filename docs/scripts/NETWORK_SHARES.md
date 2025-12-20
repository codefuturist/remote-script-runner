# Network Share Management

A comprehensive, cross-platform tool for managing network file shares (NFS, SMB/CIFS, SSHFS, WebDAV).

## Features

- **Multi-Protocol Support**: NFS, SMB/CIFS, SSHFS, WebDAV
- **Auto-Detection**: Automatically detects share type from path
- **Credential Management**: Environment variables, prompts, or encrypted storage
- **Share Discovery**: Find available shares on servers and scan networks
- **Persistent Configuration**: Save shares for easy remounting
- **Automount Support**: Generate fstab, systemd, or autofs configurations
- **Cross-Platform**: Linux, macOS, and Windows support
- **Interactive Mode**: Guided wizards for mounting and configuration

## Quick Start

### Mount a Share

```bash
# SMB/CIFS share (auto-detected)
rsr shares mount //server/share /mnt/share

# NFS export
rsr shares mount server:/export/data /mnt/data

# SSHFS (SSH filesystem)
rsr shares mount user@server:/home/user /mnt/remote

# With credentials
SMB_USER=john SMB_PASS=secret rsr shares mount //server/share /mnt/share

# Interactive mode
rsr shares mount -i
```

### Unmount a Share

```bash
rsr shares unmount /mnt/share
rsr shares umount /mnt/share --force
```

### Discover Shares

```bash
# List shares on a server
rsr shares discover fileserver.local

# Scan network for file servers
rsr shares scan
```

### Save Share Configuration

```bash
# Add a saved share
rsr shares add -n work -s //server/share -t /mnt/work

# Add with credentials and automount
rsr shares add -n mynas -s //nas.local/media -t /mnt/media -u admin --automount

# List saved shares
rsr shares list --saved

# Mount a saved share
rsr shares mount -n work

# Remove saved share
rsr shares remove work
```

### Credential Management

```bash
# Store credentials
rsr shares creds set -n myshare -u admin

# List stored credentials
rsr shares creds list

# Delete credentials
rsr shares creds delete myshare
```

### Automount Configuration

```bash
# Generate fstab entry
rsr shares automount generate myshare --method fstab

# Generate systemd mount unit
rsr shares automount generate myshare --method systemd

# Generate autofs config
rsr shares automount generate myshare --method autofs

# Enable automount for a share
rsr shares automount enable myshare
```

### Status & Health

```bash
# List all shares (mounted and saved)
rsr shares list

# Show share status
rsr shares status

# Health check
rsr shares health

# Test connectivity
rsr shares test //server/share
```

## Commands Reference

| Command | Description |
|---------|-------------|
| `mount` | Mount a network share |
| `unmount`, `umount` | Unmount a share |
| `remount` | Unmount and remount a share |
| `add` | Save a share configuration |
| `remove` | Remove a saved share |
| `show` | Show details of a saved share |
| `list` | List mounted and saved shares |
| `discover` | Discover shares on a server |
| `scan` | Scan network for file servers |
| `test` | Test share connectivity |
| `creds` | Manage credentials (set/get/delete/list) |
| `automount` | Manage automount (enable/disable/generate/status) |
| `status` | Show all share status |
| `health` | Health check for shares |

## Options

### Global Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --verbose` | Enable verbose output |
| `-d, --dry-run` | Show what would be done |
| `-y, --yes` | Auto-confirm prompts |
| `-i, --interactive` | Force interactive mode |
| `--json` | Output in JSON format |

### Mount Options

| Option | Description |
|--------|-------------|
| `-n, --name` | Share name for reference |
| `-s, --source` | Share source path |
| `-t, --target` | Local mount point |
| `-T, --type` | Share type (nfs/smb/sshfs/webdav) |
| `-o, --options` | Mount options |
| `-u, --user` | Username |
| `-p, --pass` | Password |
| `-D, --domain` | Windows domain |
| `-f, --force` | Force operation |
| `--save` | Save configuration |
| `--automount` | Enable automount |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SMB_USER`, `CIFS_USER` | Default SMB username |
| `SMB_PASS`, `CIFS_PASS` | Default SMB password |
| `<SHARE>_USER` | Username for specific share |
| `<SHARE>_PASS` | Password for specific share |
| `RSR_SHARE_CONFIG_DIR` | Config directory (default: `~/.config/rsr/shares`) |

## Share Path Formats

### SMB/CIFS

```
//server/share
\\server\share
smb://server/share
cifs://server/share
```

### NFS

```
server:/export/path
```

### SSHFS

```
user@server:/path
server:/path
sftp://server/path
ssh://user@server/path
```

### WebDAV

```
https://server/webdav
http://server/dav
dav://server/path
davs://server/path
```

## Configuration Files

Configurations are stored in `~/.config/rsr/shares/`:

```
~/.config/rsr/shares/
├── shares.json       # Saved share configurations
├── config.yaml       # User settings (optional)
└── creds/            # Encrypted credentials
    ├── myshare.creds
    └── work.creds
```

## Dependencies

### Linux

- **SMB/CIFS**: `cifs-utils` (`apt install cifs-utils`)
- **NFS**: `nfs-common` (`apt install nfs-common`)
- **SSHFS**: `sshfs` (`apt install sshfs`)
- **WebDAV**: `davfs2` (`apt install davfs2`)
- **Discovery**: `smbclient`, `nmap` or `avahi-daemon`

### macOS

- **SMB**: Built-in (`mount_smbfs`)
- **NFS**: Built-in (`mount_nfs`)
- **SSHFS**: `brew install macfuse sshfs`
- **WebDAV**: Built-in

### Windows

Uses native PowerShell cmdlets for SMB/mapped drives.

## Examples

### Mount Company File Share

```bash
# One-time mount
rsr shares mount //fileserver.company.com/shared /mnt/company -u john.doe

# Save for easy access
rsr shares add -n company -s //fileserver.company.com/shared -t /mnt/company -u john.doe

# Later, just run:
rsr shares mount -n company
```

### Home NAS Setup

```bash
# Add NAS with automount
rsr shares add -n nas-media -s //192.168.1.100/media -t /mnt/media --automount
rsr shares add -n nas-backup -s //192.168.1.100/backup -t /mnt/backup --automount

# Generate systemd mount units
rsr shares automount generate nas-media --method systemd
rsr shares automount generate nas-backup --method systemd
```

### Remote Development with SSHFS

```bash
# Mount remote project directory
rsr shares mount user@devserver:/home/user/projects /mnt/projects

# Save configuration
rsr shares add -n remote-dev -s user@devserver:/home/user/projects -t /mnt/projects
```

### Discovery and Exploration

```bash
# Scan local network
rsr shares scan

# Explore a specific server
rsr shares discover 192.168.1.50

# Test before mounting
rsr shares test //server/share
```

## Troubleshooting

### Share won't mount

1. Check connectivity: `rsr shares test //server/share`
2. Verify credentials: `rsr shares creds get myshare`
3. Check dependencies: The tool will suggest installation commands
4. Use verbose mode: `rsr shares mount -v //server/share /mnt/share`

### Permission denied

- SMB: Verify username/password, try with domain: `-D DOMAIN`
- NFS: Check export permissions on server
- SSHFS: Verify SSH key or password authentication

### Mount hangs

- Use soft mounts for NFS: `-o soft,timeo=30`
- Check network connectivity
- Force unmount: `rsr shares umount /mnt/share --force`

## See Also

- [RSR Documentation](../README.md)
- [Network Diagnostics](../diagnostics/README.md)
- [System Scripts](../../system/README.md)

