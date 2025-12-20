#!/usr/bin/env bash
#
# Declutter - Orphaned Files Scanner
# Find orphaned files like .DS_Store, Thumbs.db, node_modules without package.json
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_SCANNER_ORPHANS_LOADED:-}" ]] && return 0
readonly _DECLUTTER_SCANNER_ORPHANS_LOADED=1

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
    register_scanner "orphans" "scan_orphans" "Find orphaned and junk files"
    register_scanner "junk" "scan_orphans" "Find orphaned and junk files (alias)"
fi

# =============================================================================
# Orphan Patterns
# =============================================================================

# System junk files
declare -a SYSTEM_JUNK=(
    ".DS_Store"
    "._.DS_Store"
    "Thumbs.db"
    "desktop.ini"
    "*.lnk"
    ".Spotlight-V100"
    ".Trashes"
    ".fseventsd"
    "__MACOSX"
)

# Editor temporary files
declare -a EDITOR_JUNK=(
    "*.swp"
    "*.swo"
    "*~"
    ".*.un~"
    "*.bak"
    "*.orig"
    "*.tmp"
    "#*#"
    ".#*"
)

# Build artifacts without project files
declare -A BUILD_ORPHANS=(
    ["node_modules"]="package.json"
    ["__pycache__"]=".py"
    [".pytest_cache"]="pytest.ini|pyproject.toml|setup.py"
    [".mypy_cache"]="mypy.ini|pyproject.toml"
    ["target"]="Cargo.toml"
    ["vendor"]="go.mod"
    [".gradle"]="build.gradle|build.gradle.kts"
    [".idea"]="*.iml|pom.xml|build.gradle"
)

# =============================================================================
# Orphan Detection
# =============================================================================

# Main scanning function
scan_orphans() {
    local target_path="${1:-$PWD}"

    target_path="$(get_absolute_path "$target_path")"

    if [[ ! -d "$target_path" ]]; then
        log_error "Directory not found: $target_path"
        return 1
    fi

    log_debug "Scanning for orphaned files in: $target_path"

    local system_items=()
    local editor_items=()
    local build_items=()
    local total_size=0

    # Find system junk
    for pattern in "${SYSTEM_JUNK[@]}"; do
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local size
            size="$(get_file_size "$file")"
            ((total_size += size))
            system_items+=("{\"path\":\"$(json_escape "$file")\",\"size\":$size,\"type\":\"system\"}")
        done < <(_find_pattern "$target_path" "$pattern")
    done

    # Find editor junk
    for pattern in "${EDITOR_JUNK[@]}"; do
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local size
            size="$(get_file_size "$file")"
            ((total_size += size))
            editor_items+=("{\"path\":\"$(json_escape "$file")\",\"size\":$size,\"type\":\"editor\"}")
        done < <(_find_pattern "$target_path" "$pattern")
    done

    # Find build orphans (directories without their project files)
    for dir_name in "${!BUILD_ORPHANS[@]}"; do
        local marker="${BUILD_ORPHANS[$dir_name]}"

        while IFS= read -r dir; do
            [[ -z "$dir" ]] && continue

            # Check if parent has the marker file
            local parent
            parent="$(dirname "$dir")"

            if ! _has_marker "$parent" "$marker"; then
                local size
                size="$(du -sk "$dir" 2>/dev/null | cut -f1)"
                size=$((size * 1024))
                ((total_size += size))
                build_items+=("{\"path\":\"$(json_escape "$dir")\",\"size\":$size,\"type\":\"build_orphan\",\"expected_marker\":\"$marker\"}")
            fi
        done < <(find "$target_path" -type d -name "$dir_name" 2>/dev/null)
    done

    # Output JSON
    local all_items=("${system_items[@]}" "${editor_items[@]}" "${build_items[@]}")

    echo "{"
    echo "  \"scan_type\": \"orphans\","
    echo "  \"timestamp\": \"$(get_timestamp)\","
    echo "  \"target\": \"$target_path\","
    echo -n "  \"items\": ["
    local first=true
    for item in "${all_items[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
            echo ""
        else
            echo ","
        fi
        echo -n "    $item"
    done
    echo ""
    echo "  ],"
    echo "  \"stats\": {"
    echo "    \"system_junk\": ${#system_items[@]},"
    echo "    \"editor_junk\": ${#editor_items[@]},"
    echo "    \"build_orphans\": ${#build_items[@]},"
    echo "    \"total\": ${#all_items[@]},"
    echo "    \"total_size\": $total_size"
    echo "  }"
    echo "}"
}

# Find files matching pattern
_find_pattern() {
    local path="$1"
    local pattern="$2"

    if command -v fd &>/dev/null; then
        fd -HI --glob "$pattern" "$path" 2>/dev/null
    else
        find "$path" -name "$pattern" 2>/dev/null
    fi
}

# Check if directory has marker file
_has_marker() {
    local dir="$1"
    local markers="$2"  # Pipe-separated patterns

    IFS='|' read -ra MARKERS <<< "$markers"
    for marker in "${MARKERS[@]}"; do
        if [[ "$marker" == *"*"* ]]; then
            # Glob pattern
            # shellcheck disable=SC2086
            ls "$dir"/$marker &>/dev/null && return 0
        else
            # Exact file
            [[ -f "$dir/$marker" ]] && return 0
        fi
    done

    return 1
}

# =============================================================================
# Specialized Scanners
# =============================================================================

# Scan for broken symlinks
scan_broken_symlinks() {
    local target_path="${1:-$PWD}"

    target_path="$(get_absolute_path "$target_path")"

    log_debug "Scanning for broken symlinks in: $target_path"

    # Use czkawka if available
    if command -v czkawka_cli &>/dev/null; then
        local temp_file
        temp_file="$(mktemp)"

        czkawka_cli symlinks -d "$target_path" -f "$temp_file" --json 2>/dev/null

        local result
        result="$(jq '{
            scan_type: "broken_symlinks",
            timestamp: now | todate,
            target: "'"$target_path"'",
            items: [.invalid_symlinks[]? | {
                path: .path,
                target: .destination
            }],
            stats: {
                total: (.invalid_symlinks | length)
            }
        }' "$temp_file" 2>/dev/null)" || result="{}"

        rm -f "$temp_file"
        echo "$result"
    else
        local items=()

        while IFS= read -r link; do
            [[ -z "$link" ]] && continue
            local target
            target="$(readlink "$link" 2>/dev/null || echo "")"
            items+=("{\"path\":\"$(json_escape "$link")\",\"target\":\"$(json_escape "$target")\"}")
        done < <(find "$target_path" -type l ! -exec test -e {} \; -print 2>/dev/null)

        echo "{"
        echo "  \"scan_type\": \"broken_symlinks\","
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
    fi
}

# Scan for temporary files
scan_temp_files() {
    local target_path="${1:-$PWD}"

    target_path="$(get_absolute_path "$target_path")"

    log_debug "Scanning for temporary files in: $target_path"

    # Use czkawka if available
    if command -v czkawka_cli &>/dev/null; then
        local temp_file
        temp_file="$(mktemp)"

        czkawka_cli temp -d "$target_path" -f "$temp_file" --json 2>/dev/null

        local result
        result="$(jq '{
            scan_type: "temp_files",
            timestamp: now | todate,
            target: "'"$target_path"'",
            items: [.temporary_files[]? | {path: .path}],
            stats: {
                total: (.temporary_files | length)
            }
        }' "$temp_file" 2>/dev/null)" || result="{}"

        rm -f "$temp_file"
        echo "$result"
    else
        # Fallback
        scan_orphans "$target_path" | jq '{
            scan_type: "temp_files",
            timestamp: .timestamp,
            target: .target,
            items: [.items[] | select(.type == "editor" or .type == "system")],
            stats: {
                total: ([.items[] | select(.type == "editor" or .type == "system")] | length)
            }
        }' 2>/dev/null
    fi
}

# =============================================================================
# Helper Functions
# =============================================================================

# Get orphan items to delete
get_orphans_to_delete() {
    local scan_result="$1"
    echo "$scan_result" | jq -r '.items[].path' 2>/dev/null
}

# Filter by type
filter_orphans_by_type() {
    local scan_result="$1"
    local type="$2"  # system, editor, build_orphan

    echo "$scan_result" | jq ".items | map(select(.type == \"$type\"))" 2>/dev/null
}

# Print summary
print_orphans_summary() {
    local scan_result="$1"

    local system editor build total size
    system="$(echo "$scan_result" | jq -r '.stats.system_junk // 0')"
    editor="$(echo "$scan_result" | jq -r '.stats.editor_junk // 0')"
    build="$(echo "$scan_result" | jq -r '.stats.build_orphans // 0')"
    total="$(echo "$scan_result" | jq -r '.stats.total // 0')"
    size="$(echo "$scan_result" | jq -r '.stats.total_size // 0')"

    print_section "Orphan Files Scan Results"
    print_kv "System junk" "$system"
    print_kv "Editor temp files" "$editor"
    print_kv "Build orphans" "$build"
    print_kv "Total items" "$total"
    print_kv "Total size" "$(format_bytes "$size")"
}

# Register additional scanners
if declare -F register_scanner &>/dev/null; then
    register_scanner "symlinks" "scan_broken_symlinks" "Find broken symlinks"
    register_scanner "temp" "scan_temp_files" "Find temporary files"
fi
