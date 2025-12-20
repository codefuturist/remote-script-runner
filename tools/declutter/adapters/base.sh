#!/usr/bin/env bash
# ============================================================================
# Base Platform Adapter
# Provides platform-agnostic implementations with fallbacks
# ============================================================================

set -uo pipefail

# Prevent double-sourcing
[[ "${_DECLUTTER_ADAPTER_BASE_LOADED:-}" == "true" ]] && return 0
_DECLUTTER_ADAPTER_BASE_LOADED="true"

# =============================================================================
# Platform Detection
# =============================================================================

detect_platform() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)   echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        FreeBSD*) echo "freebsd" ;;
        *)        echo "unix" ;;
    esac
}

PLATFORM="${PLATFORM:-$(detect_platform)}"
export PLATFORM

# =============================================================================
# Trash Operations
# =============================================================================

get_trash_path() {
    case "$PLATFORM" in
        macos)   echo "$HOME/.Trash" ;;
        linux)   echo "${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files" ;;
        windows) echo "${USERPROFILE:-$HOME}/AppData/Local/Temp/Declutter_Trash" ;;
        *)       echo "/tmp/declutter_trash_$$" ;;
    esac
}

move_to_trash() {
    local file=$1
    local trash_path
    trash_path=$(get_trash_path)

    mkdir -p "$trash_path"

    # Try native trash commands first
    case "$PLATFORM" in
        macos)
            if command -v trash &>/dev/null; then
                trash "$file" && return 0
            fi
            ;;
        linux)
            if command -v gio &>/dev/null; then
                gio trash "$file" 2>/dev/null && return 0
            elif command -v trash-put &>/dev/null; then
                trash-put "$file" && return 0
            fi
            ;;
    esac

    # Fallback: move to trash directory
    local basename
    basename=$(basename "$file")
    local dest="$trash_path/${basename}.$(date +%s)"
    mv "$file" "$dest"
}

restore_from_trash() {
    local filename=$1
    local dest=${2:-$(pwd)}
    local trash_path
    trash_path=$(get_trash_path)

    local source="$trash_path/$filename"
    if [[ -e "$source" ]]; then
        mv "$source" "$dest/"
        return 0
    fi

    return 1
}

# =============================================================================
# File Metadata Operations
# =============================================================================

get_file_size() {
    local file=$1

    case "$PLATFORM" in
        macos)  stat -f "%z" "$file" 2>/dev/null ;;
        *)      stat -c "%s" "$file" 2>/dev/null ;;
    esac
}

get_access_time() {
    local file=$1

    case "$PLATFORM" in
        macos)  stat -f "%a" "$file" 2>/dev/null ;;
        *)      stat -c "%X" "$file" 2>/dev/null ;;
    esac
}

get_mod_time() {
    local file=$1

    case "$PLATFORM" in
        macos)  stat -f "%m" "$file" 2>/dev/null ;;
        *)      stat -c "%Y" "$file" 2>/dev/null ;;
    esac
}

get_creation_time() {
    local file=$1

    case "$PLATFORM" in
        macos)  stat -f "%B" "$file" 2>/dev/null ;;
        linux)  stat -c "%W" "$file" 2>/dev/null ;;
        *)      get_mod_time "$file" ;;  # fallback
    esac
}

# =============================================================================
# System Integration
# =============================================================================

open_file_manager() {
    local path=$1

    case "$PLATFORM" in
        macos)   open "$path" ;;
        linux)   xdg-open "$path" 2>/dev/null || nautilus "$path" 2>/dev/null ;;
        windows) explorer.exe "$path" ;;
        *)       echo "Cannot open file manager on this platform" >&2 ;;
    esac
}

open_file() {
    local file=$1

    case "$PLATFORM" in
        macos)   open "$file" ;;
        linux)   xdg-open "$file" 2>/dev/null ;;
        windows) start "$file" ;;
        *)       echo "Cannot open file on this platform" >&2 ;;
    esac
}

# =============================================================================
# Path Operations
# =============================================================================

get_home_dir() {
    echo "${HOME:-$(eval echo ~)}"
}

get_temp_dir() {
    echo "${TMPDIR:-/tmp}"
}

get_config_dir() {
    case "$PLATFORM" in
        macos)   echo "$HOME/Library/Application Support" ;;
        linux)   echo "${XDG_CONFIG_HOME:-$HOME/.config}" ;;
        windows) echo "${APPDATA:-$HOME/AppData/Roaming}" ;;
        *)       echo "$HOME/.config" ;;
    esac
}

get_cache_dir() {
    case "$PLATFORM" in
        macos)   echo "$HOME/Library/Caches" ;;
        linux)   echo "${XDG_CACHE_HOME:-$HOME/.cache}" ;;
        windows) echo "${LOCALAPPDATA:-$HOME/AppData/Local}/Temp" ;;
        *)       echo "$HOME/.cache" ;;
    esac
}

# =============================================================================
# System Cleanup Locations
# =============================================================================

get_system_temp_dirs() {
    case "$PLATFORM" in
        macos)
            echo "/private/var/folders"
            echo "$HOME/Library/Caches"
            echo "/tmp"
            ;;
        linux)
            echo "/tmp"
            echo "/var/tmp"
            echo "${XDG_CACHE_HOME:-$HOME/.cache}"
            ;;
        windows)
            echo "${TEMP:-/tmp}"
            echo "${LOCALAPPDATA:-$HOME/AppData/Local}/Temp"
            ;;
    esac
}

get_browser_cache_dirs() {
    case "$PLATFORM" in
        macos)
            echo "$HOME/Library/Caches/Google/Chrome"
            echo "$HOME/Library/Caches/Firefox"
            echo "$HOME/Library/Caches/com.apple.Safari"
            echo "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache"
            ;;
        linux)
            echo "$HOME/.cache/google-chrome"
            echo "$HOME/.cache/mozilla/firefox"
            echo "$HOME/.cache/chromium"
            echo "$HOME/.cache/BraveSoftware/Brave-Browser"
            ;;
        windows)
            echo "${LOCALAPPDATA:-$HOME/AppData/Local}/Google/Chrome/User Data/Default/Cache"
            echo "${LOCALAPPDATA:-$HOME/AppData/Local}/Mozilla/Firefox/Profiles"
            ;;
    esac
}

# =============================================================================
# Export
# =============================================================================

export PLATFORM

export -f detect_platform
export -f get_trash_path move_to_trash restore_from_trash
export -f get_file_size get_access_time get_mod_time get_creation_time
export -f open_file_manager open_file
export -f get_home_dir get_temp_dir get_config_dir get_cache_dir
export -f get_system_temp_dirs get_browser_cache_dirs
