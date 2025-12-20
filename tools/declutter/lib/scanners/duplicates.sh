#!/usr/bin/env bash
#
# Declutter - Duplicate Scanner
# Find duplicate files using hash-based comparison
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_SCANNER_DUPLICATES_LOADED:-}" ]] && return 0
readonly _DECLUTTER_SCANNER_DUPLICATES_LOADED=1

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

# Register this scanner when the engine loads
if declare -F register_scanner &>/dev/null; then
    register_scanner "duplicates" "scan_duplicates" "Find duplicate files"
fi

# =============================================================================
# Duplicate Detection
# =============================================================================

# Main duplicate scanning function
scan_duplicates() {
    local target_path="${1:-$PWD}"
    local output_format="${2:-json}"

    target_path="$(get_absolute_path "$target_path")"

    if [[ ! -d "$target_path" ]]; then
        log_error "Directory not found: $target_path"
        return 1
    fi

    log_debug "Scanning for duplicates in: $target_path"

    # Use czkawka if available (fastest and most accurate)
    if command -v czkawka_cli &>/dev/null; then
        _scan_duplicates_czkawka "$target_path" "$output_format"
    else
        # Fallback to built-in method
        _scan_duplicates_builtin "$target_path" "$output_format"
    fi
}

# Scan using czkawka
_scan_duplicates_czkawka() {
    local target_path="$1"
    local output_format="$2"

    local temp_file
    temp_file="$(mktemp)"

    # Run czkawka with JSON output
    czkawka_cli dup \
        -d "$target_path" \
        -f "$temp_file" \
        --json \
        2>/dev/null

    if [[ ! -s "$temp_file" ]]; then
        echo '{"scan_type":"duplicates","groups":[],"stats":{"total_groups":0,"total_files":0,"wasted_space":0}}'
        rm -f "$temp_file"
        return 0
    fi

    # Transform czkawka output to our format
    local result
    result="$(jq '{
        scan_type: "duplicates",
        timestamp: now | todate,
        target: "'"$target_path"'",
        groups: [.duplicates[]? | {
            hash: .hash,
            size: .files[0].size,
            count: (.files | length),
            files: [.files[] | {
                path: .path,
                size: .size,
                modified: .modified_date
            }]
        }],
        stats: {
            total_groups: (.duplicates | length),
            total_files: ([.duplicates[]?.files | length] | add // 0),
            wasted_space: ([.duplicates[]? | (.files | length - 1) * .files[0].size] | add // 0)
        }
    }' "$temp_file" 2>/dev/null)" || result="{}"

    rm -f "$temp_file"
    echo "$result"
}

# Built-in duplicate scanner (fallback)
_scan_duplicates_builtin() {
    local target_path="$1"
    local output_format="$2"

    local min_size="${CONFIG_SCANNERS[duplicates_min_size]:-1}"
    local hash_algo="${CONFIG_SCANNERS[duplicates_hash_algorithm]:-md5}"
    local include_hidden="${CONFIG_SCANNERS[duplicates_include_hidden]:-false}"

    log_debug "Using built-in scanner (min_size=$min_size, algo=$hash_algo)"

    # Phase 1: Group files by size
    declare -A size_groups
    local find_opts=(-type f -size +"${min_size}c")

    if [[ "$include_hidden" != "true" ]]; then
        find_opts+=(-not -path '*/\.*')
    fi

    while IFS= read -r -d '' file; do
        local size
        size="$(get_file_size "$file")"
        if [[ -n "${size_groups[$size]:-}" ]]; then
            size_groups[$size]+=$'\n'"$file"
        else
            size_groups[$size]="$file"
        fi
    done < <(find "$target_path" "${find_opts[@]}" -print0 2>/dev/null)

    # Phase 2: Hash files with same size
    declare -A hash_groups
    local processed=0
    local total_candidates=0

    for size in "${!size_groups[@]}"; do
        local files="${size_groups[$size]}"
        local file_count
        file_count="$(echo "$files" | wc -l)"

        # Skip unique sizes
        ((file_count < 2)) && continue

        ((total_candidates += file_count))

        while IFS= read -r file; do
            [[ -z "$file" ]] && continue

            local hash
            hash="$(get_file_hash "$file" "$hash_algo")"

            if [[ -n "$hash" ]]; then
                if [[ -n "${hash_groups[$hash]:-}" ]]; then
                    hash_groups[$hash]+=$'\n'"$file"
                else
                    hash_groups[$hash]="$file"
                fi
            fi

            ((processed++))
        done <<< "$files"
    done

    # Phase 3: Build output
    local groups=()
    local total_groups=0
    local total_files=0
    local wasted_space=0

    for hash in "${!hash_groups[@]}"; do
        local files="${hash_groups[$hash]}"
        local file_count
        file_count="$(echo "$files" | grep -c .)"

        # Skip unique hashes
        ((file_count < 2)) && continue

        ((total_groups++))
        ((total_files += file_count))

        # Get size from first file
        local first_file
        first_file="$(echo "$files" | head -1)"
        local file_size
        file_size="$(get_file_size "$first_file")"

        ((wasted_space += file_size * (file_count - 1)))

        # Build file list JSON
        local file_list="["
        local first=true
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            [[ "$first" == "true" ]] || file_list+=","
            first=false

            local mtime
            mtime="$(get_mtime "$file")"

            file_list+="{\"path\":\"$(json_escape "$file")\",\"size\":$file_size,\"mtime\":$mtime}"
        done <<< "$files"
        file_list+="]"

        groups+=("{\"hash\":\"$hash\",\"size\":$file_size,\"count\":$file_count,\"files\":$file_list}")
    done

    # Output JSON
    echo "{"
    echo "  \"scan_type\": \"duplicates\","
    echo "  \"timestamp\": \"$(get_timestamp)\","
    echo "  \"target\": \"$target_path\","
    echo "  \"groups\": ["
    local first=true
    for group in "${groups[@]}"; do
        [[ "$first" == "true" ]] || echo ","
        first=false
        echo "    $group"
    done
    echo ""
    echo "  ],"
    echo "  \"stats\": {"
    echo "    \"total_groups\": $total_groups,"
    echo "    \"total_files\": $total_files,"
    echo "    \"wasted_space\": $wasted_space"
    echo "  }"
    echo "}"
}

# =============================================================================
# Helper Functions
# =============================================================================

# Get duplicate groups from scan result
get_duplicate_groups() {
    local scan_result="$1"
    echo "$scan_result" | jq -r '.groups[]'
}

# Get files to delete (keep first/newest/oldest)
get_duplicates_to_delete() {
    local scan_result="$1"
    local keep_strategy="${2:-first}"  # first, newest, oldest

    local jq_filter
    case "$keep_strategy" in
        newest)
            jq_filter='.groups[] | .files | sort_by(.mtime) | reverse | .[1:][] | .path'
            ;;
        oldest)
            jq_filter='.groups[] | .files | sort_by(.mtime) | .[1:][] | .path'
            ;;
        *)  # first
            jq_filter='.groups[] | .files[1:][] | .path'
            ;;
    esac

    echo "$scan_result" | jq -r "$jq_filter" 2>/dev/null
}

# Print duplicate summary
print_duplicate_summary() {
    local scan_result="$1"

    local groups files wasted
    groups="$(echo "$scan_result" | jq -r '.stats.total_groups // 0')"
    files="$(echo "$scan_result" | jq -r '.stats.total_files // 0')"
    wasted="$(echo "$scan_result" | jq -r '.stats.wasted_space // 0')"

    print_section "Duplicate Scan Results"
    print_kv "Duplicate groups" "$groups"
    print_kv "Total files" "$files"
    print_kv "Wasted space" "$(format_bytes "$wasted")"
}
