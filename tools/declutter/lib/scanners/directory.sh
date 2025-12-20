#!/usr/bin/env bash
#
# Declutter - Directory Analysis Scanner
# Tree view with size breakdown per folder
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_SCANNER_DIRECTORY_LOADED:-}" ]] && return 0
readonly _DECLUTTER_SCANNER_DIRECTORY_LOADED=1

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
    register_scanner "directory" "scan_directory" "Analyze directory structure and sizes"
    register_scanner "analyze" "scan_directory" "Analyze directory structure (alias)"
    register_scanner "usage" "scan_disk_usage" "Show disk usage summary"
fi

# =============================================================================
# Directory Analysis
# =============================================================================

# Main analysis function
scan_directory() {
    local target_path="${1:-$PWD}"
    local depth="${2:-2}"

    target_path="$(get_absolute_path "$target_path")"

    if [[ ! -d "$target_path" ]]; then
        log_error "Directory not found: $target_path"
        return 1
    fi

    log_debug "Analyzing directory: $target_path (depth=$depth)"

    local total_size file_count dir_count
    total_size="$(du -sk "$target_path" 2>/dev/null | cut -f1)"
    total_size=$((total_size * 1024))
    file_count="$(find "$target_path" -type f 2>/dev/null | wc -l | tr -d ' ')"
    dir_count="$(find "$target_path" -type d 2>/dev/null | wc -l | tr -d ' ')"

    # Build tree
    local children
    children="$(_analyze_children "$target_path" "$depth" "$total_size")"

    # Find bloated directories
    local bloated
    bloated="$(_find_bloated_dirs "$target_path" "$total_size")"

    # Output
    cat << EOF
{
  "scan_type": "directory_analysis",
  "timestamp": "$(get_timestamp)",
  "root": "$target_path",
  "tree": {
    "name": "$(basename "$target_path")",
    "path": "$target_path",
    "size": $total_size,
    "size_human": "$(format_bytes "$total_size")",
    "file_count": $file_count,
    "dir_count": $dir_count,
    "children": $children
  },
  "bloated_dirs": $bloated,
  "stats": {
    "total_size": $total_size,
    "file_count": $file_count,
    "dir_count": $dir_count
  }
}
EOF
}

# Analyze children of a directory
_analyze_children() {
    local path="$1"
    local depth="$2"
    local parent_size="$3"

    if ((depth <= 0)); then
        echo "[]"
        return
    fi

    local items=()

    while IFS=$'\t' read -r size name; do
        [[ -z "$name" ]] && continue

        local item_path="$path/$name"
        local size_bytes=$((size * 1024))
        local percentage=0

        if ((parent_size > 0)); then
            percentage=$((size_bytes * 100 / parent_size))
        fi

        local is_dir=false
        local is_bloated=false
        local bloat_reason=""

        if [[ -d "$item_path" ]]; then
            is_dir=true

            # Check for known bloat patterns
            case "$name" in
                node_modules)
                    is_bloated=true
                    bloat_reason="npm_dependencies"
                    ;;
                .git)
                    if ((size_bytes > 104857600)); then  # > 100MB
                        is_bloated=true
                        bloat_reason="large_git_history"
                    fi
                    ;;
                __pycache__|.pytest_cache|.mypy_cache)
                    is_bloated=true
                    bloat_reason="python_cache"
                    ;;
                target)
                    is_bloated=true
                    bloat_reason="rust_build"
                    ;;
                vendor)
                    is_bloated=true
                    bloat_reason="vendor_dependencies"
                    ;;
            esac
        fi

        local item_json="{\"name\":\"$name\",\"size\":$size_bytes,\"size_human\":\"$(format_bytes "$size_bytes")\",\"percentage\":$percentage,\"is_dir\":$is_dir"

        if [[ "$is_bloated" == "true" ]]; then
            item_json+=",\"is_bloated\":true,\"bloat_reason\":\"$bloat_reason\""
        fi

        # Recurse for directories
        if [[ "$is_dir" == "true" ]] && ((depth > 1)); then
            local sub_children
            sub_children="$(_analyze_children "$item_path" $((depth - 1)) "$size_bytes")"
            item_json+=",\"children\":$sub_children"
        fi

        item_json+="}"
        items+=("$item_json")

    done < <(du -sk "$path"/* 2>/dev/null | sort -rn | head -20)

    # Output array
    echo -n "["
    local first=true
    for item in "${items[@]}"; do
        [[ "$first" == "true" ]] || echo -n ","
        first=false
        echo -n "$item"
    done
    echo "]"
}

# Find bloated directories
_find_bloated_dirs() {
    local path="$1"
    local total_size="$2"

    local bloated=()

    # Known bloat patterns
    local patterns=(
        "node_modules:npm_dependencies"
        ".git:git_history"
        "__pycache__:python_cache"
        ".pytest_cache:test_cache"
        "target:rust_build"
        "vendor:vendor_deps"
        "dist:build_output"
        "build:build_output"
        ".next:nextjs_build"
        ".nuxt:nuxt_build"
    )

    for pattern_entry in "${patterns[@]}"; do
        local pattern="${pattern_entry%%:*}"
        local reason="${pattern_entry#*:}"

        while IFS= read -r dir; do
            [[ -z "$dir" ]] && continue

            local size
            size="$(du -sk "$dir" 2>/dev/null | cut -f1)"
            size=$((size * 1024))

            # Only include if significant (> 10MB)
            if ((size > 10485760)); then
                bloated+=("{\"path\":\"$(json_escape "$dir")\",\"size\":$size,\"size_human\":\"$(format_bytes "$size")\",\"reason\":\"$reason\"}")
            fi
        done < <(find "$path" -type d -name "$pattern" 2>/dev/null)
    done

    # Output array
    echo -n "["
    local first=true
    for item in "${bloated[@]}"; do
        [[ "$first" == "true" ]] || echo -n ","
        first=false
        echo -n "$item"
    done
    echo "]"
}

# =============================================================================
# Disk Usage Display
# =============================================================================

# Show disk usage (visual)
scan_disk_usage() {
    local target_path="${1:-$PWD}"
    local depth="${2:-2}"

    target_path="$(get_absolute_path "$target_path")"

    # Use dust if available
    if command -v dust &>/dev/null; then
        dust -d "$depth" "$target_path"
        return
    fi

    # Use ncdu if available
    if command -v ncdu &>/dev/null; then
        ncdu "$target_path"
        return
    fi

    # Fallback to du
    print_section "Disk Usage: $target_path"
    du -h -d "$depth" "$target_path" 2>/dev/null | sort -hr | head -30
}

# =============================================================================
# Tree Display
# =============================================================================

# Print tree with sizes
print_size_tree() {
    local scan_result="$1"
    local depth="${2:-2}"

    echo "$scan_result" | jq -r '
        def print_tree(prefix; is_last):
            . as $node |
            (if is_last then "└── " else "├── " end) as $connector |
            (if is_last then "    " else "│   " end) as $new_prefix |
            "\(prefix)\($connector)\(.size_human | rjust(10))  \(.name)" +
            if .is_bloated then " [BLOAT: \(.bloat_reason)]" else "" end,
            if .children then
                .children | to_entries |
                .[] |
                .value | print_tree(prefix + $new_prefix; . == (.children | last))
            else empty end;

        .tree |
        "\(.size_human | rjust(10))  \(.name)/",
        (.children // [] | to_entries | .[] | .value | print_tree(""; . == ((.children // []) | last)))
    ' 2>/dev/null
}

# =============================================================================
# Helper Functions
# =============================================================================

# Get bloated directories from scan
get_bloated_dirs() {
    local scan_result="$1"
    echo "$scan_result" | jq -r '.bloated_dirs[].path' 2>/dev/null
}

# Calculate directory percentage
get_dir_percentage() {
    local scan_result="$1"
    local dir_path="$2"

    local total_size dir_size
    total_size="$(echo "$scan_result" | jq -r '.stats.total_size')"
    dir_size="$(du -sk "$dir_path" 2>/dev/null | cut -f1)"
    dir_size=$((dir_size * 1024))

    if ((total_size > 0)); then
        echo $((dir_size * 100 / total_size))
    else
        echo 0
    fi
}

# Print summary
print_directory_summary() {
    local scan_result="$1"

    local size files dirs bloated
    size="$(echo "$scan_result" | jq -r '.stats.total_size // 0')"
    files="$(echo "$scan_result" | jq -r '.stats.file_count // 0')"
    dirs="$(echo "$scan_result" | jq -r '.stats.dir_count // 0')"
    bloated="$(echo "$scan_result" | jq -r '.bloated_dirs | length')"

    print_section "Directory Analysis"
    print_kv "Total size" "$(format_bytes "$size")"
    print_kv "Files" "$files"
    print_kv "Directories" "$dirs"
    print_kv "Bloated dirs" "$bloated"

    if ((bloated > 0)); then
        echo ""
        echo "Bloated directories:"
        echo "$scan_result" | jq -r '.bloated_dirs[] | "  \(.size_human)  \(.path) [\(.reason)]"' 2>/dev/null
    fi
}
