#!/usr/bin/env bash
# ============================================================================
# Organization Rules Module
# Auto-move, rename, and organize files
# ============================================================================

set -euo pipefail

_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &

# Default organization rules
declare -A ORGANIZE_RULES=(
    ["*.pdf"]="Documents/PDFs"
    ["*.doc"]="Documents/Word"
    ["*.docx"]="Documents/Word"
    ["*.xls"]="Documents/Excel"
    ["*.xlsx"]="Documents/Excel"
    ["*.ppt"]="Documents/PowerPoint"
    ["*.pptx"]="Documents/PowerPoint"
    ["*.jpg"]="Pictures/Photos"
    ["*.jpeg"]="Pictures/Photos"
    ["*.png"]="Pictures/Images"
    ["*.gif"]="Pictures/GIFs"
    ["*.svg"]="Pictures/SVG"
    ["*.mp4"]="Videos"
    ["*.mkv"]="Videos"
    ["*.avi"]="Videos"
    ["*.mov"]="Videos"
    ["*.mp3"]="Music"
    ["*.flac"]="Music"
    ["*.wav"]="Music"
    ["*.zip"]="Archives"
    ["*.tar.gz"]="Archives"
    ["*.rar"]="Archives"
    ["*.7z"]="Archives"
    ["*.dmg"]="Installers"
    ["*.exe"]="Installers"
    ["*.pkg"]="Installers"
    ["*.deb"]="Installers"
    ["Screenshot*"]="Pictures/Screenshots"
    ["Screen Recording*"]="Videos/Recordings"
)

# Apply organization rules
organize_files() {
    local source_path=${1:-"$HOME/Downloads"}
    local dest_base=${2:-"$HOME"}

    print_header "File Organization"
    log_info "Source: $source_path"
    log_info "Destination base: $dest_base"

    if [[ ! -d "$source_path" ]]; then
        log_error "Source directory not found: $source_path"
        return 1
    fi

    local session_id
    session_id=$(create_undo_session "Organize files")

    local moved_count=0

    for pattern in "${!ORGANIZE_RULES[@]}"; do
        local dest_subdir="${ORGANIZE_RULES[$pattern]}"
        local dest_dir="$dest_base/$dest_subdir"

        while IFS= read -r -d '' file; do
            local filename
            filename=$(basename "$file")
            local dest="$dest_dir/$filename"

            # Handle duplicates
            if [[ -e "$dest" ]]; then
                local base="${filename%.*}"
                local ext="${filename##*.}"
                local counter=1
                while [[ -e "$dest_dir/${base}_$counter.$ext" ]]; do
                    ((counter++))
                done
                dest="$dest_dir/${base}_$counter.$ext"
            fi

            safe_move "$file" "$dest" "$session_id"
            ((moved_count++))

        done < <(find "$source_path" -maxdepth 1 -type f -name "$pattern" -print0 2>/dev/null)
    done

    log_success "Organized $moved_count files"
    log_info "Session ID: $session_id"
}

# Rename files with consistent naming
rename_files() {
    local search_path=${1:-.}
    local pattern=${2:-"*"}
    local style=${3:-"lowercase"}  # lowercase, uppercase, snake_case, kebab-case

    print_header "Batch Rename"
    log_info "Style: $style"

    local session_id
    session_id=$(create_undo_session "Batch rename")

    local renamed_count=0

    while IFS= read -r -d '' file; do
        local dir
        dir=$(dirname "$file")
        local filename
        filename=$(basename "$file")
        local base="${filename%.*}"
        local ext="${filename##*.}"

        local new_base=""
        case "$style" in
            lowercase)
                new_base=$(echo "$base" | tr '[:upper:]' '[:lower:]')
                ;;
            uppercase)
                new_base=$(echo "$base" | tr '[:lower:]' '[:upper:]')
                ;;
            snake_case)
                new_base=$(echo "$base" | tr '[:upper:]' '[:lower:]' | tr ' -' '_' | tr -s '_')
                ;;
            kebab-case)
                new_base=$(echo "$base" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | tr -s '-')
                ;;
            title)
                new_base=$(echo "$base" | sed 's/.*/\L&/; s/[a-z]*/\u&/g')
                ;;
        esac

        local new_name="$new_base.$ext"

        if [[ "$filename" != "$new_name" ]]; then
            safe_rename "$file" "$new_name" "$session_id"
            ((renamed_count++))
        fi

    done < <(find "$search_path" -maxdepth 1 -type f -name "$pattern" -print0 2>/dev/null)

    log_success "Renamed $renamed_count files"
    log_info "Session ID: $session_id"
}

# Add date prefix to files
add_date_prefix() {
    local search_path=${1:-.}
    local format=${2:-"%Y-%m-%d"}

    print_header "Add Date Prefix"

    local session_id
    session_id=$(create_undo_session "Add date prefix")

    local count=0

    while IFS= read -r -d '' file; do
        local filename
        filename=$(basename "$file")

        # Skip already dated files
        if [[ "$filename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
            continue
        fi

        local mtime
        mtime=$(get_mod_time "$file")
        local date_str
        date_str=$(date -r "$mtime" "+$format" 2>/dev/null || date -d "@$mtime" "+$format" 2>/dev/null)

        local new_name="${date_str}_${filename}"
        safe_rename "$file" "$new_name" "$session_id"
        ((count++))

    done < <(find "$search_path" -maxdepth 1 -type f -print0 2>/dev/null)

    log_success "Added date prefix to $count files"
}

# Remove numbered suffixes (file (1).txt -> file.txt)
remove_duplicates_suffixes() {
    local search_path=${1:-.}

    print_header "Remove Duplicate Suffixes"

    local session_id
    session_id=$(create_undo_session "Remove duplicate suffixes")

    local count=0

    while IFS= read -r -d '' file; do
        local filename
        filename=$(basename "$file")

        # Match patterns like "file (1).txt" or "file-1.txt" or "file_1.txt"
        if [[ "$filename" =~ ^(.+)[\ _-]\(([0-9]+)\)\.(.+)$ ]]; then
            local base="${BASH_REMATCH[1]}"
            local ext="${BASH_REMATCH[3]}"
            local new_name="${base}.${ext}"

            # Only rename if original doesn't exist
            local dir
            dir=$(dirname "$file")
            if [[ ! -e "$dir/$new_name" ]]; then
                safe_rename "$file" "$new_name" "$session_id"
                ((count++))
            fi
        fi

    done < <(find "$search_path" -maxdepth 1 -type f -print0 2>/dev/null)

    log_success "Cleaned up $count filenames"
}

# Flatten nested directories
flatten_directory() {
    local source_path=${1:-.}
    local dest_path=${2:-"$source_path"}

    print_header "Flatten Directory"
    log_info "Moving all files to: $dest_path"

    local session_id
    session_id=$(create_undo_session "Flatten directory")

    local count=0

    while IFS= read -r -d '' file; do
        local filename
        filename=$(basename "$file")
        local dest="$dest_path/$filename"

        # Handle duplicates
        if [[ -e "$dest" && "$file" != "$dest" ]]; then
            local base="${filename%.*}"
            local ext="${filename##*.}"
            local counter=1
            while [[ -e "$dest_path/${base}_$counter.$ext" ]]; do
                ((counter++))
            done
            dest="$dest_path/${base}_$counter.$ext"
        fi

        if [[ "$file" != "$dest" ]]; then
            safe_move "$file" "$dest" "$session_id"
            ((count++))
        fi

    done < <(find "$source_path" -type f -print0 2>/dev/null)

    # Optionally remove empty directories
    if confirm_action "Remove empty directories?"; then
        find "$source_path" -type d -empty -delete 2>/dev/null
    fi

    log_success "Flattened $count files"
}

# Consolidate scattered files by extension
consolidate_by_extension() {
    local search_path=${1:-.}
    local extensions=${2:-"jpg,png,pdf"}

    print_header "Consolidate Files by Extension"

    local session_id
    session_id=$(create_undo_session "Consolidate files")

    IFS=',' read -ra ext_array <<< "$extensions"

    local count=0

    for ext in "${ext_array[@]}"; do
        local dest_dir="$search_path/Consolidated_${ext}"

        while IFS= read -r -d '' file; do
            local filename
            filename=$(basename "$file")
            local dest="$dest_dir/$filename"

            mkdir -p "$dest_dir"

            if [[ "$file" != "$dest" ]]; then
                safe_move "$file" "$dest" "$session_id"
                ((count++))
            fi

        done < <(find "$search_path" -type f -iname "*.${ext}" -print0 2>/dev/null)
    done

    log_success "Consolidated $count files"
}

# Watch directory for new files and auto-organize
watch_and_organize() {
    local watch_path=${1:-"$HOME/Downloads"}
    local dest_base=${2:-"$HOME"}
    local interval=${3:-60}

    print_header "Watch & Organize"
    log_info "Watching: $watch_path"
    log_info "Check interval: ${interval}s"
    log_info "Press Ctrl+C to stop"

    # Track processed files
    declare -A processed

    while true; do
        while IFS= read -r -d '' file; do
            local filename
            filename=$(basename "$file")

            # Skip if already processed
            if [[ -n "${processed[$file]:-}" ]]; then
                continue
            fi

            # Mark as processed
            processed[$file]=1

            # Wait for file to be fully written
            local size1 size2
            size1=$(get_file_size "$file")
            sleep 1
            size2=$(get_file_size "$file")

            if [[ "$size1" != "$size2" ]]; then
                continue  # File still being written
            fi

            # Apply organization rules
            for pattern in "${!ORGANIZE_RULES[@]}"; do
                if [[ "$filename" == $pattern ]]; then
                    local dest_subdir="${ORGANIZE_RULES[$pattern]}"
                    local dest_dir="$dest_base/$dest_subdir"
                    local dest="$dest_dir/$filename"

                    mkdir -p "$dest_dir"

                    log_info "Auto-organizing: $filename -> $dest_subdir/"
                    mv "$file" "$dest"
                    break
                fi
            done

        done < <(find "$watch_path" -maxdepth 1 -type f -newer "$watch_path" -print0 2>/dev/null)

        sleep "$interval"
    done
}

# Load custom rules from config
load_custom_rules() {
    local rules_file=${1:-"$DECLUTTER_RULES_FILE"}

    if [[ ! -f "$rules_file" ]]; then
        return 0
    fi

    # Parse auto_organize section
    local in_section=false
    local current_match=""
    local current_target=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^auto_organize: ]]; then
            in_section=true
            continue
        fi

        if [[ $in_section == true ]]; then
            if [[ "$line" =~ match:[[:space:]]*\"?([^\"]+)\"? ]]; then
                current_match="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ target:[[:space:]]*\"?([^\"]+)\"? ]]; then
                current_target="${BASH_REMATCH[1]}"
                if [[ -n "$current_match" && -n "$current_target" ]]; then
                    ORGANIZE_RULES["$current_match"]="$current_target"
                    current_match=""
                    current_target=""
                fi
            fi
        fi
    done < "$rules_file"
}

export -f organize_files rename_files add_date_prefix
export -f remove_duplicates_suffixes flatten_directory
export -f consolidate_by_extension watch_and_organize load_custom_rules
