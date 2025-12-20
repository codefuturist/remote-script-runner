#!/usr/bin/env bash
#
# Declutter - System Cleanup Preset
# Remove system caches, temp files, and logs
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_PRESET_SYSTEM_LOADED:-}" ]] && return 0
readonly _DECLUTTER_PRESET_SYSTEM_LOADED=1

# =============================================================================
# Dependencies
# =============================================================================

# Module directory
_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/utils.sh
source "$_MODULE_DIR/../core/utils.sh"
# shellcheck source=../core/logger.sh
source "$_MODULE_DIR/../core/logger.sh"
# shellcheck source=../core/config.sh
source "$_MODULE_DIR/../core/config.sh"

# =============================================================================
# Preset Registration
# =============================================================================

if declare -F register_preset &>/dev/null; then
    register_preset "system" "preset_system" "System cleanup"
fi

# =============================================================================
# System Cleanup Locations
# =============================================================================

# macOS specific
declare -a MACOS_CACHE_DIRS=(
    "$HOME/Library/Caches"
    "$HOME/Library/Logs"
    "$HOME/Library/Application Support/Slack/Cache"
    "$HOME/Library/Application Support/Slack/Service Worker/CacheStorage"
    "$HOME/Library/Application Support/discord/Cache"
    "$HOME/Library/Application Support/Code/CachedData"
    "$HOME/Library/Application Support/Code/CachedExtensionVSIXs"
    "$HOME/Library/Application Support/Google/Chrome/Default/Cache"
    "$HOME/Library/Application Support/Firefox/Profiles/*/cache2"
)

# Linux specific
declare -a LINUX_CACHE_DIRS=(
    "$HOME/.cache"
    "$HOME/.local/share/Trash"
    "/tmp"
    "/var/tmp"
)

# Common patterns
declare -a SYSTEM_JUNK_PATTERNS=(
    ".DS_Store"
    "Thumbs.db"
    "desktop.ini"
    "*.tmp"
    "*.temp"
    "*.bak"
    "*.old"
    "*~"
    "*.log"
    "*.swp"
    "*.swo"
)

# =============================================================================
# Preset Execution
# =============================================================================

# Main system cleanup
preset_system() {
    local target_path="${1:-$HOME}"

    print_header "System Cleanup"

    if is_dry_run; then
        show_dry_run_banner
    fi

    local total_cleaned=0
    local total_size=0

    # Clean based on OS
    if is_macos; then
        _clean_macos_caches total_cleaned total_size
    elif is_linux; then
        _clean_linux_caches total_cleaned total_size
    fi

    # Clean common junk files
    _clean_junk_files "$target_path" total_cleaned total_size

    # Summary
    print_divider
    log_success "System cleanup complete"
    print_kv "Items cleaned" "$total_cleaned"
    print_kv "Space freed" "$(format_bytes "$total_size")"
}

# =============================================================================
# macOS Cleanup
# =============================================================================

_clean_macos_caches() {
    local -n cleaned="$1"
    local -n size="$2"

    print_section "macOS Cache Cleanup"

    for cache_dir in "${MACOS_CACHE_DIRS[@]}"; do
        # Expand glob patterns
        for expanded_dir in $cache_dir; do
            [[ -d "$expanded_dir" ]] || continue

            local dir_size
            dir_size="$(du -sk "$expanded_dir" 2>/dev/null | cut -f1 || echo 0)"
            dir_size=$((dir_size * 1024))

            # Skip small directories
            ((dir_size < 1048576)) && continue  # < 1MB

            log_info "$(format_bytes "$dir_size")  $expanded_dir"

            if is_dry_run; then
                dry_run_action "clean" "$expanded_dir"
                ((cleaned++))
                ((size += dir_size))
            elif is_interactive; then
                if confirm "Clean $(basename "$expanded_dir")?"; then
                    _safe_clean_dir "$expanded_dir"
                    ((cleaned++))
                    ((size += dir_size))
                fi
            fi
        done
    done
}

# =============================================================================
# Linux Cleanup
# =============================================================================

_clean_linux_caches() {
    local -n cleaned="$1"
    local -n size="$2"

    print_section "Linux Cache Cleanup"

    for cache_dir in "${LINUX_CACHE_DIRS[@]}"; do
        [[ -d "$cache_dir" ]] || continue

        local dir_size
        dir_size="$(du -sk "$cache_dir" 2>/dev/null | cut -f1 || echo 0)"
        dir_size=$((dir_size * 1024))

        # Skip small directories
        ((dir_size < 1048576)) && continue  # < 1MB

        log_info "$(format_bytes "$dir_size")  $cache_dir"

        if is_dry_run; then
            dry_run_action "clean" "$cache_dir"
            ((cleaned++))
            ((size += dir_size))
        elif is_interactive; then
            if confirm "Clean $(basename "$cache_dir")?"; then
                _safe_clean_dir "$cache_dir"
                ((cleaned++))
                ((size += dir_size))
            fi
        fi
    done
}

# =============================================================================
# Junk File Cleanup
# =============================================================================

_clean_junk_files() {
    local path="$1"
    local -n cleaned="$2"
    local -n size="$3"

    print_section "Junk Files"

    local junk_count=0
    local junk_size=0
    local -a junk_files=()

    for pattern in "${SYSTEM_JUNK_PATTERNS[@]}"; do
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            [[ -f "$file" ]] || continue

            local file_size
            file_size="$(get_file_size "$file")"

            junk_files+=("$file")
            ((junk_count++))
            ((junk_size += file_size))
        done < <(find "$path" -name "$pattern" -type f 2>/dev/null | head -1000)
    done

    if ((junk_count == 0)); then
        log_success "No junk files found"
        return
    fi

    print_kv "Junk files found" "$junk_count"
    print_kv "Total size" "$(format_bytes "$junk_size")"

    if is_interactive && ! is_dry_run; then
        if confirm "Delete $junk_count junk files?"; then
            for file in "${junk_files[@]}"; do
                rm -f "$file" 2>/dev/null && ((cleaned++))
            done
            ((size += junk_size))
            log_success "Deleted $junk_count junk files"
        fi
    elif is_dry_run; then
        log_info "[DRY-RUN] Would delete $junk_count junk files"
        ((cleaned += junk_count))
        ((size += junk_size))
    fi
}

# =============================================================================
# Safe Directory Cleaning
# =============================================================================

_safe_clean_dir() {
    local dir="$1"

    # Safety check
    case "$dir" in
        /|/bin|/sbin|/usr|/etc|/var|/System|/Library|/Applications)
            log_error "Refusing to clean system directory: $dir"
            return 1
            ;;
        "$HOME"|"$HOME/"|"$HOME/Documents"|"$HOME/Desktop"|"$HOME/Downloads")
            log_error "Refusing to clean important directory: $dir"
            return 1
            ;;
    esac

    # Clean contents, not the directory itself
    find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} \; 2>/dev/null
    log_success "Cleaned: $dir"
}

# =============================================================================
# Specialized Cleanups
# =============================================================================

# Clean browser caches
preset_system_browsers() {
    print_header "Browser Cache Cleanup"

    local -a browser_caches=()

    # Chrome
    browser_caches+=(
        "$HOME/Library/Caches/Google/Chrome"
        "$HOME/Library/Application Support/Google/Chrome/Default/Cache"
        "$HOME/.cache/google-chrome"
    )

    # Firefox
    browser_caches+=(
        "$HOME/Library/Caches/Firefox"
        "$HOME/.cache/mozilla"
    )

    # Safari
    browser_caches+=(
        "$HOME/Library/Caches/com.apple.Safari"
    )

    local total_size=0
    local cleaned=0

    for cache in "${browser_caches[@]}"; do
        # Expand globs
        for expanded in $cache; do
            [[ -d "$expanded" ]] || continue

            local size
            size="$(du -sk "$expanded" 2>/dev/null | cut -f1 || echo 0)"
            size=$((size * 1024))

            log_info "$(format_bytes "$size")  $(basename "$(dirname "$expanded")")"

            if ! is_dry_run; then
                rm -rf "$expanded"/* 2>/dev/null
                ((cleaned++))
                ((total_size += size))
            fi
        done
    done

    log_success "Cleaned browser caches: $(format_bytes "$total_size")"
}

# Clean application caches
preset_system_apps() {
    print_header "Application Cache Cleanup"

    local cache_dir="$HOME/Library/Caches"
    [[ -d "$cache_dir" ]] || cache_dir="$HOME/.cache"

    if [[ ! -d "$cache_dir" ]]; then
        log_info "No cache directory found"
        return
    fi

    # List largest caches
    log_step "Largest caches:"

    du -sk "$cache_dir"/* 2>/dev/null | sort -rn | head -20 | while read -r size name; do
        local bytes=$((size * 1024))
        printf "  %10s  %s\n" "$(format_bytes "$bytes")" "$(basename "$name")"
    done
}

# Clean temporary files
preset_system_temp() {
    print_header "Temporary Files Cleanup"

    local -a temp_dirs=(
        "/tmp"
        "/var/tmp"
        "$HOME/tmp"
        "$TMPDIR"
    )

    local total_size=0

    for temp_dir in "${temp_dirs[@]}"; do
        [[ -d "$temp_dir" ]] || continue

        local size
        size="$(du -sk "$temp_dir" 2>/dev/null | cut -f1 || echo 0)"
        size=$((size * 1024))

        ((total_size += size))

        log_info "$(format_bytes "$size")  $temp_dir"
    done

    print_kv "Total temp files" "$(format_bytes "$total_size")"

    if is_interactive && ! is_dry_run; then
        if confirm "Clean temporary files?"; then
            for temp_dir in "${temp_dirs[@]}"; do
                [[ -d "$temp_dir" ]] || continue
                # Only clean old files (> 7 days)
                find "$temp_dir" -type f -mtime +7 -delete 2>/dev/null
            done
            log_success "Cleaned old temporary files"
        fi
    fi
}

# Clean logs
preset_system_logs() {
    print_header "Log Files Cleanup"

    local -a log_dirs=(
        "$HOME/Library/Logs"
        "/var/log"
        "$HOME/.local/share/*/logs"
    )

    local total_size=0
    local log_count=0

    for log_dir in "${log_dirs[@]}"; do
        for expanded in $log_dir; do
            [[ -d "$expanded" ]] || continue

            while IFS= read -r log_file; do
                [[ -f "$log_file" ]] || continue

                local size
                size="$(get_file_size "$log_file")"
                ((total_size += size))
                ((log_count++))
            done < <(find "$expanded" -name "*.log" -type f 2>/dev/null)
        done
    done

    print_kv "Log files found" "$log_count"
    print_kv "Total size" "$(format_bytes "$total_size")"

    if is_interactive && ! is_dry_run; then
        if confirm "Delete old log files (> 30 days)?"; then
            for log_dir in "${log_dirs[@]}"; do
                for expanded in $log_dir; do
                    [[ -d "$expanded" ]] || continue
                    find "$expanded" -name "*.log" -type f -mtime +30 -delete 2>/dev/null
                done
            done
            log_success "Cleaned old log files"
        fi
    fi
}
