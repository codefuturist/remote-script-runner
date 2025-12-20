#!/usr/bin/env bash
# =============================================================================
# Declutter Tool - Organizer Module
# File organization and categorization
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"
source "$SCRIPT_DIR/scanner.sh"

# =============================================================================
# ORGANIZATION RULES
# =============================================================================

# Default organization structure
declare -A DEFAULT_ORG_RULES=(
    # By category
    [documents]="Documents"
    [images]="Pictures"
    [videos]="Videos"
    [audio]="Music"
    [code]="Code"
    [archives]="Archives"
    [executables]="Applications"
    [data]="Data"
    [other]="Other"
)

# Custom rules (loaded from config)
declare -A CUSTOM_ORG_RULES

# =============================================================================
# RULE LOADING
# =============================================================================

load_org_rules() {
    local rules_file="$1"

    if [[ ! -f "$rules_file" ]]; then
        log_debug "No custom rules file found: $rules_file"
        return 0
    fi

    log_info "Loading organization rules from: $rules_file"

    while IFS='=' read -r pattern dest; do
        [[ "$pattern" =~ ^#.*$ ]] && continue
        [[ -z "$pattern" ]] && continue

        pattern=$(echo "$pattern" | xargs)
        dest=$(echo "$dest" | xargs)

        CUSTOM_ORG_RULES["$pattern"]="$dest"
    done < "$rules_file"

    log_debug "Loaded ${#CUSTOM_ORG_RULES[@]} custom rules"
}

# =============================================================================
# FILE CATEGORIZATION
# =============================================================================

get_destination_for_file() {
    local file="$1"
    local base_dir="$2"
    local basename
    basename="$(basename "$file")"
    local ext="${file##*.}"
    ext="${ext,,}"

    # Check custom rules first (pattern matching)
    for pattern in "${!CUSTOM_ORG_RULES[@]}"; do
        if [[ "$basename" == $pattern ]] || [[ "$ext" == "$pattern" ]]; then
            echo "$base_dir/${CUSTOM_ORG_RULES[$pattern]}"
            return 0
        fi
    done

    # Fall back to category-based organization
    local category
    category=$(get_file_category "$file")
    local dest_folder="${DEFAULT_ORG_RULES[$category]:-Other}"

    echo "$base_dir/$dest_folder"
}

# =============================================================================
# ORGANIZATION OPERATIONS
# =============================================================================

organize_directory() {
    local source_dir="$1"
    local target_dir="${2:-$source_dir}"
    local recursive="${3:-false}"

    log_info "Organizing files from: $source_dir"
    log_info "Target directory: $target_dir"

    local find_opts=""
    [[ "$recursive" != "true" ]] && find_opts="-maxdepth 1"

    local total_files=0
    local organized_files=0
    local skipped_files=0

    # Count files first
    while IFS= read -r file; do
        ((total_files++))
    done < <(find "$source_dir" $find_opts -type f 2>/dev/null)

    local current=0

    while IFS= read -r file; do
        ((current++))
        show_progress "$current" "$total_files" "Organizing"

        # Skip hidden files unless configured
        local basename
        basename="$(basename "$file")"
        if [[ "$basename" == .* ]] && [[ "$INCLUDE_HIDDEN" != "true" ]]; then
            ((skipped_files++))
            continue
        fi

        # Skip orphan/system files
        if is_orphan_file "$file"; then
            ((skipped_files++))
            continue
        fi

        # Get destination
        local dest_dir
        dest_dir=$(get_destination_for_file "$file" "$target_dir")
        local dest_file="$dest_dir/$basename"

        # Skip if already in correct location
        if [[ "$(dirname "$file")" == "$dest_dir" ]]; then
            ((skipped_files++))
            continue
        fi

        # Handle conflicts
        if [[ -e "$dest_file" ]]; then
            local name="${basename%.*}"
            local ext="${basename##*.}"
            local counter=1

            while [[ -e "$dest_file" ]]; do
                if [[ "$name" == "$ext" ]]; then
                    dest_file="$dest_dir/${name}_${counter}"
                else
                    dest_file="$dest_dir/${name}_${counter}.${ext}"
                fi
                ((counter++))
            done
        fi

        # Move file
        if safe_move "$file" "$dest_file"; then
            ((organized_files++))
        fi
    done < <(find "$source_dir" $find_opts -type f 2>/dev/null)

    echo ""
    log_info "Organization complete!"
    echo "  Total files:     $total_files"
    echo "  Organized:       $organized_files"
    echo "  Skipped:         $skipped_files"
}

organize_by_date() {
    local source_dir="$1"
    local target_dir="${2:-$source_dir}"
    local format="${3:-%Y/%m}"  # Year/Month by default

    log_info "Organizing files by date..."

    local organized=0

    while IFS= read -r file; do
        # Get modification date
        local mtime
        if [[ "$PLATFORM" == "macos" ]]; then
            mtime=$(stat -f%Sm -t "$format" "$file" 2>/dev/null)
        else
            mtime=$(date -d "@$(stat -c%Y "$file")" +"$format" 2>/dev/null)
        fi

        [[ -z "$mtime" ]] && continue

        local dest_dir="$target_dir/$mtime"
        local dest_file="$dest_dir/$(basename "$file")"

        if safe_move "$file" "$dest_file"; then
            ((organized++))
        fi
    done < <(find "$source_dir" -maxdepth 1 -type f 2>/dev/null)

    log_info "Organized $organized files by date"
}

organize_by_extension() {
    local source_dir="$1"
    local target_dir="${2:-$source_dir}"

    log_info "Organizing files by extension..."

    local organized=0

    while IFS= read -r file; do
        local ext="${file##*.}"
        ext="${ext,,}"

        [[ -z "$ext" || "$ext" == "$file" ]] && ext="no_extension"

        local dest_dir="$target_dir/$ext"
        local dest_file="$dest_dir/$(basename "$file")"

        if safe_move "$file" "$dest_file"; then
            ((organized++))
        fi
    done < <(find "$source_dir" -maxdepth 1 -type f 2>/dev/null)

    log_info "Organized $organized files by extension"
}

# =============================================================================
# FOLDER FLATTENING
# =============================================================================

flatten_directory() {
    local dir="$1"
    local target_dir="${2:-$dir}"
    local delete_empty="${3:-true}"

    log_info "Flattening directory structure..."

    local moved=0

    # Move all files to target directory
    while IFS= read -r file; do
        local basename
        basename="$(basename "$file")"
        local dest="$target_dir/$basename"

        # Skip if already at root level
        [[ "$(dirname "$file")" == "$target_dir" ]] && continue

        # Handle conflicts
        local counter=1
        while [[ -e "$dest" ]]; do
            local name="${basename%.*}"
            local ext="${basename##*.}"
            if [[ "$name" == "$ext" ]]; then
                dest="$target_dir/${name}_${counter}"
            else
                dest="$target_dir/${name}_${counter}.${ext}"
            fi
            ((counter++))
        done

        if safe_move "$file" "$dest"; then
            ((moved++))
        fi
    done < <(find "$dir" -type f 2>/dev/null)

    # Delete empty directories
    if [[ "$delete_empty" == "true" ]]; then
        log_info "Removing empty directories..."
        find "$dir" -type d -empty -delete 2>/dev/null || true
    fi

    log_info "Flattened $moved files"
}

# =============================================================================
# NAMING CONVENTIONS
# =============================================================================

normalize_filename() {
    local filename="$1"
    local style="${2:-kebab}"  # kebab, snake, camel, pascal

    # Remove path, keep only filename
    local basename
    basename="$(basename "$filename")"
    local name="${basename%.*}"
    local ext="${basename##*.}"

    # Normalize the name
    case "$style" in
        kebab)
            # Convert to kebab-case
            name=$(echo "$name" | \
                   sed 's/\([a-z]\)\([A-Z]\)/\1-\2/g' | \
                   sed 's/[[:space:]_]/-/g' | \
                   tr '[:upper:]' '[:lower:]' | \
                   sed 's/--*/-/g' | \
                   sed 's/^-//' | sed 's/-$//')
            ;;
        snake)
            # Convert to snake_case
            name=$(echo "$name" | \
                   sed 's/\([a-z]\)\([A-Z]\)/\1_\2/g' | \
                   sed 's/[[:space:]-]/_/g' | \
                   tr '[:upper:]' '[:lower:]' | \
                   sed 's/__*/_/g' | \
                   sed 's/^_//' | sed 's/_$//')
            ;;
        camel)
            # Convert to camelCase
            name=$(echo "$name" | \
                   sed 's/[_-]/ /g' | \
                   awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1' | \
                   tr -d ' ' | \
                   sed 's/^\(.\)/\l\1/')
            ;;
        pascal)
            # Convert to PascalCase
            name=$(echo "$name" | \
                   sed 's/[_-]/ /g' | \
                   awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1' | \
                   tr -d ' ')
            ;;
    esac

    # Reconstruct filename
    if [[ "$name" == "$ext" ]]; then
        echo "$name"
    else
        echo "${name}.${ext}"
    fi
}

rename_files_batch() {
    local dir="$1"
    local style="${2:-kebab}"
    local pattern="${3:-*}"

    log_info "Renaming files to $style case..."

    local renamed=0

    while IFS= read -r file; do
        local dirname
        dirname="$(dirname "$file")"
        local old_name
        old_name="$(basename "$file")"
        local new_name
        new_name=$(normalize_filename "$old_name" "$style")

        if [[ "$old_name" != "$new_name" ]]; then
            local new_path="$dirname/$new_name"

            if [[ ! -e "$new_path" ]]; then
                if safe_move "$file" "$new_path"; then
                    ((renamed++))
                fi
            else
                log_warn "Skipped (conflict): $old_name -> $new_name"
            fi
        fi
    done < <(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null)

    log_info "Renamed $renamed files"
}

add_date_prefix() {
    local dir="$1"
    local format="${2:-%Y%m%d}"

    log_info "Adding date prefix to files..."

    local renamed=0

    while IFS= read -r file; do
        local dirname
        dirname="$(dirname "$file")"
        local basename
        basename="$(basename "$file")"

        # Get modification date
        local date_prefix
        if [[ "$PLATFORM" == "macos" ]]; then
            date_prefix=$(stat -f%Sm -t "$format" "$file" 2>/dev/null)
        else
            date_prefix=$(date -d "@$(stat -c%Y "$file")" +"$format" 2>/dev/null)
        fi

        [[ -z "$date_prefix" ]] && continue

        # Skip if already has date prefix
        [[ "$basename" == "$date_prefix"* ]] && continue

        local new_name="${date_prefix}_${basename}"
        local new_path="$dirname/$new_name"

        if safe_move "$file" "$new_path"; then
            ((renamed++))
        fi
    done < <(find "$dir" -maxdepth 1 -type f 2>/dev/null)

    log_info "Added date prefix to $renamed files"
}

# =============================================================================
# CONSOLIDATION
# =============================================================================

consolidate_scattered_files() {
    local search_dir="$1"
    local target_dir="$2"
    local extensions="${3:-}"  # Comma-separated list

    log_info "Consolidating scattered files..."

    local moved=0

    if [[ -n "$extensions" ]]; then
        IFS=',' read -ra exts <<< "$extensions"
        for ext in "${exts[@]}"; do
            ext=$(echo "$ext" | xargs | sed 's/^\.//')

            while IFS= read -r file; do
                local dest="$target_dir/$(basename "$file")"

                # Handle conflicts
                local counter=1
                while [[ -e "$dest" ]]; do
                    local name="${basename%.*}"
                    dest="$target_dir/${name}_${counter}.${ext}"
                    ((counter++))
                done

                if safe_move "$file" "$dest"; then
                    ((moved++))
                fi
            done < <(find "$search_dir" -type f -name "*.$ext" 2>/dev/null)
        done
    else
        # Move all files
        while IFS= read -r file; do
            local basename
            basename="$(basename "$file")"
            local dest="$target_dir/$basename"

            if safe_move "$file" "$dest"; then
                ((moved++))
            fi
        done < <(find "$search_dir" -type f 2>/dev/null)
    fi

    log_info "Consolidated $moved files to $target_dir"
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f load_org_rules get_destination_for_file
export -f organize_directory organize_by_date organize_by_extension
export -f flatten_directory
export -f normalize_filename rename_files_batch add_date_prefix
export -f consolidate_scattered_files
