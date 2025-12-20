#!/usr/bin/env bash
#
# Declutter - Developer Cleanup Preset
# Remove build artifacts, dependencies, and caches
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_PRESET_DEV_LOADED:-}" ]] && return 0
readonly _DECLUTTER_PRESET_DEV_LOADED=1

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
# Preset Registration
# =============================================================================

if declare -F register_preset &>/dev/null; then
    register_preset "dev" "preset_dev" "Developer cleanup"
    register_preset "developer" "preset_dev" "Developer cleanup (alias)"
fi

# =============================================================================
# Developer Cleanup Patterns
# =============================================================================

# Node.js patterns
declare -a NODEJS_PATTERNS=(
    "node_modules"
    ".npm"
    ".yarn"
    ".pnpm-store"
    "package-lock.json.bak"
    "yarn-error.log"
    ".eslintcache"
    ".parcel-cache"
    ".cache"
    "dist"
    "build"
    ".next"
    ".nuxt"
    ".output"
    ".turbo"
)

# Python patterns
declare -a PYTHON_PATTERNS=(
    "__pycache__"
    "*.pyc"
    "*.pyo"
    "*.pyd"
    ".pytest_cache"
    ".mypy_cache"
    ".tox"
    ".nox"
    ".coverage"
    "htmlcov"
    "*.egg-info"
    "dist"
    "build"
    ".eggs"
    ".ruff_cache"
    ".hypothesis"
)

# Rust patterns
declare -a RUST_PATTERNS=(
    "target"
)

# Go patterns
declare -a GO_PATTERNS=(
    "vendor"  # Only if orphaned
)

# Java patterns
declare -a JAVA_PATTERNS=(
    "target"
    "build"
    ".gradle"
    "*.class"
    "*.jar"
    "*.war"
)

# IDE patterns
declare -a IDE_PATTERNS=(
    ".idea"
    "*.iml"
    ".vscode/settings.json.bak"
    "*.sublime-workspace"
    ".history"
)

# System junk
declare -a SYSTEM_PATTERNS=(
    ".DS_Store"
    "Thumbs.db"
    "desktop.ini"
    "*~"
    "*.swp"
    "*.swo"
    "*.bak"
    "*.tmp"
    "*.log"
)

# =============================================================================
# Preset Execution
# =============================================================================

# Main developer cleanup function
preset_dev() {
    local target_path="${1:-$PWD}"
    local aggressive="${2:-false}"

    target_path="$(get_absolute_path "$target_path")"

    print_header "Developer Cleanup"
    log_step "Target: $target_path"

    if is_dry_run; then
        show_dry_run_banner
    fi

    print_divider

    # Collect all items to clean
    local -a all_items=()
    local total_size=0

    # Scan for patterns
    log_info "Scanning for build artifacts and caches..."

    _scan_patterns "$target_path" NODEJS_PATTERNS all_items total_size
    _scan_patterns "$target_path" PYTHON_PATTERNS all_items total_size
    _scan_patterns "$target_path" RUST_PATTERNS all_items total_size
    _scan_patterns "$target_path" JAVA_PATTERNS all_items total_size
    _scan_patterns "$target_path" IDE_PATTERNS all_items total_size
    _scan_patterns "$target_path" SYSTEM_PATTERNS all_items total_size

    # Add Go vendor only if orphaned
    if [[ "$aggressive" == "true" ]]; then
        _scan_patterns "$target_path" GO_PATTERNS all_items total_size
    fi

    # Display results
    echo ""
    print_section "Found Items"

    if ((${#all_items[@]} == 0)); then
        log_success "No cleanup needed!"
        return 0
    fi

    # Group by type for display
    local node_count=0 python_count=0 rust_count=0 java_count=0 other_count=0

    for item in "${all_items[@]}"; do
        local name
        name="$(basename "$item")"
        case "$name" in
            node_modules|.npm|.yarn|.next|.nuxt) ((node_count++)) ;;
            __pycache__|.pytest_cache|.mypy_cache|*.pyc) ((python_count++)) ;;
            target)
                if [[ -f "$(dirname "$item")/Cargo.toml" ]]; then
                    ((rust_count++))
                else
                    ((java_count++))
                fi
                ;;
            .gradle|*.class) ((java_count++)) ;;
            *) ((other_count++)) ;;
        esac
    done

    print_kv "Node.js artifacts" "$node_count"
    print_kv "Python caches" "$python_count"
    print_kv "Rust build" "$rust_count"
    print_kv "Java build" "$java_count"
    print_kv "Other" "$other_count"
    print_kv "Total items" "${#all_items[@]}"
    print_kv "Total size" "$(format_bytes "$total_size")"

    # Confirm deletion
    echo ""
    if is_interactive && ! is_dry_run; then
        if ! confirm "Delete these items?"; then
            log_info "Operation cancelled"
            return 0
        fi
    fi

    # Delete items
    local success=0
    local failed=0

    print_section "Cleaning"

    for item in "${all_items[@]}"; do
        if is_dry_run; then
            dry_run_action "delete" "$item"
            ((success++))
        elif [[ -e "$item" ]]; then
            if rm -rf "$item" 2>/dev/null; then
                log_success "Deleted: $item"
                ((success++))
            else
                log_warn "Failed: $item"
                ((failed++))
            fi
        fi
    done

    # Summary
    print_divider
    print_action_summary "dev cleanup" "$success" "$failed" "$(format_bytes "$total_size")"
}

# Scan for patterns and add to items array
_scan_patterns() {
    local path="$1"
    local -n patterns="$2"
    local -n items="$3"
    local -n size="$4"

    for pattern in "${patterns[@]}"; do
        while IFS= read -r item; do
            [[ -z "$item" ]] && continue
            [[ -e "$item" ]] || continue

            # Skip if in .git
            [[ "$item" == *"/.git/"* ]] && continue

            items+=("$item")

            if [[ -d "$item" ]]; then
                local item_size
                item_size="$(du -sk "$item" 2>/dev/null | cut -f1 || echo 0)"
                ((size += item_size * 1024))
            elif [[ -f "$item" ]]; then
                local item_size
                item_size="$(get_file_size "$item")"
                ((size += item_size))
            fi
        done < <(_find_pattern "$path" "$pattern")
    done
}

# Find pattern (use fd if available)
_find_pattern() {
    local path="$1"
    local pattern="$2"

    if command -v fd &>/dev/null; then
        fd -HI --glob "$pattern" "$path" 2>/dev/null
    else
        find "$path" -name "$pattern" 2>/dev/null
    fi
}

# =============================================================================
# Specialized Cleanups
# =============================================================================

# Clean Node.js projects
preset_dev_node() {
    local target_path="${1:-$PWD}"

    print_header "Node.js Cleanup"

    local -a items=()
    local total_size=0

    _scan_patterns "$target_path" NODEJS_PATTERNS items total_size

    _cleanup_items "Node.js" items total_size
}

# Clean Python projects
preset_dev_python() {
    local target_path="${1:-$PWD}"

    print_header "Python Cleanup"

    local -a items=()
    local total_size=0

    _scan_patterns "$target_path" PYTHON_PATTERNS items total_size

    _cleanup_items "Python" items total_size
}

# Clean Rust projects
preset_dev_rust() {
    local target_path="${1:-$PWD}"

    print_header "Rust Cleanup"

    local -a items=()
    local total_size=0

    _scan_patterns "$target_path" RUST_PATTERNS items total_size

    _cleanup_items "Rust" items total_size
}

# Common cleanup logic
_cleanup_items() {
    local name="$1"
    local -n items_ref="$2"
    local -n size_ref="$3"

    if ((${#items_ref[@]} == 0)); then
        log_success "No $name artifacts found"
        return 0
    fi

    print_kv "Items found" "${#items_ref[@]}"
    print_kv "Total size" "$(format_bytes "$size_ref")"

    if is_interactive && ! is_dry_run; then
        if ! confirm "Delete ${#items_ref[@]} items?"; then
            return 0
        fi
    fi

    local success=0
    for item in "${items_ref[@]}"; do
        if is_dry_run; then
            dry_run_action "delete" "$item"
            ((success++))
        elif rm -rf "$item" 2>/dev/null; then
            log_success "Deleted: $(basename "$item")"
            ((success++))
        fi
    done

    log_success "Cleaned $success items, freed $(format_bytes "$size_ref")"
}

# =============================================================================
# Git Cleanup
# =============================================================================

# Clean git repositories
preset_dev_git() {
    local target_path="${1:-$PWD}"

    print_header "Git Cleanup"

    # Find git repos
    while IFS= read -r git_dir; do
        [[ -z "$git_dir" ]] && continue

        local repo_dir
        repo_dir="$(dirname "$git_dir")"

        log_step "Cleaning: $repo_dir"

        (
            cd "$repo_dir" || exit

            # Run git gc
            if is_dry_run; then
                log_info "[DRY-RUN] Would run: git gc --prune=now"
            else
                git gc --prune=now --quiet 2>/dev/null
                log_success "Garbage collected"
            fi

            # Clean untracked files (only with confirmation)
            if is_interactive; then
                local untracked
                untracked="$(git clean -n -d 2>/dev/null | wc -l | tr -d ' ')"
                if ((untracked > 0)); then
                    log_info "Found $untracked untracked items"
                    if confirm "Clean untracked files?"; then
                        git clean -fd 2>/dev/null
                        log_success "Cleaned untracked files"
                    fi
                fi
            fi
        )
    done < <(find "$target_path" -name ".git" -type d 2>/dev/null)
}
