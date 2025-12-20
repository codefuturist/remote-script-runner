#!/usr/bin/env bash
#
# Declutter - Large Files Scanner
# Find files above configurable size thresholds
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_SCANNER_LARGE_FILES_LOADED:-}" ]] && return 0
readonly _DECLUTTER_SCANNER_LARGE_FILES_LOADED=1

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
    register_scanner "large_files" "scan_large_files" "Find large files"
    register_scanner "big" "scan_large_files" "Find large files (alias)"
fi

# =============================================================================
# Large File Detection
# =============================================================================

# Main scanning function
scan_large_files() {
    local target_path="${1:-$PWD}"
    local threshold="${2:-}"
    local sort_by="${3:-size}"  # size, atime, mtime
    local limit="${4:-50}"

    target_path="$(get_absolute_path "$target_path")"

    if [[ ! -d "$target_path" ]]; then
        log_error "Directory not found: $target_path"
        return 1
    fi

    # Get threshold from config if not provided
    if [[ -z "$threshold" ]]; then
        threshold="${CONFIG_SCANNERS[large_files_threshold]:-104857600}"  # 100MB default
    else
        threshold="$(parse_size "$threshold")"
    fi

    log_debug "Scanning for files larger than $(format_bytes "$threshold") in: $target_path"

    # Use czkawka if available
    if command -v czkawka_cli &>/dev/null; then
        _scan_large_czkawka "$target_path" "$limit" "$sort_by"
    else
        _scan_large_builtin "$target_path" "$threshold" "$limit" "$sort_by"
    fi
}

# Scan using czkawka
_scan_large_czkawka() {
    local target_path="$1"
    local limit="$2"
    local sort_by="$3"

    local temp_file
    temp_file="$(mktemp)"

    czkawka_cli big \
        -d "$target_path" \
        -n "$limit" \
        -f "$temp_file" \
        --json \
        2>/dev/null

    if [[ ! -s "$temp_file" ]]; then
        echo '{"scan_type":"large_files","items":[],"stats":{"total_files":0,"total_size":0}}'
        rm -f "$temp_file"
        return 0
    fi

    # Transform to our format
    local result
    result="$(jq '{
        scan_type: "large_files",
        timestamp: now | todate,
        target: "'"$target_path"'",
        items: [.big_files[]? | {
            path: .path,
            size: .size,
            size_human: (.size | tonumber | if . >= 1073741824 then "\(. / 1073741824 | floor)GB" elif . >= 1048576 then "\(. / 1048576 | floor)MB" else "\(. / 1024 | floor)KB" end),
            category: (
                if .path | test("\\.(mp4|mkv|avi|mov|wmv)$"; "i") then "video"
                elif .path | test("\\.(mp3|flac|wav|aac)$"; "i") then "audio"
                elif .path | test("\\.(zip|tar|gz|7z|rar)$"; "i") then "archive"
                elif .path | test("\\.(iso|dmg|img)$"; "i") then "disk_image"
                else "other"
                end
            )
        }],
        stats: {
            total_files: (.big_files | length),
            total_size: ([.big_files[]?.size | tonumber] | add // 0)
        }
    }' "$temp_file" 2>/dev/null)" || result="{}"

    rm -f "$temp_file"
    echo "$result"
}

# Built-in large file scanner
_scan_large_builtin() {
    local target_path="$1"
    local threshold="$2"
    local limit="$3"
    local sort_by="$4"

    local items=()
    local total_size=0
    local count=0

    # Find large files
    local sort_flag
    case "$sort_by" in
        atime) sort_flag="-u" ;;  # Access time
        mtime) sort_flag="-t" ;;  # Modification time
        *)     sort_flag="-S" ;;  # Size (default)
    esac

    while IFS= read -r line; do
        local size path
        size="$(echo "$line" | awk '{print $1}')"
        path="$(echo "$line" | awk '{$1=""; print substr($0,2)}')"

        ((size < threshold)) && continue
        ((count >= limit)) && break

        ((total_size += size))
        ((count++))

        local category
        category="$(get_file_category "$path")"

        local mtime atime
        mtime="$(get_mtime "$path")"
        atime="$(get_atime "$path")"

        items+=("{\"path\":\"$(json_escape "$path")\",\"size\":$size,\"size_human\":\"$(format_bytes "$size")\",\"mtime\":$mtime,\"atime\":$atime,\"category\":\"$category\"}")
    done < <(find "$target_path" -type f -exec stat -f"%z %N" {} \; 2>/dev/null | sort -rn || \
             find "$target_path" -type f -printf "%s %p\n" 2>/dev/null | sort -rn)

    # Output JSON
    echo "{"
    echo "  \"scan_type\": \"large_files\","
    echo "  \"timestamp\": \"$(get_timestamp)\","
    echo "  \"target\": \"$target_path\","
    echo "  \"threshold\": $threshold,"
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
# Helper Functions
# =============================================================================

# Get files to delete from scan result
get_large_files_to_delete() {
    local scan_result="$1"
    echo "$scan_result" | jq -r '.items[].path' 2>/dev/null
}

# Filter by category
filter_by_category() {
    local scan_result="$1"
    local category="$2"

    echo "$scan_result" | jq ".items | map(select(.category == \"$category\"))" 2>/dev/null
}

# Print summary
print_large_files_summary() {
    local scan_result="$1"

    local count total_size
    count="$(echo "$scan_result" | jq -r '.stats.total_files // 0')"
    total_size="$(echo "$scan_result" | jq -r '.stats.total_size // 0')"

    print_section "Large Files Scan Results"
    print_kv "Files found" "$count"
    print_kv "Total size" "$(format_bytes "$total_size")"

    # Category breakdown
    echo ""
    echo "By category:"
    echo "$scan_result" | jq -r '.items | group_by(.category) | .[] | "  \(.[0].category): \(length) files"' 2>/dev/null
}
