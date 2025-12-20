#!/usr/bin/env bash
#
# Declutter - Old Files Scanner
# Find files not accessed in X days/months
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_SCANNER_OLD_FILES_LOADED:-}" ]] && return 0
readonly _DECLUTTER_SCANNER_OLD_FILES_LOADED=1

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
# Scanner Registration
# =============================================================================

if declare -F register_scanner &>/dev/null; then
    register_scanner "old_files" "scan_old_files" "Find old/unused files"
    register_scanner "old" "scan_old_files" "Find old/unused files (alias)"
    register_scanner "unused" "scan_old_files" "Find old/unused files (alias)"
fi

# =============================================================================
# Old File Detection
# =============================================================================

# Main scanning function
scan_old_files() {
    local target_path="${1:-$PWD}"
    local age_days="${2:-}"
    local use_atime="${3:-}"

    target_path="$(get_absolute_path "$target_path")"

    if [[ ! -d "$target_path" ]]; then
        log_error "Directory not found: $target_path"
        return 1
    fi

    # Get settings from config if not provided
    if [[ -z "$age_days" ]]; then
        age_days="${CONFIG_SCANNERS[old_files_age_days]:-90}"
    fi

    if [[ -z "$use_atime" ]]; then
        use_atime="${CONFIG_SCANNERS[old_files_use_atime]:-true}"
    fi

    log_debug "Scanning for files older than $age_days days in: $target_path"

    # Use fd if available (faster)
    if command -v fd &>/dev/null; then
        _scan_old_fd "$target_path" "$age_days" "$use_atime"
    else
        _scan_old_find "$target_path" "$age_days" "$use_atime"
    fi
}

# Scan using fd
_scan_old_fd() {
    local target_path="$1"
    local age_days="$2"
    local use_atime="$3"

    local items=()
    local total_size=0
    local count=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ -f "$file" ]] || continue

        local size mtime atime age_type age
        size="$(get_file_size "$file")"
        mtime="$(get_mtime "$file")"
        atime="$(get_atime "$file")"

        if [[ "$use_atime" == "true" ]]; then
            age_type="access"
            age="$(days_since "$atime")"
        else
            age_type="modify"
            age="$(days_since "$mtime")"
        fi

        local category
        category="$(get_file_category "$file")"

        ((total_size += size))
        ((count++))

        items+=("{\"path\":\"$(json_escape "$file")\",\"size\":$size,\"mtime\":$mtime,\"atime\":$atime,\"age_days\":$age,\"age_type\":\"$age_type\",\"category\":\"$category\"}")

    done < <(fd . "$target_path" --type f --changed-before "${age_days}d" 2>/dev/null)

    _output_old_files_json "$target_path" "$age_days" "$use_atime" "$count" "$total_size" "${items[@]}"
}

# Scan using find
_scan_old_find() {
    local target_path="$1"
    local age_days="$2"
    local use_atime="$3"

    local items=()
    local total_size=0
    local count=0

    local time_flag
    if [[ "$use_atime" == "true" ]]; then
        time_flag="-atime"
    else
        time_flag="-mtime"
    fi

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ -f "$file" ]] || continue

        local size mtime atime age_type age
        size="$(get_file_size "$file")"
        mtime="$(get_mtime "$file")"
        atime="$(get_atime "$file")"

        if [[ "$use_atime" == "true" ]]; then
            age_type="access"
            age="$(days_since "$atime")"
        else
            age_type="modify"
            age="$(days_since "$mtime")"
        fi

        local category
        category="$(get_file_category "$file")"

        ((total_size += size))
        ((count++))

        items+=("{\"path\":\"$(json_escape "$file")\",\"size\":$size,\"mtime\":$mtime,\"atime\":$atime,\"age_days\":$age,\"age_type\":\"$age_type\",\"category\":\"$category\"}")

    done < <(find "$target_path" -type f "$time_flag" +"$age_days" 2>/dev/null)

    _output_old_files_json "$target_path" "$age_days" "$use_atime" "$count" "$total_size" "${items[@]}"
}

# Output JSON
_output_old_files_json() {
    local target_path="$1"
    local age_days="$2"
    local use_atime="$3"
    local count="$4"
    local total_size="$5"
    shift 5
    local items=("$@")

    echo "{"
    echo "  \"scan_type\": \"old_files\","
    echo "  \"timestamp\": \"$(get_timestamp)\","
    echo "  \"target\": \"$target_path\","
    echo "  \"age_days\": $age_days,"
    echo "  \"use_atime\": $use_atime,"
    echo "  \"items\": ["
    local first=true
    for item in "${items[@]}"; do
        [[ "$first" == "true" ]] || echo ","
        first=false
        echo "    $item"
    done
    echo ""
    echo "  ],"
    echo "  \"stats\": {"
    echo "    \"total_files\": $count,"
    echo "    \"total_size\": $total_size"
    echo "  }"
    echo "}"
}

# =============================================================================
# Specialized Scanners
# =============================================================================

# Scan Downloads folder for old files
scan_old_downloads() {
    local downloads_dir="${1:-$HOME/Downloads}"
    local age_days="${2:-30}"

    if [[ ! -d "$downloads_dir" ]]; then
        log_warn "Downloads directory not found: $downloads_dir"
        return 1
    fi

    scan_old_files "$downloads_dir" "$age_days" "true"
}

# Scan for stale cache files
scan_stale_cache() {
    local age_days="${1:-7}"

    local cache_dirs=(
        "$HOME/.cache"
        "$HOME/Library/Caches"
        "/tmp"
    )

    local all_items=()
    local total_size=0
    local total_count=0

    for cache_dir in "${cache_dirs[@]}"; do
        if [[ -d "$cache_dir" ]]; then
            local result
            result="$(scan_old_files "$cache_dir" "$age_days" "true")"

            local count size
            count="$(echo "$result" | jq -r '.stats.total_files // 0')"
            size="$(echo "$result" | jq -r '.stats.total_size // 0')"

            ((total_count += count))
            ((total_size += size))
        fi
    done

    echo "{"
    echo "  \"scan_type\": \"stale_cache\","
    echo "  \"timestamp\": \"$(get_timestamp)\","
    echo "  \"age_days\": $age_days,"
    echo "  \"stats\": {"
    echo "    \"total_files\": $total_count,"
    echo "    \"total_size\": $total_size"
    echo "  }"
    echo "}"
}

# =============================================================================
# Helper Functions
# =============================================================================

# Get files to delete from scan result
get_old_files_to_delete() {
    local scan_result="$1"
    echo "$scan_result" | jq -r '.items[].path' 2>/dev/null
}

# Filter by age range
filter_by_age() {
    local scan_result="$1"
    local min_days="${2:-0}"
    local max_days="${3:-99999}"

    echo "$scan_result" | jq ".items | map(select(.age_days >= $min_days and .age_days <= $max_days))" 2>/dev/null
}

# Print summary
print_old_files_summary() {
    local scan_result="$1"

    local count total_size age_days
    count="$(echo "$scan_result" | jq -r '.stats.total_files // 0')"
    total_size="$(echo "$scan_result" | jq -r '.stats.total_size // 0')"
    age_days="$(echo "$scan_result" | jq -r '.age_days // 0')"

    print_section "Old Files Scan Results"
    print_kv "Age threshold" "${age_days} days"
    print_kv "Files found" "$count"
    print_kv "Total size" "$(format_bytes "$total_size")"

    # Age breakdown
    echo ""
    echo "By age:"
    echo "$scan_result" | jq -r '
        .items |
        group_by(if .age_days < 180 then "3-6 months"
                elif .age_days < 365 then "6-12 months"
                else "1+ years" end) |
        .[] | "  \(.[0].age_days | if . < 180 then "3-6 months" elif . < 365 then "6-12 months" else "1+ years" end): \(length) files"
    ' 2>/dev/null
}
