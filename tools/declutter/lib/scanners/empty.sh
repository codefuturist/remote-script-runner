#!/usr/bin/env bash
#
# Declutter - Empty Files Scanner
# Find empty files and directories
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_SCANNER_EMPTY_LOADED:-}" ]] && return 0
readonly _DECLUTTER_SCANNER_EMPTY_LOADED=1

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
    register_scanner "empty" "scan_empty" "Find empty files and directories"
    register_scanner "empty_files" "scan_empty_files" "Find empty files"
    register_scanner "empty_dirs" "scan_empty_dirs" "Find empty directories"
fi

# =============================================================================
# Empty Detection
# =============================================================================

# Main scanning function (both files and directories)
scan_empty() {
    local target_path="${1:-$PWD}"

    target_path="$(get_absolute_path "$target_path")"

    if [[ ! -d "$target_path" ]]; then
        log_error "Directory not found: $target_path"
        return 1
    fi

    log_debug "Scanning for empty items in: $target_path"

    # Use czkawka if available
    if command -v czkawka_cli &>/dev/null; then
        _scan_empty_czkawka "$target_path"
    else
        _scan_empty_builtin "$target_path"
    fi
}

# Scan using czkawka
_scan_empty_czkawka() {
    local target_path="$1"

    local files_temp dirs_temp
    files_temp="$(mktemp)"
    dirs_temp="$(mktemp)"

    # Scan empty files
    czkawka_cli empty-files -d "$target_path" -f "$files_temp" --json 2>/dev/null

    # Scan empty directories
    czkawka_cli empty-folders -d "$target_path" -f "$dirs_temp" --json 2>/dev/null

    # Combine results
    local empty_files empty_dirs
    empty_files="$(jq -r '.empty_files // []' "$files_temp" 2>/dev/null || echo '[]')"
    empty_dirs="$(jq -r '.empty_folders // []' "$dirs_temp" 2>/dev/null || echo '[]')"

    local files_count dirs_count
    files_count="$(echo "$empty_files" | jq 'length' 2>/dev/null || echo 0)"
    dirs_count="$(echo "$empty_dirs" | jq 'length' 2>/dev/null || echo 0)"

    rm -f "$files_temp" "$dirs_temp"

    # Output
    cat << EOF
{
  "scan_type": "empty",
  "timestamp": "$(get_timestamp)",
  "target": "$target_path",
  "empty_files": $(echo "$empty_files" | jq '[.[]? | {path: .path}]' 2>/dev/null || echo '[]'),
  "empty_dirs": $(echo "$empty_dirs" | jq '[.[]? | {path: .path}]' 2>/dev/null || echo '[]'),
  "stats": {
    "empty_files": $files_count,
    "empty_dirs": $dirs_count
  }
}
EOF
}

# Built-in scanner
_scan_empty_builtin() {
    local target_path="$1"

    local empty_files=()
    local empty_dirs=()

    # Find empty files
    while IFS= read -r file; do
        [[ -n "$file" ]] && empty_files+=("{\"path\":\"$(json_escape "$file")\"}")
    done < <(find "$target_path" -type f -empty 2>/dev/null)

    # Find empty directories
    while IFS= read -r dir; do
        [[ -n "$dir" ]] && empty_dirs+=("{\"path\":\"$(json_escape "$dir")\"}")
    done < <(find "$target_path" -type d -empty 2>/dev/null)

    # Output JSON
    echo "{"
    echo "  \"scan_type\": \"empty\","
    echo "  \"timestamp\": \"$(get_timestamp)\","
    echo "  \"target\": \"$target_path\","
    echo "  \"empty_files\": ["
    local first=true
    for item in "${empty_files[@]}"; do
        [[ "$first" == "true" ]] || echo ","
        first=false
        echo "    $item"
    done
    echo ""
    echo "  ],"
    echo "  \"empty_dirs\": ["
    first=true
    for item in "${empty_dirs[@]}"; do
        [[ "$first" == "true" ]] || echo ","
        first=false
        echo "    $item"
    done
    echo ""
    echo "  ],"
    echo "  \"stats\": {"
    echo "    \"empty_files\": ${#empty_files[@]},"
    echo "    \"empty_dirs\": ${#empty_dirs[@]}"
    echo "  }"
    echo "}"
}

# Scan only empty files
scan_empty_files() {
    local target_path="${1:-$PWD}"

    target_path="$(get_absolute_path "$target_path")"

    local items=()

    while IFS= read -r file; do
        [[ -n "$file" ]] && items+=("{\"path\":\"$(json_escape "$file")\"}")
    done < <(find "$target_path" -type f -empty 2>/dev/null)

    echo "{"
    echo "  \"scan_type\": \"empty_files\","
    echo "  \"timestamp\": \"$(get_timestamp)\","
    echo "  \"target\": \"$target_path\","
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
    echo "    \"total\": ${#items[@]}"
    echo "  }"
    echo "}"
}

# Scan only empty directories
scan_empty_dirs() {
    local target_path="${1:-$PWD}"

    target_path="$(get_absolute_path "$target_path")"

    local items=()

    while IFS= read -r dir; do
        [[ -n "$dir" ]] && items+=("{\"path\":\"$(json_escape "$dir")\"}")
    done < <(find "$target_path" -type d -empty 2>/dev/null)

    echo "{"
    echo "  \"scan_type\": \"empty_dirs\","
    echo "  \"timestamp\": \"$(get_timestamp)\","
    echo "  \"target\": \"$target_path\","
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
    echo "    \"total\": ${#items[@]}"
    echo "  }"
    echo "}"
}

# =============================================================================
# Helper Functions
# =============================================================================

# Get all empty items (files + dirs) from scan result
get_empty_items() {
    local scan_result="$1"

    {
        echo "$scan_result" | jq -r '.empty_files[]?.path // empty' 2>/dev/null
        echo "$scan_result" | jq -r '.empty_dirs[]?.path // empty' 2>/dev/null
    } | sort -r  # Sort reverse so dirs are deleted after contents
}

# Print summary
print_empty_summary() {
    local scan_result="$1"

    local files dirs
    files="$(echo "$scan_result" | jq -r '.stats.empty_files // 0')"
    dirs="$(echo "$scan_result" | jq -r '.stats.empty_dirs // 0')"

    print_section "Empty Items Scan Results"
    print_kv "Empty files" "$files"
    print_kv "Empty directories" "$dirs"
}
