#!/usr/bin/env bash
#
# Declutter - Move Action
# Move files with journaling support
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_ACTION_MOVE_LOADED:-}" ]] && return 0
readonly _DECLUTTER_ACTION_MOVE_LOADED=1

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
    register_action "move" "action_move" "Move files to destination"
    register_action "mv" "action_move" "Move files (alias)"
fi

# =============================================================================
# Move Operations
# =============================================================================

# Main move function
action_move() {
    local source="$1"
    local destination="$2"
    local overwrite="${3:-false}"

    if [[ ! -e "$source" ]]; then
        log_error "Source not found: $source"
        return 1
    fi

    if [[ -z "$destination" ]]; then
        log_error "Destination not specified"
        return 1
    fi

    # Check dry run
    if is_dry_run; then
        dry_run_action "move" "$source" "$destination"
        return 0
    fi

    # Expand destination
    destination="${destination/#\~/$HOME}"

    # Handle destination directory
    local dest_dir
    if [[ -d "$destination" ]]; then
        # Moving into directory
        dest_dir="$destination"
        destination="$destination/$(basename "$source")"
    else
        dest_dir="$(dirname "$destination")"
    fi

    # Create destination directory if needed
    local create_dirs
    create_dirs="$(config_action "move_create_dirs" "true")"

    if [[ "$create_dirs" == "true" ]] && [[ ! -d "$dest_dir" ]]; then
        mkdir -p "$dest_dir"
        log_debug "Created directory: $dest_dir"
    fi

    if [[ ! -d "$dest_dir" ]]; then
        log_error "Destination directory does not exist: $dest_dir"
        return 1
    fi

    # Check for existing file
    if [[ -e "$destination" ]]; then
        local config_overwrite
        config_overwrite="$(config_action "move_overwrite" "false")"

        if [[ "$overwrite" != "true" ]] && [[ "$config_overwrite" != "true" ]]; then
            if is_interactive; then
                if ! confirm "Overwrite existing file: $destination?"; then
                    log_info "Skipped: $source"
                    return 0
                fi
            else
                log_warn "Destination exists (use overwrite): $destination"
                return 1
            fi
        fi
    fi

    # Record in journal
    if is_journal_enabled; then
        journal_record "move" "$source" "$destination" "{}"
    fi

    # Perform move
    mv "$source" "$destination"
    local exit_code=$?

    if ((exit_code == 0)); then
        log_success "Moved: $source → $destination"
    else
        log_error "Failed to move: $source"
    fi

    return $exit_code
}

# =============================================================================
# Batch Operations
# =============================================================================

# Move multiple files to destination
action_move_batch() {
    local destination="$1"
    shift
    local -a files=("$@")

    local success=0
    local failed=0

    # Ensure destination is a directory
    if [[ ! -d "$destination" ]]; then
        if is_dry_run; then
            log_info "[DRY-RUN] Would create directory: $destination"
        else
            mkdir -p "$destination"
        fi
    fi

    for file in "${files[@]}"; do
        if action_move "$file" "$destination"; then
            ((success++))
        else
            ((failed++))
        fi
    done

    print_action_summary "move" "$success" "$failed" ""

    return $((failed > 0 ? 1 : 0))
}

# Move files matching pattern
action_move_pattern() {
    local source_dir="$1"
    local pattern="$2"
    local destination="$3"

    local -a files=()

    if command -v fd &>/dev/null; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && files+=("$file")
        done < <(fd --glob "$pattern" "$source_dir" 2>/dev/null)
    else
        while IFS= read -r file; do
            [[ -n "$file" ]] && files+=("$file")
        done < <(find "$source_dir" -name "$pattern" 2>/dev/null)
    fi

    if ((${#files[@]} == 0)); then
        log_info "No files matching pattern: $pattern"
        return 0
    fi

    log_info "Found ${#files[@]} files matching: $pattern"

    action_move_batch "$destination" "${files[@]}"
}

# =============================================================================
# Organization Moves
# =============================================================================

# Move files by extension to categorized folders
action_organize_by_type() {
    local source_dir="${1:-$PWD}"
    local dest_base="${2:-$source_dir}"

    log_step "Organizing files by type in: $source_dir"

    declare -A type_dirs=(
        [documents]="Documents"
        [images]="Images"
        [videos]="Videos"
        [audio]="Audio"
        [code]="Code"
        [archives]="Archives"
        [data]="Data"
        [executables]="Applications"
        [other]="Other"
    )

    local success=0
    local failed=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue

        local category
        category="$(get_file_category "$file")"

        local dest_dir="${dest_base}/${type_dirs[$category]:-Other}"

        if action_move "$file" "$dest_dir/"; then
            ((success++))
        else
            ((failed++))
        fi
    done < <(find "$source_dir" -maxdepth 1 -type f 2>/dev/null)

    print_action_summary "organize" "$success" "$failed" ""
}

# Move files by date to year/month folders
action_organize_by_date() {
    local source_dir="${1:-$PWD}"
    local dest_base="${2:-$source_dir}"

    log_step "Organizing files by date in: $source_dir"

    local success=0
    local failed=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue

        local mtime year month
        mtime="$(get_mtime "$file")"
        year="$(date -r "$mtime" +%Y 2>/dev/null || date -d "@$mtime" +%Y 2>/dev/null)"
        month="$(date -r "$mtime" +%m 2>/dev/null || date -d "@$mtime" +%m 2>/dev/null)"

        if [[ -n "$year" ]] && [[ -n "$month" ]]; then
            local dest_dir="${dest_base}/${year}/${month}"

            if action_move "$file" "$dest_dir/"; then
                ((success++))
            else
                ((failed++))
            fi
        fi
    done < <(find "$source_dir" -maxdepth 1 -type f 2>/dev/null)

    print_action_summary "organize by date" "$success" "$failed" ""
}

# =============================================================================
# Flatten Operations
# =============================================================================

# Flatten nested directories
action_flatten() {
    local source_dir="${1:-$PWD}"
    local dest_dir="${2:-$source_dir}"
    local delete_empty="${3:-true}"

    log_step "Flattening directory structure: $source_dir"

    local success=0
    local failed=0

    # Move all files to destination
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Skip if already in dest_dir
        local file_dir
        file_dir="$(dirname "$file")"
        [[ "$file_dir" == "$dest_dir" ]] && continue

        local basename
        basename="$(basename "$file")"
        local dest_path="$dest_dir/$basename"

        # Handle name conflicts
        if [[ -e "$dest_path" ]]; then
            local counter=1
            local name_no_ext ext
            name_no_ext="$(get_basename_no_ext "$basename")"
            ext="$(get_extension "$basename")"

            while [[ -e "$dest_path" ]]; do
                if [[ -n "$ext" ]]; then
                    dest_path="$dest_dir/${name_no_ext}_${counter}.${ext}"
                else
                    dest_path="$dest_dir/${name_no_ext}_${counter}"
                fi
                ((counter++))
            done
        fi

        if action_move "$file" "$dest_path"; then
            ((success++))
        else
            ((failed++))
        fi
    done < <(find "$source_dir" -type f 2>/dev/null)

    # Delete empty directories
    if [[ "$delete_empty" == "true" ]]; then
        find "$source_dir" -type d -empty -delete 2>/dev/null
        log_info "Removed empty directories"
    fi

    print_action_summary "flatten" "$success" "$failed" ""
}

# =============================================================================
# Helper Functions
# =============================================================================

# Preview move operation
preview_move() {
    local destination="$1"
    shift
    local -a files=("$@")

    print_section "Move Preview"
    print_kv "Destination" "$destination"
    echo ""

    for file in "${files[@]}"; do
        echo "  $file"
    done

    print_divider
    print_kv "Total files" "${#files[@]}"
}
