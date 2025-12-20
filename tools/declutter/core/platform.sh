#!/usr/bin/env bash
# ============================================================================
# Platform Abstraction Layer
# Cross-platform utilities for Unix/macOS/Windows compatibility
# ============================================================================

set -euo pipefail

# Detect platform
detect_platform() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)   echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

PLATFORM=$(detect_platform)
export PLATFORM

# Platform-specific trash locations
get_trash_path() {
    case "$PLATFORM" in
        macos)  echo "$HOME/.Trash" ;;
        linux)  echo "${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files" ;;
        windows) echo "$USERPROFILE/AppData/Local/Temp/Declutter_Trash" ;;
        *)      echo "/tmp/declutter_trash" ;;
    esac
}

# Move to trash (cross-platform)
move_to_trash() {
    local file="$1"
    local trash_path
    trash_path=$(get_trash_path)

    mkdir -p "$trash_path"

    case "$PLATFORM" in
        macos)
            if command -v trash &>/dev/null; then
                trash "$file"
            else
                mv "$file" "$trash_path/"
            fi
            ;;
        linux)
            if command -v gio &>/dev/null; then
                gio trash "$file"
            elif command -v trash-put &>/dev/null; then
                trash-put "$file"
            else
                mv "$file" "$trash_path/"
            fi
            ;;
        *)
            mv "$file" "$trash_path/"
            ;;
    esac
}

# Get file access time (cross-platform)
get_access_time() {
    local file="$1"
    case "$PLATFORM" in
        macos)  stat -f "%a" "$file" 2>/dev/null || echo "0" ;;
        linux)  stat -c "%X" "$file" 2>/dev/null || echo "0" ;;
        *)      stat -c "%X" "$file" 2>/dev/null || echo "0" ;;
    esac
}

# Get file modification time (cross-platform)
get_mod_time() {
    local file="$1"
    case "$PLATFORM" in
        macos)  stat -f "%m" "$file" 2>/dev/null || echo "0" ;;
        linux)  stat -c "%Y" "$file" 2>/dev/null || echo "0" ;;
        *)      stat -c "%Y" "$file" 2>/dev/null || echo "0" ;;
    esac
}

# Get file size (cross-platform)
get_file_size() {
    local file="$1"
    case "$PLATFORM" in
        macos)  stat -f "%z" "$file" 2>/dev/null || echo "0" ;;
        linux)  stat -c "%s" "$file" 2>/dev/null || echo "0" ;;
        *)      stat -c "%s" "$file" 2>/dev/null || echo "0" ;;
    esac
}

# Human readable size
human_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        printf "%.2f GB" "$(echo "scale=2; $bytes / 1073741824" | bc)"
    elif (( bytes >= 1048576 )); then
        printf "%.2f MB" "$(echo "scale=2; $bytes / 1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.2f KB" "$(echo "scale=2; $bytes / 1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

# Open file manager (cross-platform)
open_file_manager() {
    local path="$1"
    case "$PLATFORM" in
        macos)  open "$path" ;;
        linux)  xdg-open "$path" 2>/dev/null || nautilus "$path" 2>/dev/null ;;
        windows) explorer.exe "$path" ;;
    esac
}

# Path normalization
normalize_path() {
    local path="$1"
    case "$PLATFORM" in
        windows)
            # Convert Unix paths to Windows paths if needed
            echo "$path" | sed 's|/|\\|g'
            ;;
        *)
            realpath "$path" 2>/dev/null || echo "$path"
            ;;
    esac
}

export -f detect_platform get_trash_path move_to_trash get_access_time
export -f get_mod_time get_file_size human_size open_file_manager normalize_path
