#!/usr/bin/env bash
# ============================================================================
# macOS Platform Adapter
# macOS-specific implementations and optimizations
# ============================================================================

set -uo pipefail

# Prevent double-sourcing
[[ "${_DECLUTTER_ADAPTER_MACOS_LOADED:-}" == "true" ]] && return 0
_DECLUTTER_ADAPTER_MACOS_LOADED="true"

# Only load on macOS
[[ "$(uname -s)" != "Darwin" ]] && return 0

# =============================================================================
# macOS-Specific Trash Operations
# =============================================================================

# Use AppleScript for native Finder trash integration
macos_trash() {
    local file=$1
    local abs_path
    abs_path=$(cd "$(dirname "$file")" && pwd)/$(basename "$file")

    if command -v trash &>/dev/null; then
        trash "$abs_path"
    else
        osascript -e "tell application \"Finder\" to delete POSIX file \"$abs_path\"" 2>/dev/null
    fi
}

# Empty the Trash
macos_empty_trash() {
    osascript -e 'tell application "Finder" to empty trash' 2>/dev/null
}

# Get Trash size
macos_trash_size() {
    du -sh "$HOME/.Trash" 2>/dev/null | cut -f1
}

# =============================================================================
# macOS Metadata Operations
# =============================================================================

# Remove extended attributes
macos_remove_xattrs() {
    local file=$1
    xattr -c "$file" 2>/dev/null
}

# Get Spotlight metadata
macos_get_spotlight_metadata() {
    local file=$1
    mdls "$file" 2>/dev/null
}

# Check if file is in Time Machine backup
macos_is_time_machine_backup() {
    local file=$1
    [[ "$file" == *".MobileBackups"* || "$file" == *"Backups.backupdb"* ]]
}

# =============================================================================
# macOS System Cleanup
# =============================================================================

# Get macOS-specific cleanup locations
macos_get_cleanup_locations() {
    local cleanup_type=${1:-"all"}

    case "$cleanup_type" in
        caches)
            echo "$HOME/Library/Caches"
            echo "/Library/Caches"
            ;;
        logs)
            echo "$HOME/Library/Logs"
            echo "/var/log"
            echo "/Library/Logs"
            ;;
        derived_data)
            echo "$HOME/Library/Developer/Xcode/DerivedData"
            ;;
        ios_backups)
            echo "$HOME/Library/Application Support/MobileSync/Backup"
            ;;
        mail_downloads)
            echo "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
            ;;
        all)
            macos_get_cleanup_locations "caches"
            macos_get_cleanup_locations "logs"
            macos_get_cleanup_locations "derived_data"
            ;;
    esac
}

# Get size of Xcode derived data
macos_xcode_derived_data_size() {
    local derived_data="$HOME/Library/Developer/Xcode/DerivedData"
    if [[ -d "$derived_data" ]]; then
        du -sh "$derived_data" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

# Clean Xcode derived data
macos_clean_xcode() {
    local derived_data="$HOME/Library/Developer/Xcode/DerivedData"
    local archives="$HOME/Library/Developer/Xcode/Archives"

    if [[ -d "$derived_data" ]]; then
        log_info "Cleaning Xcode DerivedData..."
        rm -rf "$derived_data"/*
    fi
}

# =============================================================================
# macOS Spotlight Integration
# =============================================================================

# Find files using Spotlight (faster than find for indexed locations)
macos_spotlight_find() {
    local query=$1
    local path=${2:-$HOME}

    mdfind -onlyin "$path" "$query" 2>/dev/null
}

# Find files by kind
macos_find_by_kind() {
    local kind=$1  # e.g., "image", "movie", "music", "document"
    local path=${2:-$HOME}

    mdfind -onlyin "$path" "kMDItemContentTypeTree == 'public.$kind'" 2>/dev/null
}

# Find large files using Spotlight
macos_find_large_files() {
    local min_size_mb=${1:-100}
    local path=${2:-$HOME}
    local min_size_bytes=$((min_size_mb * 1048576))

    mdfind -onlyin "$path" "kMDItemFSSize > $min_size_bytes" 2>/dev/null
}

# =============================================================================
# macOS Disk Management
# =============================================================================

# Get APFS purgeable space
macos_purgeable_space() {
    df -H / 2>/dev/null | awk 'NR==2 {print $4}'
}

# Purge disk cache
macos_purge_cache() {
    sudo purge 2>/dev/null
}

# =============================================================================
# macOS Quarantine
# =============================================================================

# Remove quarantine attribute
macos_remove_quarantine() {
    local file=$1
    xattr -d com.apple.quarantine "$file" 2>/dev/null
}

# Check if file is quarantined
macos_is_quarantined() {
    local file=$1
    xattr -l "$file" 2>/dev/null | grep -q "com.apple.quarantine"
}

# =============================================================================
# Export
# =============================================================================

export -f macos_trash macos_empty_trash macos_trash_size
export -f macos_remove_xattrs macos_get_spotlight_metadata macos_is_time_machine_backup
export -f macos_get_cleanup_locations macos_xcode_derived_data_size macos_clean_xcode
export -f macos_spotlight_find macos_find_by_kind macos_find_large_files
export -f macos_purgeable_space
export -f macos_remove_quarantine macos_is_quarantined
