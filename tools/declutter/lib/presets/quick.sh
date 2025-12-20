#!/usr/bin/env bash
#
# Declutter - Quick Cleanup Preset
# Fast cleanup of common issues
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_PRESET_QUICK_LOADED:-}" ]] && return 0
readonly _DECLUTTER_PRESET_QUICK_LOADED=1

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
    register_preset "quick" "preset_quick" "Quick cleanup"
    register_preset "fast" "preset_quick" "Quick cleanup (alias)"
fi

# =============================================================================
# Quick Cleanup
# =============================================================================

preset_quick() {
    local target_path="${1:-$PWD}"

    target_path="$(get_absolute_path "$target_path")"

    print_header "Quick Cleanup"
    log_step "Target: $target_path"

    if is_dry_run; then
        show_dry_run_banner
    fi

    local total_items=0
    local total_size=0

    # Step 1: Empty files
    print_section "1/4 Empty Files"
    local empty_files
    empty_files="$(find "$target_path" -type f -empty 2>/dev/null | wc -l | tr -d ' ')"

    if ((empty_files > 0)); then
        log_info "Found $empty_files empty files"
        if ! is_interactive || confirm "Delete empty files?"; then
            if ! is_dry_run; then
                find "$target_path" -type f -empty -delete 2>/dev/null
            fi
            ((total_items += empty_files))
            log_success "Cleaned $empty_files empty files"
        fi
    else
        log_success "No empty files found"
    fi

    # Step 2: Empty directories
    print_section "2/4 Empty Directories"
    local empty_dirs
    empty_dirs="$(find "$target_path" -type d -empty 2>/dev/null | wc -l | tr -d ' ')"

    if ((empty_dirs > 0)); then
        log_info "Found $empty_dirs empty directories"
        if ! is_interactive || confirm "Delete empty directories?"; then
            if ! is_dry_run; then
                find "$target_path" -type d -empty -delete 2>/dev/null
            fi
            ((total_items += empty_dirs))
            log_success "Cleaned $empty_dirs empty directories"
        fi
    else
        log_success "No empty directories found"
    fi

    # Step 3: System junk
    print_section "3/4 System Junk"
    local junk_patterns=(".DS_Store" "Thumbs.db" "desktop.ini" "*~" "*.swp")
    local junk_count=0

    for pattern in "${junk_patterns[@]}"; do
        local count
        count="$(find "$target_path" -name "$pattern" -type f 2>/dev/null | wc -l | tr -d ' ')"
        ((junk_count += count))
    done

    if ((junk_count > 0)); then
        log_info "Found $junk_count junk files"
        if ! is_interactive || confirm "Delete junk files?"; then
            for pattern in "${junk_patterns[@]}"; do
                if ! is_dry_run; then
                    find "$target_path" -name "$pattern" -type f -delete 2>/dev/null
                fi
            done
            ((total_items += junk_count))
            log_success "Cleaned $junk_count junk files"
        fi
    else
        log_success "No junk files found"
    fi

    # Step 4: Broken symlinks
    print_section "4/4 Broken Symlinks"
    local broken_links
    broken_links="$(find "$target_path" -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l | tr -d ' ')"

    if ((broken_links > 0)); then
        log_info "Found $broken_links broken symlinks"
        if ! is_interactive || confirm "Delete broken symlinks?"; then
            if ! is_dry_run; then
                find "$target_path" -type l ! -exec test -e {} \; -delete 2>/dev/null
            fi
            ((total_items += broken_links))
            log_success "Cleaned $broken_links broken symlinks"
        fi
    else
        log_success "No broken symlinks found"
    fi

    # Summary
    print_divider
    log_success "Quick cleanup complete!"
    print_kv "Items cleaned" "$total_items"
}

# =============================================================================
# Deep Cleanup
# =============================================================================

preset_deep() {
    local target_path="${1:-$PWD}"

    target_path="$(get_absolute_path "$target_path")"

    print_header "Deep Scan"
    log_step "Target: $target_path"
    log_warn "This may take a while for large directories..."

    if is_dry_run; then
        show_dry_run_banner
    fi

    print_divider

    local start_time
    start_time="$(timer_start)"

    # Run all scans
    print_section "1/6 Duplicates"
    if command -v czkawka_cli &>/dev/null; then
        local dup_result
        dup_result="$(scan_duplicates "$target_path" 2>/dev/null)"
        local dup_count
        dup_count="$(echo "$dup_result" | jq -r '.stats.total_groups // 0' 2>/dev/null)"
        local dup_size
        dup_size="$(echo "$dup_result" | jq -r '.stats.wasted_space // 0' 2>/dev/null)"
        print_kv "Duplicate groups" "$dup_count"
        print_kv "Wasted space" "$(format_bytes "$dup_size")"
    else
        log_info "Install czkawka for duplicate detection"
    fi

    print_section "2/6 Large Files"
    local large_result
    large_result="$(scan_large_files "$target_path" "100MB" 2>/dev/null)"
    local large_count
    large_count="$(echo "$large_result" | jq -r '.stats.total_files // 0' 2>/dev/null)"
    local large_size
    large_size="$(echo "$large_result" | jq -r '.stats.total_size // 0' 2>/dev/null)"
    print_kv "Large files (>100MB)" "$large_count"
    print_kv "Total size" "$(format_bytes "$large_size")"

    print_section "3/6 Old Files"
    local old_result
    old_result="$(scan_old_files "$target_path" 90 2>/dev/null)"
    local old_count
    old_count="$(echo "$old_result" | jq -r '.stats.total_files // 0' 2>/dev/null)"
    print_kv "Old files (>90 days)" "$old_count"

    print_section "4/6 Empty Items"
    local empty_files empty_dirs
    empty_files="$(find "$target_path" -type f -empty 2>/dev/null | wc -l | tr -d ' ')"
    empty_dirs="$(find "$target_path" -type d -empty 2>/dev/null | wc -l | tr -d ' ')"
    print_kv "Empty files" "$empty_files"
    print_kv "Empty directories" "$empty_dirs"

    print_section "5/6 Orphan Files"
    local orphan_result
    orphan_result="$(scan_orphans "$target_path" 2>/dev/null)"
    local orphan_count
    orphan_count="$(echo "$orphan_result" | jq -r '.stats.total // 0' 2>/dev/null)"
    print_kv "Orphan/junk files" "$orphan_count"

    print_section "6/6 Directory Analysis"
    local total_size file_count dir_count
    total_size="$(du -sk "$target_path" 2>/dev/null | cut -f1)"
    total_size=$((total_size * 1024))
    file_count="$(find "$target_path" -type f 2>/dev/null | wc -l | tr -d ' ')"
    dir_count="$(find "$target_path" -type d 2>/dev/null | wc -l | tr -d ' ')"
    print_kv "Total size" "$(format_bytes "$total_size")"
    print_kv "Files" "$file_count"
    print_kv "Directories" "$dir_count"

    # Summary
    print_divider
    timer_end "$start_time" "Deep scan"

    echo ""
    log_info "Run specific cleanup commands to address findings:"
    echo "  • declutter duplicates $target_path"
    echo "  • declutter big $target_path"
    echo "  • declutter old $target_path"
    echo "  • declutter quick $target_path"
}

# Register deep preset
if declare -F register_preset &>/dev/null; then
    register_preset "deep" "preset_deep" "Deep scan"
    register_preset "full" "preset_deep" "Deep scan (alias)"
fi
