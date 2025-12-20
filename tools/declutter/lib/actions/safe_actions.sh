#!/usr/bin/env bash
# ============================================================================
# Safe Actions
# Safe wrappers for file operations with undo support
# ============================================================================

set -euo pipefail

# Prevent double-sourcing
[[ "${_DECLUTTER_ACTIONS_LOADED:-}" == "true" ]] && return 0
readonly _DECLUTTER_ACTIONS_LOADED="true"

# =============================================================================
# Safe Delete
# =============================================================================

safe_delete() {
    local file=$1
    local session_id=${2:-$(undo_get_current_session)}

    if [[ ! -e "$file" ]]; then
        log_warn "File not found: $file"
        return 1
    fi

    # Record for undo if session is active
    if [[ -n "$session_id" ]]; then
        undo_record "delete" "$file" "" "$session_id"
    fi

    # Dry run check
    if is_dry_run; then
        log_info "[DRY RUN] Would delete: $file"
        return 0
    fi

    # Use trash or permanent delete
    if use_trash; then
        if move_to_trash "$file"; then
            log_action "TRASH" "$file"
            log_success "Moved to trash: $file"
        else
            log_error "Failed to trash: $file"
            return 1
        fi
    else
        if rm -rf "$file"; then
            log_action "DELETE" "$file"
            log_success "Deleted: $file"
        else
            log_error "Failed to delete: $file"
            return 1
        fi
    fi
}

# =============================================================================
# Safe Move
# =============================================================================

safe_move() {
    local source=$1
    local dest=$2
    local session_id=${3:-$(undo_get_current_session)}

    if [[ ! -e "$source" ]]; then
        log_warn "Source not found: $source"
        return 1
    fi

    # Record for undo
    if [[ -n "$session_id" ]]; then
        undo_record "move" "$source" "$dest" "$session_id"
    fi

    # Dry run check
    if is_dry_run; then
        log_info "[DRY RUN] Would move: $source -> $dest"
        return 0
    fi

    # Create destination directory if needed
    local dest_dir
    dest_dir=$(dirname "$dest")
    mkdir -p "$dest_dir"

    if mv "$source" "$dest"; then
        log_action "MOVE" "$source" "-> $dest"
        log_success "Moved: $source -> $dest"
    else
        log_error "Failed to move: $source -> $dest"
        return 1
    fi
}

# =============================================================================
# Safe Rename
# =============================================================================

safe_rename() {
    local source=$1
    local new_name=$2
    local session_id=${3:-$(undo_get_current_session)}

    if [[ ! -e "$source" ]]; then
        log_warn "Source not found: $source"
        return 1
    fi

    local dir
    dir=$(dirname "$source")
    local dest="$dir/$new_name"

    # Check if destination exists
    if [[ -e "$dest" ]]; then
        log_warn "Destination already exists: $dest"
        return 1
    fi

    # Record for undo
    if [[ -n "$session_id" ]]; then
        undo_record "rename" "$source" "$dest" "$session_id"
    fi

    # Dry run check
    if is_dry_run; then
        log_info "[DRY RUN] Would rename: $source -> $new_name"
        return 0
    fi

    if mv "$source" "$dest"; then
        log_action "RENAME" "$source" "-> $new_name"
        log_success "Renamed: $(basename "$source") -> $new_name"
    else
        log_error "Failed to rename: $source -> $new_name"
        return 1
    fi
}

# =============================================================================
# Safe Copy
# =============================================================================

safe_copy() {
    local source=$1
    local dest=$2
    local session_id=${3:-$(undo_get_current_session)}

    if [[ ! -e "$source" ]]; then
        log_warn "Source not found: $source"
        return 1
    fi

    # Record for undo (copy can be undone by deleting the copy)
    if [[ -n "$session_id" ]]; then
        undo_record "copy" "$source" "$dest" "$session_id"
    fi

    # Dry run check
    if is_dry_run; then
        log_info "[DRY RUN] Would copy: $source -> $dest"
        return 0
    fi

    # Create destination directory if needed
    local dest_dir
    dest_dir=$(dirname "$dest")
    mkdir -p "$dest_dir"

    if cp -rp "$source" "$dest"; then
        log_action "COPY" "$source" "-> $dest"
        log_success "Copied: $source -> $dest"
    else
        log_error "Failed to copy: $source -> $dest"
        return 1
    fi
}

# =============================================================================
# Batch Operations
# =============================================================================

# Delete multiple files
batch_delete() {
    local session_id=${1:-}
    shift
    local files=("$@")

    local deleted=0
    local failed=0

    for file in "${files[@]}"; do
        if safe_delete "$file" "$session_id"; then
            ((deleted++))
        else
            ((failed++))
        fi
    done

    log_info "Batch delete: $deleted succeeded, $failed failed"
}

# Move multiple files to a directory
batch_move() {
    local dest_dir=$1
    local session_id=${2:-}
    shift 2
    local files=("$@")

    mkdir -p "$dest_dir"

    local moved=0
    local failed=0

    for file in "${files[@]}"; do
        local basename
        basename=$(basename "$file")
        local dest="$dest_dir/$basename"

        if safe_move "$file" "$dest" "$session_id"; then
            ((moved++))
        else
            ((failed++))
        fi
    done

    log_info "Batch move: $moved succeeded, $failed failed"
}

# =============================================================================
# Confirmation Helpers
# =============================================================================

# Confirm before action
confirm_and_delete() {
    local file=$1
    local session_id=${2:-}

    if prompt_confirm "Delete $file?"; then
        safe_delete "$file" "$session_id"
    else
        log_info "Skipped: $file"
    fi
}

# Confirm before batch action
confirm_batch_delete() {
    local session_id=${1:-}
    shift
    local files=("$@")

    local count=${#files[@]}

    echo ""
    log_info "Files to delete:"
    for file in "${files[@]:0:10}"; do
        echo "  - $file"
    done

    if ((count > 10)); then
        echo "  ... and $((count - 10)) more"
    fi
    echo ""

    if prompt_confirm "Delete $count files?"; then
        batch_delete "$session_id" "${files[@]}"
    else
        log_info "Operation cancelled"
    fi
}

# =============================================================================
# Export
# =============================================================================

export -f safe_delete safe_move safe_rename safe_copy
export -f batch_delete batch_move
export -f confirm_and_delete confirm_batch_delete
