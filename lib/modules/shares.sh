#!/bin/sh
# lib/modules/shares.sh - RSR Network Share Management Module
# Cross-platform share mounting and management utilities
#
# Usage: rsr_load_module shares
#
# Provides:
#   - Share mounting/unmounting (NFS, SMB/CIFS, SSHFS, WebDAV)
#   - Credential management (environment variables, encrypted files)
#   - Share discovery (SMB, NFS)
#   - Persistent mount configuration (fstab, systemd, autofs)
#   - Share health monitoring

# =============================================================================
# Guard: Prevent double-sourcing
# =============================================================================

[ -n "${_RSR_MODULE_SHARES_LOADED:-}" ] && return 0
_RSR_MODULE_SHARES_LOADED=1

# Ensure core init is loaded
if [ -z "${_RSR_CORE_INIT_LOADED:-}" ]; then
    echo "ERROR: RSR core library must be loaded first" >&2
    return 1
fi

# =============================================================================
# Constants
# =============================================================================

RSR_SHARE_TYPE_NFS="nfs"
RSR_SHARE_TYPE_SMB="smb"
RSR_SHARE_TYPE_CIFS="cifs"
RSR_SHARE_TYPE_SSHFS="sshfs"
RSR_SHARE_TYPE_WEBDAV="webdav"

RSR_SHARE_CONFIG_DIR="${RSR_CONFIG_DIR:-$HOME/.config/rsr}/shares"
RSR_SHARE_CREDENTIALS_FILE="${RSR_SHARE_CONFIG_DIR}/credentials.enc"
RSR_SHARE_SAVED_FILE="${RSR_SHARE_CONFIG_DIR}/shares.json"

# =============================================================================
# Initialization
# =============================================================================

# Initialize shares module
# Usage: rsr_shares_init
rsr_shares_init() {
    # Create config directory if needed
    if [ ! -d "$RSR_SHARE_CONFIG_DIR" ]; then
        mkdir -p "$RSR_SHARE_CONFIG_DIR"
        chmod 700 "$RSR_SHARE_CONFIG_DIR"
    fi

    # Initialize saved shares file
    if [ ! -f "$RSR_SHARE_SAVED_FILE" ]; then
        echo '{"shares":[]}' > "$RSR_SHARE_SAVED_FILE"
        chmod 600 "$RSR_SHARE_SAVED_FILE"
    fi
}

# =============================================================================
# Share Type Detection
# =============================================================================

# Detect share type from path/URL
# Usage: rsr_share_detect_type "//server/share" -> "smb"
# Usage: rsr_share_detect_type "server:/path" -> "nfs"
rsr_share_detect_type() {
    _share_path="$1"

    case "$_share_path" in
        # SMB/CIFS paths
        //*)
            echo "$RSR_SHARE_TYPE_SMB"
            ;;
        \\\\*)
            echo "$RSR_SHARE_TYPE_SMB"
            ;;
        smb://*)
            echo "$RSR_SHARE_TYPE_SMB"
            ;;
        cifs://*)
            echo "$RSR_SHARE_TYPE_CIFS"
            ;;
        # SSHFS paths
        *:/*@*)
            echo "$RSR_SHARE_TYPE_SSHFS"
            ;;
        sftp://*)
            echo "$RSR_SHARE_TYPE_SSHFS"
            ;;
        ssh://*)
            echo "$RSR_SHARE_TYPE_SSHFS"
            ;;
        # WebDAV paths
        http://*|https://*)
            echo "$RSR_SHARE_TYPE_WEBDAV"
            ;;
        dav://*|davs://*)
            echo "$RSR_SHARE_TYPE_WEBDAV"
            ;;
        # NFS paths (server:/path format without @)
        *:/*)
            # Check if it looks like user@server (SSHFS)
            if echo "$_share_path" | grep -q '@'; then
                echo "$RSR_SHARE_TYPE_SSHFS"
            else
                echo "$RSR_SHARE_TYPE_NFS"
            fi
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
}

# Validate share path format
# Usage: rsr_share_validate_path "//server/share" "smb"
rsr_share_validate_path() {
    _path="$1"
    _type="${2:-}"

    [ -z "$_path" ] && return 1

    # Auto-detect type if not specified
    if [ -z "$_type" ]; then
        _type=$(rsr_share_detect_type "$_path") || return 1
    fi

    case "$_type" in
        smb|cifs)
            # Must be //server/share or smb://server/share
            echo "$_path" | grep -qE '^(//|\\\\|smb://|cifs://)[^/\\]+[/\\].+' || return 1
            ;;
        nfs)
            # Must be server:/path
            echo "$_path" | grep -qE '^[^:]+:/.+' || return 1
            ;;
        sshfs)
            # Must be user@server:/path or sftp://...
            echo "$_path" | grep -qE '^([^@]+@)?[^:]+:/.+|^s(ftp|sh)://' || return 1
            ;;
        webdav)
            # Must be http(s):// or dav(s)://
            echo "$_path" | grep -qE '^(https?|davs?)://.+' || return 1
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

# =============================================================================
# Share Path Parsing
# =============================================================================

# Parse SMB path into components
# Usage: rsr_share_parse_smb "//server/share/path"
# Sets: RSR_SHARE_SERVER, RSR_SHARE_NAME, RSR_SHARE_SUBPATH
rsr_share_parse_smb() {
    _path="$1"

    # Remove protocol prefix and normalize backslashes to forward slashes
    _path=$(echo "$_path" | sed -E 's#^(//|\\\\|smb://|cifs://)##' | tr '\\' '/')

    # Extract server (first component)
    RSR_SHARE_SERVER=$(echo "$_path" | cut -d'/' -f1)

    # Extract share name (second component)
    RSR_SHARE_NAME=$(echo "$_path" | cut -d'/' -f2)

    # Extract subpath (remaining components)
    RSR_SHARE_SUBPATH=$(echo "$_path" | cut -d'/' -f3-)

    export RSR_SHARE_SERVER RSR_SHARE_NAME RSR_SHARE_SUBPATH
}

# Parse NFS path into components
# Usage: rsr_share_parse_nfs "server:/export/path"
# Sets: RSR_SHARE_SERVER, RSR_SHARE_EXPORT
rsr_share_parse_nfs() {
    _path="$1"

    RSR_SHARE_SERVER=$(echo "$_path" | cut -d':' -f1)
    RSR_SHARE_EXPORT=$(echo "$_path" | cut -d':' -f2-)

    export RSR_SHARE_SERVER RSR_SHARE_EXPORT
}

# Parse SSHFS path into components
# Usage: rsr_share_parse_sshfs "user@server:/path"
# Sets: RSR_SHARE_USER, RSR_SHARE_SERVER, RSR_SHARE_PATH
rsr_share_parse_sshfs() {
    _path="$1"

    # Remove protocol prefix
    _path=$(echo "$_path" | sed -E 's#^(sftp|ssh)://##')

    # Check for user@server format
    if echo "$_path" | grep -q '@'; then
        RSR_SHARE_USER=$(echo "$_path" | cut -d'@' -f1)
        _rest=$(echo "$_path" | cut -d'@' -f2-)
    else
        RSR_SHARE_USER=""
        _rest="$_path"
    fi

    RSR_SHARE_SERVER=$(echo "$_rest" | cut -d':' -f1)
    RSR_SHARE_PATH=$(echo "$_rest" | cut -d':' -f2-)

    export RSR_SHARE_USER RSR_SHARE_SERVER RSR_SHARE_PATH
}

# =============================================================================
# Dependency Checking
# =============================================================================

# Check if required tools for share type are available
# Usage: rsr_share_check_deps "smb"
rsr_share_check_deps() {
    _type="$1"
    _missing=""

    case "$_type" in
        smb|cifs)
            if [ "$(rsr_detect_os)" = "darwin" ]; then
                # macOS uses mount_smbfs
                rsr_command_exists mount_smbfs || _missing="mount_smbfs"
            else
                # Linux uses mount.cifs or cifs-utils
                rsr_command_exists mount.cifs || _missing="cifs-utils"
            fi
            ;;
        nfs)
            if [ "$(rsr_detect_os)" = "darwin" ]; then
                rsr_command_exists mount_nfs || _missing="mount_nfs"
            else
                rsr_command_exists mount.nfs || _missing="nfs-common"
            fi
            ;;
        sshfs)
            rsr_command_exists sshfs || _missing="sshfs"
            ;;
        webdav)
            if [ "$(rsr_detect_os)" = "darwin" ]; then
                # macOS has built-in WebDAV support
                true
            else
                rsr_command_exists mount.davfs || _missing="davfs2"
            fi
            ;;
    esac

    if [ -n "$_missing" ]; then
        echo "$_missing"
        return 1
    fi

    return 0
}

# Get installation command for missing dependency
# Usage: rsr_share_get_install_cmd "cifs-utils"
rsr_share_get_install_cmd() {
    _pkg="$1"

    case "$(rsr_detect_os)" in
        darwin)
            echo "brew install $_pkg"
            ;;
        linux)
            if rsr_command_exists apt-get; then
                echo "sudo apt-get install -y $_pkg"
            elif rsr_command_exists dnf; then
                echo "sudo dnf install -y $_pkg"
            elif rsr_command_exists yum; then
                echo "sudo yum install -y $_pkg"
            elif rsr_command_exists pacman; then
                echo "sudo pacman -S --noconfirm $_pkg"
            elif rsr_command_exists zypper; then
                echo "sudo zypper install -y $_pkg"
            else
                echo "# Install $_pkg using your package manager"
            fi
            ;;
        *)
            echo "# Install $_pkg"
            ;;
    esac
}

# =============================================================================
# Credential Management
# =============================================================================

# Get credentials from environment or prompt
# Usage: rsr_share_get_credentials "share_name" -> sets RSR_SHARE_USERNAME, RSR_SHARE_PASSWORD
rsr_share_get_credentials() {
    _share_name="$1"
    _env_prefix=$(echo "$_share_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_' | tr '.' '_')

    # Try environment variables first (format: SHARE_NAME_USER, SHARE_NAME_PASS)
    RSR_SHARE_USERNAME="${RSR_SHARE_USERNAME:-}"
    RSR_SHARE_PASSWORD="${RSR_SHARE_PASSWORD:-}"

    # Check share-specific environment variables
    eval "_user_var=\"\${${_env_prefix}_USER:-}\""
    eval "_pass_var=\"\${${_env_prefix}_PASS:-}\""

    [ -n "$_user_var" ] && RSR_SHARE_USERNAME="$_user_var"
    [ -n "$_pass_var" ] && RSR_SHARE_PASSWORD="$_pass_var"

    # Check generic SMB/CIFS environment variables
    [ -z "$RSR_SHARE_USERNAME" ] && RSR_SHARE_USERNAME="${SMB_USER:-${CIFS_USER:-${USER:-}}}"
    [ -z "$RSR_SHARE_PASSWORD" ] && RSR_SHARE_PASSWORD="${SMB_PASS:-${CIFS_PASS:-}}"

    export RSR_SHARE_USERNAME RSR_SHARE_PASSWORD
}

# Create credentials file for CIFS mount
# Usage: rsr_share_create_creds_file "username" "password" -> prints temp file path
rsr_share_create_creds_file() {
    _username="$1"
    _password="$2"
    _domain="${3:-}"

    _creds_file=$(mktemp)
    chmod 600 "$_creds_file"

    echo "username=$_username" > "$_creds_file"
    echo "password=$_password" >> "$_creds_file"
    [ -n "$_domain" ] && echo "domain=$_domain" >> "$_creds_file"

    echo "$_creds_file"
}

# Store encrypted credentials
# Usage: rsr_share_store_credentials "share_name" "username" "password"
rsr_share_store_credentials() {
    _name="$1"
    _username="$2"
    _password="$3"
    _domain="${4:-}"

    rsr_shares_init

    _creds_dir="${RSR_SHARE_CONFIG_DIR}/creds"
    mkdir -p "$_creds_dir"
    chmod 700 "$_creds_dir"

    _creds_file="${_creds_dir}/${_name}.creds"

    # Simple obfuscation (not encryption, but prevents casual reading)
    # For real security, integrate with system keyring
    {
        echo "username=$_username"
        echo "password=$_password"
        if [ -n "$_domain" ]; then echo "domain=$_domain"; fi
    } | base64 > "$_creds_file"

    chmod 600 "$_creds_file"

    rsr_log_ok "Credentials stored for '$_name'"
}

# Load stored credentials
# Usage: rsr_share_load_credentials "share_name"
rsr_share_load_credentials() {
    _name="$1"
    _creds_file="${RSR_SHARE_CONFIG_DIR}/creds/${_name}.creds"

    if [ ! -f "$_creds_file" ]; then
        return 1
    fi

    _decoded=$(base64 -d < "$_creds_file" 2>/dev/null || base64 -D < "$_creds_file" 2>/dev/null)

    RSR_SHARE_USERNAME=$(echo "$_decoded" | grep '^username=' | cut -d'=' -f2-)
    RSR_SHARE_PASSWORD=$(echo "$_decoded" | grep '^password=' | cut -d'=' -f2-)
    RSR_SHARE_DOMAIN=$(echo "$_decoded" | grep '^domain=' | cut -d'=' -f2-)

    export RSR_SHARE_USERNAME RSR_SHARE_PASSWORD RSR_SHARE_DOMAIN
}

# Delete stored credentials
# Usage: rsr_share_delete_credentials "share_name"
rsr_share_delete_credentials() {
    _name="$1"
    _creds_file="${RSR_SHARE_CONFIG_DIR}/creds/${_name}.creds"

    if [ -f "$_creds_file" ]; then
        rm -f "$_creds_file"
        rsr_log_ok "Credentials deleted for '$_name'"
    fi
}

# List stored credentials
# Usage: rsr_share_list_credentials
rsr_share_list_credentials() {
    _creds_dir="${RSR_SHARE_CONFIG_DIR}/creds"

    if [ -d "$_creds_dir" ]; then
        find "$_creds_dir" -name '*.creds' -exec basename {} .creds \; 2>/dev/null
    fi
}

# =============================================================================
# Mount Operations
# =============================================================================

# Mount a network share
# Usage: rsr_share_mount "//server/share" "/mnt/share" [options]
rsr_share_mount() {
    _source="$1"
    _target="$2"
    _opts="${3:-}"
    _type="${4:-}"

    # Auto-detect type if not specified
    if [ -z "$_type" ]; then
        _type=$(rsr_share_detect_type "$_source") || {
            rsr_log_error "Cannot detect share type for: $_source"
            return 1
        }
    fi

    # Check dependencies
    _missing=$(rsr_share_check_deps "$_type")
    if [ $? -ne 0 ]; then
        rsr_log_error "Missing dependency: $_missing"
        rsr_log_info "Install with: $(rsr_share_get_install_cmd "$_missing")"
        return "$RSR_EXIT_DEPENDENCY"
    fi

    # Create mount point if needed
    if [ ! -d "$_target" ]; then
        mkdir -p "$_target" || {
            rsr_log_error "Cannot create mount point: $_target"
            return 1
        }
    fi

    # Perform mount based on type
    case "$_type" in
        smb|cifs)
            _rsr_mount_smb "$_source" "$_target" "$_opts"
            ;;
        nfs)
            _rsr_mount_nfs "$_source" "$_target" "$_opts"
            ;;
        sshfs)
            _rsr_mount_sshfs "$_source" "$_target" "$_opts"
            ;;
        webdav)
            _rsr_mount_webdav "$_source" "$_target" "$_opts"
            ;;
        *)
            rsr_log_error "Unsupported share type: $_type"
            return 1
            ;;
    esac
}

# Internal: Mount SMB/CIFS share
_rsr_mount_smb() {
    _source="$1"
    _target="$2"
    _opts="$3"

    if [ "$(rsr_detect_os)" = "darwin" ]; then
        # macOS mount
        _mount_opts=""

        if [ -n "$RSR_SHARE_USERNAME" ] && [ -n "$RSR_SHARE_PASSWORD" ]; then
            # URL encode special characters in password
            _encoded_pass=$(printf '%s' "$RSR_SHARE_PASSWORD" | sed 's/@/%40/g; s/:/%3A/g; s/\//%2F/g')
            # Convert //server/share to smb://user:pass@server/share
            _smb_url=$(echo "$_source" | sed "s#^//\(.*\)#smb://${RSR_SHARE_USERNAME}:${_encoded_pass}@\1#")
        else
            _smb_url=$(echo "$_source" | sed 's#^//#smb://#')
        fi

        mount_smbfs $_opts "$_smb_url" "$_target"
    else
        # Linux mount
        _mount_opts="$_opts"

        if [ -n "$RSR_SHARE_USERNAME" ] && [ -n "$RSR_SHARE_PASSWORD" ]; then
            _creds_file=$(rsr_share_create_creds_file "$RSR_SHARE_USERNAME" "$RSR_SHARE_PASSWORD" "$RSR_SHARE_DOMAIN")
            _mount_opts="${_mount_opts:+$_mount_opts,}credentials=$_creds_file"

            # Mount and cleanup
            mount -t cifs "$_source" "$_target" -o "$_mount_opts"
            _result=$?
            rm -f "$_creds_file"
            return $_result
        else
            if [ -n "$_mount_opts" ]; then
                mount -t cifs "$_source" "$_target" -o "$_mount_opts"
            else
                mount -t cifs "$_source" "$_target"
            fi
        fi
    fi
}

# Internal: Mount NFS share
_rsr_mount_nfs() {
    _source="$1"
    _target="$2"
    _opts="$3"

    if [ "$(rsr_detect_os)" = "darwin" ]; then
        if [ -n "$_opts" ]; then
            mount -t nfs -o "$_opts" "$_source" "$_target"
        else
            mount -t nfs "$_source" "$_target"
        fi
    else
        if [ -n "$_opts" ]; then
            mount -t nfs -o "$_opts" "$_source" "$_target"
        else
            mount -t nfs "$_source" "$_target"
        fi
    fi
}

# Internal: Mount SSHFS share
_rsr_mount_sshfs() {
    _source="$1"
    _target="$2"
    _opts="$3"

    _sshfs_opts="-o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3"

    if [ "$(rsr_detect_os)" = "darwin" ]; then
        _sshfs_opts="$_sshfs_opts,volname=$(basename "$_target")"
    fi

    [ -n "$_opts" ] && _sshfs_opts="$_sshfs_opts,$_opts"

    sshfs "$_source" "$_target" $_sshfs_opts
}

# Internal: Mount WebDAV share
_rsr_mount_webdav() {
    _source="$1"
    _target="$2"
    _opts="$3"

    if [ "$(rsr_detect_os)" = "darwin" ]; then
        # macOS uses mount_webdav
        mount_webdav "$_source" "$_target"
    else
        # Linux uses davfs2
        if [ -n "$_opts" ]; then
            mount -t davfs -o "$_opts" "$_source" "$_target"
        else
            mount -t davfs "$_source" "$_target"
        fi
    fi
}

# Unmount a share
# Usage: rsr_share_unmount "/mnt/share" [force]
rsr_share_unmount() {
    _target="$1"
    _force="${2:-false}"

    if ! mountpoint -q "$_target" 2>/dev/null && ! mount | grep -q " on $_target "; then
        rsr_log_warn "Not mounted: $_target"
        return 0
    fi

    if [ "$_force" = "true" ] || [ "$_force" = "1" ]; then
        if [ "$(rsr_detect_os)" = "darwin" ]; then
            umount -f "$_target"
        else
            umount -l "$_target" || umount -f "$_target"
        fi
    else
        umount "$_target"
    fi
}

# =============================================================================
# Share Discovery
# =============================================================================

# Discover SMB shares on a host
# Usage: rsr_share_discover_smb "server"
rsr_share_discover_smb() {
    _server="$1"
    _username="${2:-}"

    if ! rsr_command_exists smbclient; then
        rsr_log_error "smbclient not found. Install samba-client."
        return "$RSR_EXIT_DEPENDENCY"
    fi

    if [ -n "$_username" ]; then
        smbclient -L "$_server" -U "$_username" -g 2>/dev/null | grep '^Disk|' | cut -d'|' -f2
    else
        smbclient -L "$_server" -N -g 2>/dev/null | grep '^Disk|' | cut -d'|' -f2
    fi
}

# Discover NFS exports on a host
# Usage: rsr_share_discover_nfs "server"
rsr_share_discover_nfs() {
    _server="$1"

    if ! rsr_command_exists showmount; then
        rsr_log_error "showmount not found. Install nfs-common."
        return "$RSR_EXIT_DEPENDENCY"
    fi

    showmount -e "$_server" 2>/dev/null | tail -n +2 | awk '{print $1}'
}

# Scan local network for SMB servers
# Usage: rsr_share_scan_network [subnet]
rsr_share_scan_network() {
    _subnet="${1:-}"

    # Try to auto-detect subnet if not provided
    if [ -z "$_subnet" ]; then
        if rsr_command_exists ip; then
            _subnet=$(ip route | grep 'scope link' | head -1 | awk '{print $1}')
        elif rsr_command_exists route; then
            _subnet=$(route -n get default 2>/dev/null | grep 'interface:' | awk '{print $2}')
        fi
    fi

    if rsr_command_exists nmap; then
        rsr_log_info "Scanning network for SMB shares..."
        nmap -p 445 --open "$_subnet" 2>/dev/null | grep 'Nmap scan report' | awk '{print $NF}' | tr -d '()'
    elif rsr_command_exists avahi-browse; then
        rsr_log_info "Discovering SMB services via mDNS..."
        avahi-browse -rt _smb._tcp 2>/dev/null | grep '=' | awk '{print $4}'
    else
        rsr_log_warn "Install nmap or avahi-daemon for network discovery"
        return "$RSR_EXIT_DEPENDENCY"
    fi
}

# =============================================================================
# Share Status
# =============================================================================

# List all mounted network shares
# Usage: rsr_share_list_mounted
rsr_share_list_mounted() {
    if [ "$(rsr_detect_os)" = "darwin" ]; then
        mount | grep -E '(smbfs|nfs|webdav|sshfs|osxfuse)' || true
    else
        mount | grep -E '(cifs|nfs|davfs|fuse\.sshfs)' || true
    fi
}

# Check if a path is a mounted share
# Usage: rsr_share_is_mounted "/mnt/share"
rsr_share_is_mounted() {
    _path="$1"
    mount | grep -q " on $_path "
}

# Get mount info for a path
# Usage: rsr_share_mount_info "/mnt/share"
rsr_share_mount_info() {
    _path="$1"
    mount | grep " on $_path " | head -1
}

# Test share connectivity
# Usage: rsr_share_test "//server/share"
rsr_share_test() {
    _source="$1"
    _type=$(rsr_share_detect_type "$_source") || return 1

    case "$_type" in
        smb|cifs)
            rsr_share_parse_smb "$_source"
            # Test SMB port
            rsr_test_port "$RSR_SHARE_SERVER" 445 2
            ;;
        nfs)
            rsr_share_parse_nfs "$_source"
            # Test NFS ports
            rsr_test_port "$RSR_SHARE_SERVER" 2049 2 || rsr_test_port "$RSR_SHARE_SERVER" 111 2
            ;;
        sshfs)
            rsr_share_parse_sshfs "$_source"
            # Test SSH port
            rsr_test_port "$RSR_SHARE_SERVER" 22 2
            ;;
        webdav)
            # Test HTTP(S) connectivity
            if echo "$_source" | grep -q '^https'; then
                _port=443
            else
                _port=80
            fi
            _host=$(echo "$_source" | sed -E 's#^https?://([^/:]+).*#\1#')
            rsr_test_port "$_host" "$_port" 2
            ;;
    esac
}

# =============================================================================
# Persistent Configuration
# =============================================================================

# Save share configuration
# Usage: rsr_share_save "name" "source" "target" "type" "options"
rsr_share_save() {
    _name="$1"
    _source="$2"
    _target="$3"
    _type="${4:-}"
    _opts="${5:-}"
    _automount="${6:-false}"

    rsr_shares_init

    [ -z "$_type" ] && _type=$(rsr_share_detect_type "$_source")

    # Create JSON entry (using simple string manipulation for POSIX compliance)
    _entry="{\"name\":\"$_name\",\"source\":\"$_source\",\"target\":\"$_target\",\"type\":\"$_type\",\"options\":\"$_opts\",\"automount\":$_automount}"

    # Check if jq is available for proper JSON handling
    if rsr_command_exists jq; then
        # Remove existing entry with same name and add new one
        _tmp=$(mktemp)
        jq --arg name "$_name" 'del(.shares[] | select(.name == $name))' "$RSR_SHARE_SAVED_FILE" > "$_tmp"
        jq --argjson entry "$_entry" '.shares += [$entry]' "$_tmp" > "$RSR_SHARE_SAVED_FILE"
        rm -f "$_tmp"
    else
        rsr_log_warn "jq not found - using basic JSON storage"
        # Fallback: append to simple format
        echo "$_entry" >> "${RSR_SHARE_SAVED_FILE}.lines"
    fi

    rsr_log_ok "Share '$_name' saved"
}

# Load saved share configuration
# Usage: rsr_share_load "name"
rsr_share_load() {
    _name="$1"

    if rsr_command_exists jq; then
        _share=$(jq -r --arg name "$_name" '.shares[] | select(.name == $name)' "$RSR_SHARE_SAVED_FILE" 2>/dev/null)

        if [ -n "$_share" ] && [ "$_share" != "null" ]; then
            RSR_LOADED_SHARE_SOURCE=$(echo "$_share" | jq -r '.source')
            RSR_LOADED_SHARE_TARGET=$(echo "$_share" | jq -r '.target')
            RSR_LOADED_SHARE_TYPE=$(echo "$_share" | jq -r '.type')
            RSR_LOADED_SHARE_OPTIONS=$(echo "$_share" | jq -r '.options')
            RSR_LOADED_SHARE_AUTOMOUNT=$(echo "$_share" | jq -r '.automount')
            export RSR_LOADED_SHARE_SOURCE RSR_LOADED_SHARE_TARGET RSR_LOADED_SHARE_TYPE RSR_LOADED_SHARE_OPTIONS RSR_LOADED_SHARE_AUTOMOUNT
            return 0
        fi
    fi

    return 1
}

# List saved shares
# Usage: rsr_share_list_saved
rsr_share_list_saved() {
    if rsr_command_exists jq; then
        jq -r '.shares[] | "\(.name)\t\(.source)\t\(.target)\t\(.type)"' "$RSR_SHARE_SAVED_FILE" 2>/dev/null
    fi
}

# Delete saved share
# Usage: rsr_share_delete "name"
rsr_share_delete() {
    _name="$1"

    if rsr_command_exists jq; then
        _tmp=$(mktemp)
        jq --arg name "$_name" 'del(.shares[] | select(.name == $name))' "$RSR_SHARE_SAVED_FILE" > "$_tmp"
        mv "$_tmp" "$RSR_SHARE_SAVED_FILE"
        rsr_log_ok "Share '$_name' deleted"
    fi

    # Also delete credentials if they exist
    rsr_share_delete_credentials "$_name"
}

# =============================================================================
# Automount Generation
# =============================================================================

# Generate fstab entry
# Usage: rsr_share_generate_fstab "name"
rsr_share_generate_fstab() {
    _name="$1"

    rsr_share_load "$_name" || {
        rsr_log_error "Share not found: $_name"
        return 1
    }

    _source="$RSR_LOADED_SHARE_SOURCE"
    _target="$RSR_LOADED_SHARE_TARGET"
    _type="$RSR_LOADED_SHARE_TYPE"
    _opts="$RSR_LOADED_SHARE_OPTIONS"

    case "$_type" in
        smb|cifs)
            _fs_type="cifs"
            _default_opts="credentials=${RSR_SHARE_CONFIG_DIR}/creds/${_name}.creds,iocharset=utf8,file_mode=0644,dir_mode=0755,nofail,_netdev"
            ;;
        nfs)
            _fs_type="nfs"
            _default_opts="defaults,nofail,_netdev"
            ;;
        sshfs)
            _fs_type="fuse.sshfs"
            _default_opts="defaults,nofail,_netdev,reconnect,ServerAliveInterval=15"
            ;;
        webdav)
            _fs_type="davfs"
            _default_opts="defaults,nofail,_netdev"
            ;;
    esac

    [ -n "$_opts" ] && _default_opts="${_default_opts},${_opts}"

    echo "# RSR Share: $_name"
    echo "$_source  $_target  $_fs_type  $_default_opts  0  0"
}

# Generate systemd mount unit
# Usage: rsr_share_generate_systemd "name"
rsr_share_generate_systemd() {
    _name="$1"

    rsr_share_load "$_name" || {
        rsr_log_error "Share not found: $_name"
        return 1
    }

    _source="$RSR_LOADED_SHARE_SOURCE"
    _target="$RSR_LOADED_SHARE_TARGET"
    _type="$RSR_LOADED_SHARE_TYPE"
    _opts="$RSR_LOADED_SHARE_OPTIONS"

    # Convert mount path to systemd unit name
    _unit_name=$(echo "$_target" | sed 's#^/##; s#/#-#g')

    case "$_type" in
        smb|cifs)
            _fs_type="cifs"
            _default_opts="credentials=${RSR_SHARE_CONFIG_DIR}/creds/${_name}.creds,iocharset=utf8"
            ;;
        nfs)
            _fs_type="nfs"
            _default_opts="defaults"
            ;;
        sshfs)
            _fs_type="fuse.sshfs"
            _default_opts="reconnect,ServerAliveInterval=15"
            ;;
        webdav)
            _fs_type="davfs"
            _default_opts="defaults"
            ;;
    esac

    [ -n "$_opts" ] && _default_opts="${_default_opts},${_opts}"

    cat << EOF
# ${_unit_name}.mount - Generated by RSR Share Management
# Install to: /etc/systemd/system/${_unit_name}.mount
# Enable with: systemctl enable --now ${_unit_name}.mount

[Unit]
Description=RSR Network Share: $_name
After=network-online.target
Wants=network-online.target

[Mount]
What=$_source
Where=$_target
Type=$_fs_type
Options=$_default_opts
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF
}

# Generate autofs entry
# Usage: rsr_share_generate_autofs "name"
rsr_share_generate_autofs() {
    _name="$1"

    rsr_share_load "$_name" || {
        rsr_log_error "Share not found: $_name"
        return 1
    }

    _source="$RSR_LOADED_SHARE_SOURCE"
    _type="$RSR_LOADED_SHARE_TYPE"
    _opts="$RSR_LOADED_SHARE_OPTIONS"

    case "$_type" in
        smb|cifs)
            _fs_opts="-fstype=cifs,credentials=${RSR_SHARE_CONFIG_DIR}/creds/${_name}.creds"
            ;;
        nfs)
            _fs_opts="-fstype=nfs"
            ;;
        sshfs)
            _fs_opts="-fstype=fuse.sshfs"
            ;;
    esac

    [ -n "$_opts" ] && _fs_opts="${_fs_opts},${_opts}"

    echo "# Add to /etc/auto.master: /mnt/auto /etc/auto.rsr"
    echo "# Add to /etc/auto.rsr:"
    echo "$_name  $_fs_opts  :$_source"
}

