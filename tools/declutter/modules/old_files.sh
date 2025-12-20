#!/usr/bin/env bash
# ============================================================================
# Old/Unused File Detection Module
# Find stale, unused, and temporary files
# ============================================================================

set -euo pipefail

_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &

# Find old files (not accessed in X days)
find_old_files() {
    local search_path=${1:-.}
    local days=${2:-90}
    local limit=${3:-100}

    print_header "Old File Finder"
    log_info "Searching in: $search_path"
    log_info "Threshold: $days days since last access"

    local now
    now=$(date +%s)
    local threshold=$((now - days * 86400))

    local results=()
    local total_size=0

    start_spinner "Scanning files..."

    while IFS= read -r -d '' file; do
        local atime
        atime=$(get_access_time "$file")

        if [[ $atime -lt $threshold ]]; then
            local size
            size=$(get_file_size "$file")
            local days_old=$(( (now - atime) / 86400 ))
            results+=("$days_old|$size|$file")
            total_size=$((total_size + size))
        fi
    done < <(find "$search_path" -type f -print0 2>/dev/null)

    stop_spinner

    if [[ ${#results[@]} -eq 0 ]]; then
        log_info "No files older than $days days found"
        return 0
    fi

    # Sort by age (oldest first)
    local sorted
    sorted=$(printf '%s\n' "${results[@]}" | sort -t'|' -k1 -rn | head -n "$limit")

    local count
    count=$(printf '%s\n' "${results[@]}" | wc -l)

    print_subheader "Found $count old files ($(human_size $total_size) total)"

    printf "  ${WHITE}%-40s %10s %15s${NC}\n" "FILE" "DAYS OLD" "SIZE"
    printf "  ${GRAY}%-40s %10s %15s${NC}\n" "$(printf '─%.0s' {1..40})" "$(printf '─%.0s' {1..10})" "$(printf '─%.0s' {1..15})"

    while IFS='|' read -r days_old size filepath; do
        local human
        human=$(human_size "$size")
        local filename
        filename=$(basename "$filepath")

        if [[ ${#filename} -gt 37 ]]; then
            filename="${filename:0:34}..."
        fi

        local color=""
        if [[ $days_old -gt 365 ]]; then
            color="${RED}"
        elif [[ $days_old -gt 180 ]]; then
            color="${YELLOW}"
        fi

        printf "  ${color}%-40s %10d %15s${NC}\n" "$filename" "$days_old" "$human"
    done <<< "$sorted"
}

# Find temporary files
find_temp_files() {
    local search_path=${1:-.}

    print_header "Temporary File Finder"

    local temp_patterns=(
        "*.tmp"
        "*.temp"
        "*.bak"
        "*.swp"
        "*.swo"
        "*~"
        "*.log"
        "*.cache"
        ".*.swp"
        "#*#"
        "*.orig"
        "*.rej"
    )

    local results=()
    local total_size=0

    start_spinner "Scanning for temp files..."

    for pattern in "${temp_patterns[@]}"; do
        while IFS= read -r -d '' file; do
            local size
            size=$(get_file_size "$file")
            results+=("$size|$file")
            total_size=$((total_size + size))
        done < <(find "$search_path" -type f -name "$pattern" -print0 2>/dev/null)
    done

    stop_spinner

    if [[ ${#results[@]} -eq 0 ]]; then
        log_info "No temporary files found"
        return 0
    fi

    print_subheader "Found ${#results[@]} temp files ($(human_size $total_size) total)"

    # Group by extension
    declare -A ext_count
    declare -A ext_size

    for result in "${results[@]}"; do
        IFS='|' read -r size filepath <<< "$result"
        local ext="${filepath##*.}"
        ext_count[$ext]=$((${ext_count[$ext]:-0} + 1))
        ext_size[$ext]=$((${ext_size[$ext]:-0} + size))
    done

    printf "  ${WHITE}%-15s %10s %15s${NC}\n" "TYPE" "COUNT" "SIZE"
    printf "  ${GRAY}%-15s %10s %15s${NC}\n" "$(printf '─%.0s' {1..15})" "$(printf '─%.0s' {1..10})" "$(printf '─%.0s' {1..15})"

    for ext in "${!ext_count[@]}"; do
        printf "  %-15s %10d %15s\n" "*.$ext" "${ext_count[$ext]}" "$(human_size ${ext_size[$ext]})"
    done
}

# Find stale downloads
find_stale_downloads() {
    local downloads_path=${1:-"$HOME/Downloads"}
    local days=${2:-30}

    print_header "Stale Downloads"

    if [[ ! -d "$downloads_path" ]]; then
        log_warn "Downloads folder not found: $downloads_path"
        return 1
    fi

    log_info "Checking: $downloads_path"
    log_info "Age threshold: $days days"

    find_old_files "$downloads_path" "$days"
}

# Find cache directories
find_cache_dirs() {
    local search_path=${1:-$HOME}

    print_header "Cache Directory Finder"

    local cache_patterns=(
        ".cache"
        "__pycache__"
        ".pytest_cache"
        ".mypy_cache"
        ".tox"
        "node_modules/.cache"
        ".npm/_cacache"
        ".gradle/caches"
        ".m2/repository"
        "Library/Caches"
        ".nuget/packages"
    )

    local results=()
    local total_size=0

    start_spinner "Scanning for cache directories..."

    for pattern in "${cache_patterns[@]}"; do
        while IFS= read -r -d '' dir; do
            local size=0
            size=$(du -s "$dir" 2>/dev/null | cut -f1) || size=0
            size=$((size * 1024))  # du returns KB
            results+=("$size|$dir")
            total_size=$((total_size + size))
        done < <(find "$search_path" -type d -name "$pattern" -print0 2>/dev/null)
    done

    stop_spinner

    if [[ ${#results[@]} -eq 0 ]]; then
        log_info "No cache directories found"
        return 0
    fi

    # Sort by size
    local sorted
    sorted=$(printf '%s\n' "${results[@]}" | sort -t'|' -k1 -rn)

    print_subheader "Found ${#results[@]} cache directories ($(human_size $total_size) total)"

    printf "  ${WHITE}%-50s %15s${NC}\n" "DIRECTORY" "SIZE"
    printf "  ${GRAY}%-50s %15s${NC}\n" "$(printf '─%.0s' {1..50})" "$(printf '─%.0s' {1..15})"

    while IFS='|' read -r size dirpath; do
        local display_path="$dirpath"
        if [[ ${#display_path} -gt 47 ]]; then
            display_path="...${display_path: -44}"
        fi
        printf "  %-50s %15s\n" "$display_path" "$(human_size $size)"
    done <<< "$sorted"
}

# Archive old files
archive_old_files() {
    local search_path=${1:-.}
    local days=${2:-365}
    local archive_path=${3:-"$HOME/.declutter/archive"}

    if is_dry_run; then
        log_info "[DRY RUN] Would archive files older than $days days to $archive_path"
    fi

    mkdir -p "$archive_path"

    local session_id
    session_id=$(create_undo_session "Archive old files")

    local count=0
    local now
    now=$(date +%s)
    local threshold=$((now - days * 86400))

    while IFS= read -r -d '' file; do
        local atime
        atime=$(get_access_time "$file")

        if [[ $atime -lt $threshold ]]; then
            local relative_path="${file#$search_path/}"
            local dest="$archive_path/$relative_path"

            safe_move "$file" "$dest" "$session_id"
            ((count++))
        fi
    done < <(find "$search_path" -type f -print0 2>/dev/null)

    log_success "Archived $count files to $archive_path"
    log_info "Session ID: $session_id"
}

# Cleanup temp files
cleanup_temp_files() {
    local search_path=${1:-.}

    local session_id
    session_id=$(create_undo_session "Cleanup temp files")

    local temp_patterns=(
        "*.tmp"
        "*.temp"
        "*.bak"
        "*.swp"
        "*~"
    )

    local count=0

    for pattern in "${temp_patterns[@]}"; do
        while IFS= read -r -d '' file; do
            safe_delete "$file" "$session_id"
            ((count++))
        done < <(find "$search_path" -type f -name "$pattern" -print0 2>/dev/null)
    done

    log_success "Cleaned up $count temp files"
    log_info "Session ID: $session_id"
}

export -f find_old_files find_temp_files find_stale_downloads
export -f find_cache_dirs archive_old_files cleanup_temp_files
