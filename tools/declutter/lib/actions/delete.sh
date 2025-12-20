#!/usr/bin/env bash
#
# Declutter - Delete Action
# Safe file deletion with trash support
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_ACTION_DELETE_LOADED:-}" ]] && return 0
readonly _DECLUTTER_ACTION_DELETE_LOADED=1

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
# Action Registration
# =============================================================================

if declare -F register_action &>/dev/null; then
    register_action "delete" "action_delete" "Delete files safely"
    register_action "trash" "action_trash" "Move files to trash"
    register_action "remove" "action_delete" "Delete files (alias)"
fi

# =============================================================================
# Delete Operations
# =============================================================================

# Main delete function
action_delete() {
    local path="$1"
    local force="${2:-false}"

    if [[ ! -e "$path" ]] && [[ ! -L "$path" ]]; then
        log_warn "Path not found: $path"
        return 1
    fi

    # Safety check
    if ! is_safe_path "$path"; then
        log_error "Refusing to delete protected path: $path"
        return 1
    fi

    # Check dry run
    if is_dry_run; then
        dry_run_action "delete" "$path"
        return 0
    fi

    # Use trash if enabled
    if is_trash_enabled; then
        action_trash "$path"
        return $?
    fi

    # Direct delete (with confirmation for non-force)
    if [[ "$force" != "true" ]] && is_interactive; then
        if ! confirm "Delete $path?"; then
            log_info "Skipped: $path"
            return 0
        fi
    fi

    # Record in journal
    local entry_id=""
    if is_journal_enabled; then
        entry_id="$(journal_record "delete" "$path" "" "{}")"
    fi

    # Perform delete
    if [[ -d "$path" ]]; then
        rm -rf "$path"
    else
        rm -f "$path"
    fi

    local exit_code=$?

    if ((exit_code == 0)); then
        log_success "Deleted: $path"
    else
        log_error "Failed to delete: $path"
    fi

    return $exit_code
}

# Move to trash
action_trash() {
    local path="$1"

    if [[ ! -e "$path" ]] && [[ ! -L "$path" ]]; then
        log_warn "Path not found: $path"
        return 1
    fi

    # Safety check
    if ! is_safe_path "$path"; then
        log_error "Refusing to trash protected path: $path"
        return 1
    fi

    # Check dry run
    if is_dry_run; then
        dry_run_action "trash" "$path"
        return 0
    fi

    # Get trash destination for journaling
    local trash_path=""

    if command -v trash &>/dev/null; then
        # macOS trash command
        trash_path="$HOME/.Trash/$(basename "$path")"

        # Record in journal before action
        if is_journal_enabled; then
            journal_record "delete" "$path" "$trash_path" "{}"
        fi

        trash "$path"
        local exit_code=$?

        if ((exit_code == 0)); then
            log_success "Moved to trash: $path"
        else
            log_error "Failed to trash: $path"
        fi

        return $exit_code

    elif command -v trash-put &>/dev/null; then
        # Linux trash-cli
        trash_path="$HOME/.local/share/Trash/files/$(basename "$path")"

        if is_journal_enabled; then
            journal_record "delete" "$path" "$trash_path" "{}"
        fi

        trash-put "$path"
        local exit_code=$?

        if ((exit_code == 0)); then
            log_success "Moved to trash: $path"
        else
            log_error "Failed to trash: $path"
        fi

        return $exit_code

    elif command -v gio &>/dev/null; then
        # GNOME gio trash
        if is_journal_enabled; then
            journal_record "delete" "$path" "trash:///" "{}"
        fi

        gio trash "$path"
        local exit_code=$?

        if ((exit_code == 0)); then
            log_success "Moved to trash: $path"
        else
            log_error "Failed to trash: $path"
        fi

        return $exit_code

    else
        log_warn "No trash command available, using rm instead"
        action_delete "$path" "true"
        return $?
    fi
}

# =============================================================================
# Batch Operations
# =============================================================================

# Delete multiple files
action_delete_batch() {
    local -a files=("$@")
    local success=0
    local failed=0
    local threshold
    threshold="$(config_action "delete_confirm_threshold" "10")"

    local count="${#files[@]}"

    # Confirm if above threshold
    if is_interactive && ((count > threshold)); then
        log_warn "About to delete $count files"
        if ! confirm "Continue with deletion?"; then
            log_info "Operation cancelled"
            return 0
        fi
    fi

    # Delete each file
    for file in "${files[@]}"; do
        if action_delete "$file" "true"; then
            ((success++))
        else
            ((failed++))
        fi
    done

    # Summary
    print_action_summary "delete" "$success" "$failed" ""

    return $((failed > 0 ? 1 : 0))
}

# Delete from scan result
action_delete_from_scan() {
    local scan_result="$1"
    local selector="${2:-.items[].path}"

    local -a files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && files+=("$file")
    done < <(echo "$scan_result" | jq -r "$selector" 2>/dev/null)

    if ((${#files[@]} == 0)); then
        log_info "No files to delete"
        return 0
    fi

    # Interactive selection if enabled
    if is_interactive && has_fzf; then
        local -a selected=()
        while IFS= read -r file; do
            [[ -n "$file" ]] && selected+=("$file")
        done < <(printf '%s\n' "${files[@]}" | select_files "Select files to delete")

        if ((${#selected[@]} == 0)); then
            log_info "No files selected"
            return 0
        fi

        files=("${selected[@]}")
    fi

    action_delete_batch "${files[@]}"
}

# =============================================================================
# Specialized Delete Functions
# =============================================================================

# Delete empty files
action_delete_empty_files() {
    local target_path="${1:-$PWD}"

    log_step "Deleting empty files in: $target_path"

    local scan_result
    scan_result="$(scan_empty_files "$target_path")"

    action_delete_from_scan "$scan_result" ".items[].path"
}

# Delete empty directories
action_delete_empty_dirs() {
    local target_path="${1:-$PWD}"

    log_step "Deleting empty directories in: $target_path"

    local -a dirs=()
    while IFS= read -r dir; do
        [[ -n "$dir" ]] && dirs+=("$dir")
    done < <(find "$target_path" -type d -empty 2>/dev/null | sort -r)

    local success=0
    local failed=0

    for dir in "${dirs[@]}"; do
        if is_dry_run; then
            dry_run_action "rmdir" "$dir"
            ((success++))
        elif rmdir "$dir" 2>/dev/null; then
            log_success "Deleted directory: $dir"
            ((success++))
        else
            log_warn "Could not delete: $dir"
            ((failed++))
        fi
    done

    print_action_summary "delete empty dirs" "$success" "$failed" ""
}

# Delete duplicates (keep one)
action_delete_duplicates() {
    local scan_result="$1"
    local keep_strategy="${2:-first}"  # first, newest, oldest

    log_step "Deleting duplicates (keeping $keep_strategy)"

    local -a to_delete=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && to_delete+=("$file")
    done < <(get_duplicates_to_delete "$scan_result" "$keep_strategy")

    if ((${#to_delete[@]} == 0)); then
        log_info "No duplicates to delete"
        return 0
    fi

    log_info "Found ${#to_delete[@]} duplicate files to remove"

    action_delete_batch "${to_delete[@]}"
}

# =============================================================================
# Safety Functions
# =============================================================================

# Verify deletion is safe
verify_delete_safe() {
    local path="$1"

    # Check if path exists
    if [[ ! -e "$path" ]]; then
        return 1
    fi

    # Check if protected
    if ! is_safe_path "$path"; then
        return 1
    fi

    # Check for important files
    local basename
    basename="$(basename "$path")"

    case "$basename" in
        .ssh|.gnupg|.aws|.kube|id_rsa*|*.pem|*.key)
            log_warn "Potential credential file detected: $path"
            return 1
            ;;
        .bashrc|.zshrc|.profile|.bash_profile)
            log_warn "Shell config file detected: $path"
            return 1
            ;;
    esac

    return 0
}

# Preview delete operation
preview_delete() {
    local -a files=("$@")
    local total_size=0

    print_section "Delete Preview"

    for file in "${files[@]}"; do
        if [[ -e "$file" ]]; then
            local size
            size="$(get_file_size "$file")"
            ((total_size += size))
            echo "  $(format_bytes "$size")  $file"
        fi
    done

    print_divider
    print_kv "Total files" "${#files[@]}"
    print_kv "Total size" "$(format_bytes "$total_size")"
}
