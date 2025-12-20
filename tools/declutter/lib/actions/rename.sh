#!/usr/bin/env bash
#
# Declutter - Rename Action
# Rename files with pattern support
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_ACTION_RENAME_LOADED:-}" ]] && return 0
readonly _DECLUTTER_ACTION_RENAME_LOADED=1

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
    register_action "rename" "action_rename" "Rename files"
fi

# =============================================================================
# Rename Operations
# =============================================================================

# Main rename function
action_rename() {
    local source="$1"
    local new_name="$2"

    if [[ ! -e "$source" ]]; then
        log_error "Source not found: $source"
        return 1
    fi

    if [[ -z "$new_name" ]]; then
        log_error "New name not specified"
        return 1
    fi

    local source_dir
    source_dir="$(dirname "$source")"
    local destination="$source_dir/$new_name"

    # Check dry run
    if is_dry_run; then
        dry_run_action "rename" "$source" "$destination"
        return 0
    fi

    # Check if destination exists
    if [[ -e "$destination" ]]; then
        log_error "Destination already exists: $destination"
        return 1
    fi

    # Record in journal
    if is_journal_enabled; then
        journal_record "rename" "$source" "$destination" "{}"
    fi

    # Perform rename
    mv "$source" "$destination"
    local exit_code=$?

    if ((exit_code == 0)); then
        log_success "Renamed: $(basename "$source") → $new_name"
    else
        log_error "Failed to rename: $source"
    fi

    return $exit_code
}

# =============================================================================
# Pattern-based Renaming
# =============================================================================

# Rename using template pattern
# Supported variables: {original}, {ext}, {date}, {datetime}, {counter}, {hash:N}
action_rename_pattern() {
    local source="$1"
    local pattern="$2"
    local counter="${3:-1}"

    if [[ ! -e "$source" ]]; then
        log_error "Source not found: $source"
        return 1
    fi

    local original ext date_str datetime_str hash_str
    original="$(get_basename_no_ext "$source")"
    ext="$(get_extension "$source")"
    date_str="$(date +%Y-%m-%d)"
    datetime_str="$(date +%Y-%m-%d_%H-%M-%S)"
    hash_str="$(get_file_hash "$source" md5 | head -c 8)"

    # Replace variables
    local new_name="$pattern"
    new_name="${new_name//\{original\}/$original}"
    new_name="${new_name//\{ext\}/$ext}"
    new_name="${new_name//\{date\}/$date_str}"
    new_name="${new_name//\{datetime\}/$datetime_str}"
    new_name="${new_name//\{counter\}/$counter}"

    # Handle {hash:N} pattern
    if [[ "$new_name" =~ \{hash:([0-9]+)\} ]]; then
        local hash_len="${BASH_REMATCH[1]}"
        local short_hash
        short_hash="$(get_file_hash "$source" md5 | head -c "$hash_len")"
        new_name="${new_name//\{hash:$hash_len\}/$short_hash}"
    fi
    new_name="${new_name//\{hash\}/$hash_str}"

    # Add extension if not in pattern
    if [[ -n "$ext" ]] && [[ "$new_name" != *".$ext" ]]; then
        new_name="${new_name}.${ext}"
    fi

    action_rename "$source" "$new_name"
}

# Batch rename with pattern
action_rename_batch() {
    local pattern="$1"
    shift
    local -a files=("$@")

    local success=0
    local failed=0
    local counter=1

    for file in "${files[@]}"; do
        if action_rename_pattern "$file" "$pattern" "$counter"; then
            ((success++))
        else
            ((failed++))
        fi
        ((counter++))
    done

    print_action_summary "rename" "$success" "$failed" ""
}

# =============================================================================
# Common Rename Operations
# =============================================================================

# Add prefix to filename
action_add_prefix() {
    local source="$1"
    local prefix="$2"

    local basename
    basename="$(basename "$source")"
    local new_name="${prefix}${basename}"

    action_rename "$source" "$new_name"
}

# Add suffix to filename (before extension)
action_add_suffix() {
    local source="$1"
    local suffix="$2"

    local basename ext name_no_ext new_name
    basename="$(basename "$source")"
    ext="$(get_extension "$basename")"
    name_no_ext="$(get_basename_no_ext "$basename")"

    if [[ -n "$ext" ]]; then
        new_name="${name_no_ext}${suffix}.${ext}"
    else
        new_name="${name_no_ext}${suffix}"
    fi

    action_rename "$source" "$new_name"
}

# Replace text in filename
action_replace_in_name() {
    local source="$1"
    local find_text="$2"
    local replace_text="$3"

    local basename new_name
    basename="$(basename "$source")"
    new_name="${basename//$find_text/$replace_text}"

    if [[ "$basename" == "$new_name" ]]; then
        log_debug "No change needed: $source"
        return 0
    fi

    action_rename "$source" "$new_name"
}

# Convert to lowercase
action_lowercase() {
    local source="$1"

    local basename new_name
    basename="$(basename "$source")"
    new_name="${basename,,}"

    if [[ "$basename" == "$new_name" ]]; then
        return 0
    fi

    action_rename "$source" "$new_name"
}

# Convert to uppercase
action_uppercase() {
    local source="$1"

    local basename new_name
    basename="$(basename "$source")"
    new_name="${basename^^}"

    if [[ "$basename" == "$new_name" ]]; then
        return 0
    fi

    action_rename "$source" "$new_name"
}

# Replace spaces with character
action_replace_spaces() {
    local source="$1"
    local replacement="${2:-_}"

    local basename new_name
    basename="$(basename "$source")"
    new_name="${basename// /$replacement}"

    if [[ "$basename" == "$new_name" ]]; then
        return 0
    fi

    action_rename "$source" "$new_name"
}

# Sanitize filename (remove special characters)
action_sanitize_name() {
    local source="$1"

    local basename ext name_no_ext sanitized new_name
    basename="$(basename "$source")"
    ext="$(get_extension "$basename")"
    name_no_ext="$(get_basename_no_ext "$basename")"

    # Replace problematic characters
    sanitized="$name_no_ext"
    sanitized="${sanitized// /_}"           # Spaces to underscores
    sanitized="${sanitized//[^a-zA-Z0-9._-]/}"  # Remove special chars
    sanitized="${sanitized//__/_}"          # Collapse multiple underscores

    if [[ -n "$ext" ]]; then
        new_name="${sanitized}.${ext}"
    else
        new_name="$sanitized"
    fi

    if [[ "$basename" == "$new_name" ]]; then
        return 0
    fi

    action_rename "$source" "$new_name"
}

# =============================================================================
# Sequential Renaming
# =============================================================================

# Rename files sequentially (file_001, file_002, etc.)
action_rename_sequential() {
    local prefix="$1"
    local padding="${2:-3}"
    shift 2
    local -a files=("$@")

    local success=0
    local failed=0
    local counter=1

    for file in "${files[@]}"; do
        local ext
        ext="$(get_extension "$file")"

        local new_name
        new_name=$(printf "%s_%0${padding}d" "$prefix" "$counter")

        if [[ -n "$ext" ]]; then
            new_name="${new_name}.${ext}"
        fi

        if action_rename "$file" "$new_name"; then
            ((success++))
        else
            ((failed++))
        fi
        ((counter++))
    done

    print_action_summary "sequential rename" "$success" "$failed" ""
}

# =============================================================================
# Helper Functions
# =============================================================================

# Preview rename operation
preview_rename() {
    local pattern="$1"
    shift
    local -a files=("$@")

    print_section "Rename Preview"
    print_kv "Pattern" "$pattern"
    echo ""

    local counter=1
    for file in "${files[@]}"; do
        local original ext date_str new_name
        original="$(get_basename_no_ext "$file")"
        ext="$(get_extension "$file")"
        date_str="$(date +%Y-%m-%d)"

        new_name="$pattern"
        new_name="${new_name//\{original\}/$original}"
        new_name="${new_name//\{date\}/$date_str}"
        new_name="${new_name//\{counter\}/$counter}"

        if [[ -n "$ext" ]] && [[ "$new_name" != *".$ext" ]]; then
            new_name="${new_name}.${ext}"
        fi

        echo "  $(basename "$file") → $new_name"
        ((counter++))
    done

    print_divider
}
