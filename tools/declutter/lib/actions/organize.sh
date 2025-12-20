#!/usr/bin/env bash
# ============================================================================
# File Organization Module
# Auto-sort, organize, and manage files
# ============================================================================

set -euo pipefail

# Prevent double-sourcing
[[ "${_DECLUTTER_ACTIONS_ORGANIZE_LOADED:-}" == "true" ]] && return 0
readonly _DECLUTTER_ACTIONS_ORGANIZE_LOADED="true"

# =============================================================================
# Category Organization
# =============================================================================

# Organize files by category
organize_by_category() {
    local source_dir=${1:-.}
    local dest_base=${2:-$source_dir}
    local session_id=${3:-}

    if [[ -z "$session_id" ]]; then
        session_id=$(undo_create_session "Organize by category")
    fi

    print_section "Organizing files by category"

    local moved=0

    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue

        local category
        category=$(get_file_category "$file")

        [[ "$category" == "other" ]] && continue

        local dest_dir="$dest_base/$category"
        local basename
        basename=$(basename "$file")
        local dest="$dest_dir/$basename"

        # Skip if already in correct location
        [[ "$(dirname "$file")" == "$dest_dir" ]] && continue

        safe_move "$file" "$dest" "$session_id"
        ((moved++))
    done < <(find "$source_dir" -maxdepth 1 -type f -print0 2>/dev/null)

    undo_close_session "$session_id"

    log_success "Organized $moved files into categories"
}

# Organize by date
organize_by_date() {
    local source_dir=${1:-.}
    local dest_base=${2:-$source_dir}
    local date_format=${3:-"%Y/%m"}  # e.g., 2024/01
    local session_id=${4:-}

    if [[ -z "$session_id" ]]; then
        session_id=$(undo_create_session "Organize by date")
    fi

    print_section "Organizing files by date"

    local moved=0

    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue

        local mtime
        mtime=$(get_mod_time "$file" 2>/dev/null) || continue

        local date_dir
        date_dir=$(format_timestamp "$mtime" "$date_format" 2>/dev/null) || continue

        local dest_dir="$dest_base/$date_dir"
        local basename
        basename=$(basename "$file")
        local dest="$dest_dir/$basename"

        safe_move "$file" "$dest" "$session_id"
        ((moved++))
    done < <(find "$source_dir" -maxdepth 1 -type f -print0 2>/dev/null)

    undo_close_session "$session_id"

    log_success "Organized $moved files by date"
}

# =============================================================================
# Extension-Based Sorting
# =============================================================================

# Default extension rules
declare -A EXTENSION_RULES=(
    [pdf]="Documents/PDF"
    [doc]="Documents/Word"
    [docx]="Documents/Word"
    [xls]="Documents/Excel"
    [xlsx]="Documents/Excel"
    [ppt]="Documents/PowerPoint"
    [pptx]="Documents/PowerPoint"
    [txt]="Documents/Text"
    [md]="Documents/Markdown"

    [jpg]="Images"
    [jpeg]="Images"
    [png]="Images"
    [gif]="Images"
    [svg]="Images"
    [webp]="Images"
    [heic]="Images"

    [mp4]="Videos"
    [avi]="Videos"
    [mkv]="Videos"
    [mov]="Videos"
    [wmv]="Videos"

    [mp3]="Music"
    [wav]="Music"
    [flac]="Music"
    [aac]="Music"
    [m4a]="Music"

    [zip]="Archives"
    [rar]="Archives"
    [7z]="Archives"
    [tar]="Archives"
    [gz]="Archives"

    [dmg]="Installers"
    [pkg]="Installers"
    [exe]="Installers"
    [msi]="Installers"
    [deb]="Installers"
    [rpm]="Installers"
)

# Sort files by extension rules
sort_by_extension() {
    local source_dir=${1:-.}
    local dest_base=${2:-$source_dir}
    local session_id=${3:-}

    if [[ -z "$session_id" ]]; then
        session_id=$(undo_create_session "Sort by extension")
    fi

    print_section "Sorting files by extension"

    local moved=0

    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue

        local ext
        ext=$(get_extension "$file")

        [[ -z "$ext" ]] && continue

        local dest_subdir="${EXTENSION_RULES[$ext]:-}"
        [[ -z "$dest_subdir" ]] && continue

        local dest_dir="$dest_base/$dest_subdir"
        local basename
        basename=$(basename "$file")
        local dest="$dest_dir/$basename"

        safe_move "$file" "$dest" "$session_id"
        ((moved++))
    done < <(find "$source_dir" -maxdepth 1 -type f -print0 2>/dev/null)

    undo_close_session "$session_id"

    log_success "Sorted $moved files by extension"
}

# Add custom extension rule
add_extension_rule() {
    local extension=$1
    local destination=$2
    EXTENSION_RULES[$extension]="$destination"
}

# =============================================================================
# Renaming
# =============================================================================

# Batch rename files
batch_rename() {
    local path=${1:-.}
    local pattern=${2:-"*"}
    local style=${3:-"lowercase"}  # lowercase, uppercase, snake_case, kebab-case, title_case
    local session_id=${4:-}

    if [[ -z "$session_id" ]]; then
        session_id=$(undo_create_session "Batch rename")
    fi

    print_section "Renaming files: $style"

    local renamed=0

    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue

        local dir basename ext new_name
        dir=$(dirname "$file")
        basename=$(basename "$file")
        ext="${basename##*.}"
        basename="${basename%.*}"

        case "$style" in
            lowercase)
                new_name="${basename,,}"
                ;;
            uppercase)
                new_name="${basename^^}"
                ;;
            snake_case)
                new_name=$(echo "$basename" | sed -E 's/[[:space:]]+/_/g; s/-/_/g; s/([a-z])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')
                ;;
            kebab-case)
                new_name=$(echo "$basename" | sed -E 's/[[:space:]]+/-/g; s/_/-/g; s/([a-z])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')
                ;;
            title_case)
                new_name=$(echo "$basename" | sed -E 's/(^|[[:space:]])([a-z])/\1\u\2/g')
                ;;
        esac

        [[ "$ext" != "$basename" ]] && new_name="$new_name.$ext"

        if [[ "$basename.$ext" != "$new_name" ]]; then
            safe_rename "$file" "$new_name" "$session_id"
            ((renamed++))
        fi
    done < <(find "$path" -maxdepth 1 -type f -name "$pattern" -print0 2>/dev/null)

    undo_close_session "$session_id"

    log_success "Renamed $renamed files"
}

# Add prefix/suffix to files
add_prefix_suffix() {
    local path=${1:-.}
    local prefix=${2:-""}
    local suffix=${3:-""}
    local pattern=${4:-"*"}
    local session_id=${5:-}

    if [[ -z "$prefix" && -z "$suffix" ]]; then
        log_error "Either prefix or suffix must be specified"
        return 1
    fi

    if [[ -z "$session_id" ]]; then
        session_id=$(undo_create_session "Add prefix/suffix")
    fi

    local renamed=0

    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue

        local basename ext new_name
        basename=$(basename "$file")
        ext="${basename##*.}"

        if [[ "$ext" != "$basename" ]]; then
            basename="${basename%.*}"
            new_name="${prefix}${basename}${suffix}.${ext}"
        else
            new_name="${prefix}${basename}${suffix}"
        fi

        safe_rename "$file" "$new_name" "$session_id"
        ((renamed++))
    done < <(find "$path" -maxdepth 1 -type f -name "$pattern" -print0 2>/dev/null)

    undo_close_session "$session_id"

    log_success "Renamed $renamed files"
}

# =============================================================================
# Flatten/Consolidate
# =============================================================================

# Flatten nested directories
flatten_directory() {
    local source_dir=${1:-.}
    local dest_dir=${2:-$source_dir}
    local session_id=${3:-}

    if [[ -z "$session_id" ]]; then
        session_id=$(undo_create_session "Flatten directory")
    fi

    print_section "Flattening directory structure"

    local moved=0

    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue

        local basename
        basename=$(basename "$file")
        local dest="$dest_dir/$basename"

        # Handle name conflicts
        if [[ -e "$dest" && "$file" != "$dest" ]]; then
            local name ext counter=1
            name="${basename%.*}"
            ext="${basename##*.}"

            while [[ -e "$dest_dir/${name}_${counter}.${ext}" ]]; do
                ((counter++))
            done

            dest="$dest_dir/${name}_${counter}.${ext}"
        fi

        if [[ "$file" != "$dest" ]]; then
            safe_move "$file" "$dest" "$session_id"
            ((moved++))
        fi
    done < <(find "$source_dir" -mindepth 2 -type f -print0 2>/dev/null)

    # Remove empty directories
    find "$source_dir" -mindepth 1 -type d -empty -delete 2>/dev/null || true

    undo_close_session "$session_id"

    log_success "Flattened $moved files"
}

# Consolidate scattered files of same type
consolidate_by_type() {
    local source_dir=${1:-.}
    local dest_dir=${2:-$source_dir/Consolidated}
    local file_type=${3:-"images"}  # images, videos, documents, audio
    local session_id=${4:-}

    if [[ -z "$session_id" ]]; then
        session_id=$(undo_create_session "Consolidate $file_type")
    fi

    local -a extensions
    case "$file_type" in
        images)   extensions=(jpg jpeg png gif webp svg heic bmp tiff) ;;
        videos)   extensions=(mp4 avi mkv mov wmv flv webm m4v) ;;
        documents) extensions=(pdf doc docx xls xlsx ppt pptx txt md odt ods) ;;
        audio)    extensions=(mp3 wav flac aac ogg wma m4a opus) ;;
    esac

    mkdir -p "$dest_dir"

    local moved=0

    for ext in "${extensions[@]}"; do
        while IFS= read -r -d '' file; do
            local basename
            basename=$(basename "$file")
            local dest="$dest_dir/$basename"

            if [[ "$file" != "$dest" ]]; then
                safe_move "$file" "$dest" "$session_id"
                ((moved++))
            fi
        done < <(find "$source_dir" -type f -iname "*.$ext" -print0 2>/dev/null)
    done

    undo_close_session "$session_id"

    log_success "Consolidated $moved $file_type files to $dest_dir"
}

# =============================================================================
# Export
# =============================================================================

export -f organize_by_category organize_by_date
export -f sort_by_extension add_extension_rule
export -f batch_rename add_prefix_suffix
export -f flatten_directory consolidate_by_type
