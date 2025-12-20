#!/usr/bin/env bash
# ============================================================================
# Linux Platform Adapter
# Linux-specific implementations and optimizations
# ============================================================================

set -uo pipefail

# Prevent double-sourcing
[[ "${_DECLUTTER_ADAPTER_LINUX_LOADED:-}" == "true" ]] && return 0
_DECLUTTER_ADAPTER_LINUX_LOADED="true"

# Only load on Linux
[[ "$(uname -s)" != "Linux" ]] && return 0

# =============================================================================
# Linux Trash Operations
# =============================================================================

# XDG-compliant trash implementation
linux_trash() {
    local file=$1

    # Prefer gio, then trash-cli
    if command -v gio &>/dev/null; then
        gio trash "$file"
    elif command -v trash-put &>/dev/null; then
        trash-put "$file"
    else
        # Manual XDG trash implementation
        local trash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"
        local trash_files="$trash_dir/files"
        local trash_info="$trash_dir/info"

        mkdir -p "$trash_files" "$trash_info"

        local basename
        basename=$(basename "$file")
        local abs_path
        abs_path=$(realpath "$file")
        local timestamp
        timestamp=$(date +%Y-%m-%dT%H:%M:%S)

        # Create .trashinfo file
        cat > "$trash_info/${basename}.trashinfo" << EOF
[Trash Info]
Path=$abs_path
DeletionDate=$timestamp
EOF

        mv "$file" "$trash_files/"
    fi
}

# Empty trash
linux_empty_trash() {
    local trash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"

    if command -v gio &>/dev/null; then
        gio trash --empty
    elif command -v trash-empty &>/dev/null; then
        trash-empty
    else
        rm -rf "$trash_dir/files"/* "$trash_dir/info"/*
    fi
}

# Get trash size
linux_trash_size() {
    local trash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files"
    du -sh "$trash_dir" 2>/dev/null | cut -f1
}

# =============================================================================
# Linux System Cleanup
# =============================================================================

# Get distribution info
linux_get_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif command -v lsb_release &>/dev/null; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# Get package manager cleanup locations
linux_get_package_cache() {
    local distro
    distro=$(linux_get_distro)

    case "$distro" in
        ubuntu|debian|pop|linuxmint)
            echo "/var/cache/apt/archives"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            echo "/var/cache/dnf"
            echo "/var/cache/yum"
            ;;
        arch|manjaro|endeavouros)
            echo "/var/cache/pacman/pkg"
            ;;
        opensuse*)
            echo "/var/cache/zypp"
            ;;
    esac
}

# Clean package manager cache
linux_clean_package_cache() {
    local distro
    distro=$(linux_get_distro)

    case "$distro" in
        ubuntu|debian|pop|linuxmint)
            sudo apt clean 2>/dev/null
            ;;
        fedora|rhel|centos|rocky|almalinux)
            sudo dnf clean all 2>/dev/null
            ;;
        arch|manjaro|endeavouros)
            sudo paccache -r 2>/dev/null
            ;;
    esac
}

# Get journalctl log size
linux_journal_size() {
    journalctl --disk-usage 2>/dev/null | grep -oP '\d+(\.\d+)?[KMGT]?'
}

# Clean old journal logs
linux_clean_journal() {
    local max_age=${1:-"7d"}
    sudo journalctl --vacuum-time="$max_age" 2>/dev/null
}

# =============================================================================
# Linux-Specific Cleanup Locations
# =============================================================================

linux_get_cleanup_locations() {
    local cleanup_type=${1:-"all"}

    case "$cleanup_type" in
        caches)
            echo "${XDG_CACHE_HOME:-$HOME/.cache}"
            echo "/var/cache"
            ;;
        logs)
            echo "/var/log"
            echo "$HOME/.local/share/logs"
            ;;
        thumbnails)
            echo "${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails"
            ;;
        snap)
            echo "/var/lib/snapd/cache"
            echo "$HOME/snap"
            ;;
        flatpak)
            echo "$HOME/.var/app"
            echo "/var/lib/flatpak"
            ;;
        all)
            linux_get_cleanup_locations "caches"
            linux_get_cleanup_locations "logs"
            linux_get_cleanup_locations "thumbnails"
            ;;
    esac
}

# =============================================================================
# Linux Desktop Integration
# =============================================================================

# Send desktop notification
linux_notify() {
    local title=$1
    local message=$2
    local icon=${3:-"dialog-information"}

    if command -v notify-send &>/dev/null; then
        notify-send -i "$icon" "$title" "$message"
    fi
}

# Get current desktop environment
linux_get_desktop() {
    echo "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"
}

# =============================================================================
# Linux File System
# =============================================================================

# Find files by inode (useful for hard links)
linux_find_by_inode() {
    local inode=$1
    local path=${2:-.}

    find "$path" -inum "$inode" 2>/dev/null
}

# Get file system type
linux_get_fs_type() {
    local path=$1
    df -T "$path" 2>/dev/null | awk 'NR==2 {print $2}'
}

# Check if path is on SSD
linux_is_ssd() {
    local path=$1
    local device
    device=$(df "$path" 2>/dev/null | awk 'NR==2 {print $1}' | sed 's/[0-9]*$//')
    device=$(basename "$device")

    local rotational="/sys/block/$device/queue/rotational"
    if [[ -f "$rotational" ]]; then
        [[ $(cat "$rotational") -eq 0 ]]
    else
        return 1
    fi
}

# =============================================================================
# Export
# =============================================================================

export -f linux_trash linux_empty_trash linux_trash_size
export -f linux_get_distro linux_get_package_cache linux_clean_package_cache
export -f linux_journal_size linux_clean_journal
export -f linux_get_cleanup_locations
export -f linux_notify linux_get_desktop
export -f linux_find_by_inode linux_get_fs_type linux_is_ssd
