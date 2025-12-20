#!/usr/bin/env bash
# ============================================================================
# Smart Categorization Module
# Auto-sort and categorize files
# ============================================================================

set -euo pipefail

_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &

# File category definitions
declare -A FILE_CATEGORIES=(
    [documents]="pdf doc docx txt rtf odt xls xlsx ppt pptx csv md rst tex"
    [images]="jpg jpeg png gif bmp svg webp ico tiff raw heic cr2 nef"
    [videos]="mp4 mkv avi mov wmv flv webm m4v mpg mpeg 3gp"
    [audio]="mp3 wav flac aac ogg wma m4a opus aiff"
    [archives]="zip tar gz rar 7z bz2 xz tgz tbz2 iso dmg"
    [code]="py js ts jsx tsx go rs java c cpp h hpp rb php sh bash zsh ps1 cs swift kt"
    [data]="json yaml yml xml sql db sqlite csv tsv parquet"
    [executables]="exe msi app dmg deb rpm pkg"
    [fonts]="ttf otf woff woff2 eot"
    [ebooks]="epub mobi azw3 pdf"
)

# Junk file patterns
JUNK_FILES=(
    ".DS_Store"
    "Thumbs.db"
    "desktop.ini"
    ".localized"
    "Icon\r"
    ".Spotlight-V100"
    ".Trashes"
    ".fseventsd"
    "__MACOSX"
)

# Get file category
get_file_category() {
    local file=$1
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    for category in "${!FILE_CATEGORIES[@]}"; do
        if [[ " ${FILE_CATEGORIES[$category]} " =~ " $ext " ]]; then
            echo "$category"
            return 0
        fi
    done

    echo "other"
}

# Analyze file categories in a directory
analyze_categories() {
    local search_path=${1:-.}

    print_header "File Category Analysis"
    log_info "Analyzing: $search_path"

    declare -A category_count
    declare -A category_size
    local total_files=0
    local total_size=0

    start_spinner "Categorizing files..."

    while IFS= read -r -d '' file; do
        local category
        category=$(get_file_category "$file")
        local size
        size=$(get_file_size "$file")

        category_count[$category]=$((${category_count[$category]:-0} + 1))
        category_size[$category]=$((${category_size[$category]:-0} + size))
        ((total_files++))
        total_size=$((total_size + size))
    done < <(find "$search_path" -type f -print0 2>/dev/null)

    stop_spinner

    print_subheader "Category Breakdown"

    printf "  ${WHITE}%-15s %10s %8s %15s %8s${NC}\n" "CATEGORY" "FILES" "%" "SIZE" "%"
    printf "  ${GRAY}%-15s %10s %8s %15s %8s${NC}\n" \
        "$(printf '─%.0s' {1..15})" "$(printf '─%.0s' {1..10})" "$(printf '─%.0s' {1..8})" \
        "$(printf '─%.0s' {1..15})" "$(printf '─%.0s' {1..8})"

    # Sort categories by count
    for category in $(echo "${!category_count[@]}" | tr ' ' '\n' | sort); do
        local count=${category_count[$category]}
        local size=${category_size[$category]}
        local count_pct=$((count * 100 / total_files))
        local size_pct=0
        [[ $total_size -gt 0 ]] && size_pct=$((size * 100 / total_size))

        local color=""
        case "$category" in
            documents) color="${BLUE}" ;;
            images) color="${GREEN}" ;;
            videos) color="${PURPLE}" ;;
            audio) color="${CYAN}" ;;
            code) color="${YELLOW}" ;;
            other) color="${GRAY}" ;;
        esac

        printf "  ${color}%-15s${NC} %10d %7d%% %15s %7d%%\n" \
            "$category" "$count" "$count_pct" "$(human_size $size)" "$size_pct"
    done

    echo ""
    printf "  ${WHITE}%-15s %10d %8s %15s${NC}\n" \
        "TOTAL" "$total_files" "" "$(human_size $total_size)"
}

# Find junk/orphan files
find_junk_files() {
    local search_path=${1:-.}

    print_header "Junk File Finder"

    local results=()
    local total_size=0

    start_spinner "Scanning for junk files..."

    for pattern in "${JUNK_FILES[@]}"; do
        while IFS= read -r -d '' file; do
            local size
            size=$(get_file_size "$file" 2>/dev/null || echo "0")
            results+=("$size|$file")
            total_size=$((total_size + size))
        done < <(find "$search_path" -name "$pattern" -print0 2>/dev/null)
    done

    stop_spinner

    if [[ ${#results[@]} -eq 0 ]]; then
        log_info "No junk files found"
        return 0
    fi

    print_subheader "Found ${#results[@]} junk files ($(human_size $total_size))"

    for result in "${results[@]}"; do
        IFS='|' read -r size filepath <<< "$result"
        echo "  ${RED}•${NC} $filepath ($(human_size $size))"
    done
}

# Detect project folders
detect_project_folders() {
    local search_path=${1:-.}

    print_header "Project Folder Detection"

    local project_markers=(
        "package.json:Node.js"
        "Cargo.toml:Rust"
        "go.mod:Go"
        "requirements.txt:Python"
        "setup.py:Python"
        "pyproject.toml:Python"
        "pom.xml:Java/Maven"
        "build.gradle:Java/Gradle"
        "Gemfile:Ruby"
        "composer.json:PHP"
        "*.csproj:C#/.NET"
        "Makefile:Make"
        ".git:Git Repository"
    )

    local found_projects=()

    start_spinner "Detecting projects..."

    for marker_info in "${project_markers[@]}"; do
        IFS=':' read -r marker type <<< "$marker_info"

        while IFS= read -r -d '' file; do
            local project_dir
            project_dir=$(dirname "$file")
            local project_name
            project_name=$(basename "$project_dir")
            found_projects+=("$type|$project_name|$project_dir")
        done < <(find "$search_path" -maxdepth 3 -name "$marker" -print0 2>/dev/null)
    done

    stop_spinner

    if [[ ${#found_projects[@]} -eq 0 ]]; then
        log_info "No project folders found"
        return 0
    fi

    # Deduplicate
    local unique_projects
    unique_projects=$(printf '%s\n' "${found_projects[@]}" | sort -u)

    print_subheader "Detected Projects"

    printf "  ${WHITE}%-15s %-25s %s${NC}\n" "TYPE" "PROJECT" "PATH"
    printf "  ${GRAY}%-15s %-25s %s${NC}\n" \
        "$(printf '─%.0s' {1..15})" "$(printf '─%.0s' {1..25})" "$(printf '─%.0s' {1..30})"

    while IFS='|' read -r type name path; do
        printf "  ${CYAN}%-15s${NC} %-25s ${GRAY}%s${NC}\n" "$type" "$name" "$path"
    done <<< "$unique_projects"
}

# Organize files by category
organize_by_category() {
    local source_path=${1:-.}
    local dest_base=${2:-"$source_path/Organized"}

    print_header "Organize by Category"

    if is_dry_run; then
        log_info "[DRY RUN] Preview mode"
    fi

    local session_id
    session_id=$(create_undo_session "Organize by category")

    local moved_count=0

    while IFS= read -r -d '' file; do
        # Skip directories and already organized files
        [[ -d "$file" ]] && continue
        [[ "$file" == *"/Organized/"* ]] && continue

        local category
        category=$(get_file_category "$file")
        local filename
        filename=$(basename "$file")
        local dest_dir="$dest_base/$category"
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

    done < <(find "$source_path" -maxdepth 1 -type f -print0 2>/dev/null)

    log_success "Organized $moved_count files into categories"
    log_info "Session ID: $session_id"
}

# Clean up junk files
cleanup_junk() {
    local search_path=${1:-.}

    local session_id
    session_id=$(create_undo_session "Cleanup junk files")

    local count=0

    for pattern in "${JUNK_FILES[@]}"; do
        while IFS= read -r -d '' file; do
            safe_delete "$file" "$session_id"
            ((count++))
        done < <(find "$search_path" -name "$pattern" -print0 2>/dev/null)
    done

    log_success "Removed $count junk files"
    log_info "Session ID: $session_id"
}

export -f get_file_category analyze_categories find_junk_files
export -f detect_project_folders organize_by_category cleanup_junk
