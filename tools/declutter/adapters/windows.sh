#!/usr/bin/env bash
# ============================================================================
# Windows Platform Adapter (Git Bash/WSL/MSYS2)
# Windows-specific implementations for bash environments on Windows
# ============================================================================

set -uo pipefail

# Prevent double-sourcing
[[ "${_DECLUTTER_ADAPTER_WINDOWS_LOADED:-}" == "true" ]] && return 0
_DECLUTTER_ADAPTER_WINDOWS_LOADED="true"

# Only load on Windows
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *) return 0 ;;
esac

# =============================================================================
# Path Conversion
# =============================================================================

# Convert Unix path to Windows path
to_windows_path() {
    local path=$1

    if command -v cygpath &>/dev/null; then
        cygpath -w "$path"
    else
        # Manual conversion for MINGW/MSYS
        echo "$path" | sed -e 's|^/\([a-zA-Z]\)/|\1:\\|' -e 's|/|\\|g'
    fi
}

# Convert Windows path to Unix path
to_unix_path() {
    local path=$1

    if command -v cygpath &>/dev/null; then
        cygpath -u "$path"
    else
        echo "$path" | sed -e 's|\\|/|g' -e 's|^\([a-zA-Z]\):|/\L\1|'
    fi
}

# =============================================================================
# Windows Trash Operations
# =============================================================================

# Move file to Windows Recycle Bin using PowerShell
windows_trash() {
    local file=$1
    local win_path
    win_path=$(to_windows_path "$file")

    powershell.exe -NoProfile -Command "
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            '$win_path',
            'OnlyErrorDialogs',
            'SendToRecycleBin'
        )
    " 2>/dev/null
}

# Empty Recycle Bin
windows_empty_trash() {
    powershell.exe -NoProfile -Command "
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    " 2>/dev/null
}

# Get Recycle Bin size
windows_trash_size() {
    powershell.exe -NoProfile -Command "
        (New-Object -ComObject Shell.Application).NameSpace(10).Items() |
        Measure-Object -Property Size -Sum |
        Select-Object -ExpandProperty Sum
    " 2>/dev/null
}

# =============================================================================
# Windows System Cleanup
# =============================================================================

# Get Windows temp directories
windows_get_temp_dirs() {
    local userprofile
    userprofile=$(to_unix_path "${USERPROFILE:-}")
    local localappdata
    localappdata=$(to_unix_path "${LOCALAPPDATA:-}")

    echo "$userprofile/AppData/Local/Temp"
    echo "/c/Windows/Temp"
    echo "$localappdata/Microsoft/Windows/INetCache"
    echo "$localappdata/Microsoft/Windows/Explorer"
}

# Clean Windows temp files
windows_clean_temp() {
    local temp_dirs
    temp_dirs=$(windows_get_temp_dirs)

    while IFS= read -r dir; do
        if [[ -d "$dir" ]]; then
            find "$dir" -type f -mtime +7 -delete 2>/dev/null || true
        fi
    done <<< "$temp_dirs"
}

# Run Windows Disk Cleanup
windows_disk_cleanup() {
    local drive=${1:-C}

    powershell.exe -NoProfile -Command "
        cleanmgr.exe /d $drive /sagerun:1
    " 2>/dev/null
}

# =============================================================================
# Windows-Specific Cleanup Locations
# =============================================================================

windows_get_cleanup_locations() {
    local cleanup_type=${1:-"all"}
    local userprofile
    userprofile=$(to_unix_path "${USERPROFILE:-$HOME}")
    local localappdata
    localappdata=$(to_unix_path "${LOCALAPPDATA:-$userprofile/AppData/Local}")

    case "$cleanup_type" in
        temp)
            echo "$localappdata/Temp"
            echo "/c/Windows/Temp"
            ;;
        browser)
            echo "$localappdata/Google/Chrome/User Data/Default/Cache"
            echo "$localappdata/Microsoft/Edge/User Data/Default/Cache"
            echo "$localappdata/Mozilla/Firefox/Profiles"
            ;;
        thumbnails)
            echo "$localappdata/Microsoft/Windows/Explorer"
            ;;
        windows_update)
            echo "/c/Windows/SoftwareDistribution/Download"
            ;;
        prefetch)
            echo "/c/Windows/Prefetch"
            ;;
        all)
            windows_get_cleanup_locations "temp"
            windows_get_cleanup_locations "browser"
            windows_get_cleanup_locations "thumbnails"
            ;;
    esac
}

# =============================================================================
# Windows File System
# =============================================================================

# Get Windows file attributes
windows_get_attributes() {
    local file=$1
    local win_path
    win_path=$(to_windows_path "$file")

    powershell.exe -NoProfile -Command "
        (Get-Item '$win_path' -Force).Attributes
    " 2>/dev/null
}

# Check if file is hidden
windows_is_hidden() {
    local attrs
    attrs=$(windows_get_attributes "$1")
    [[ "$attrs" == *"Hidden"* ]]
}

# Check if file is system file
windows_is_system() {
    local attrs
    attrs=$(windows_get_attributes "$1")
    [[ "$attrs" == *"System"* ]]
}

# Get Windows file owner
windows_get_owner() {
    local file=$1
    local win_path
    win_path=$(to_windows_path "$file")

    powershell.exe -NoProfile -Command "
        (Get-Acl '$win_path').Owner
    " 2>/dev/null
}

# =============================================================================
# Windows Desktop Integration
# =============================================================================

# Send Windows notification (requires BurntToast or similar)
windows_notify() {
    local title=$1
    local message=$2

    powershell.exe -NoProfile -Command "
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        \$template = '<toast><visual><binding template=\"ToastText02\"><text id=\"1\">$title</text><text id=\"2\">$message</text></binding></visual></toast>'
        \$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        \$xml.LoadXml(\$template)

        \$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Declutter')
        \$notifier.Show([Windows.UI.Notifications.ToastNotification]::new(\$xml))
    " 2>/dev/null || true
}

# Open file in default Windows application
windows_open() {
    local file=$1
    local win_path
    win_path=$(to_windows_path "$file")

    cmd.exe /c start "" "$win_path" 2>/dev/null
}

# =============================================================================
# Windows Drive Info
# =============================================================================

# Get drive free space
windows_drive_free_space() {
    local drive=${1:-C}

    powershell.exe -NoProfile -Command "
        (Get-PSDrive $drive).Free
    " 2>/dev/null
}

# List drives
windows_list_drives() {
    powershell.exe -NoProfile -Command "
        Get-PSDrive -PSProvider FileSystem | Select-Object Name, Used, Free | ConvertTo-Json
    " 2>/dev/null
}

# =============================================================================
# Export
# =============================================================================

export -f to_windows_path to_unix_path
export -f windows_trash windows_empty_trash windows_trash_size
export -f windows_get_temp_dirs windows_clean_temp windows_disk_cleanup
export -f windows_get_cleanup_locations
export -f windows_get_attributes windows_is_hidden windows_is_system windows_get_owner
export -f windows_notify windows_open
export -f windows_drive_free_space windows_list_drives
