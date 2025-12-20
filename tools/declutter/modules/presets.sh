#!/usr/bin/env bash
# ============================================================================
# Cleanup Presets Module
# Pre-configured cleanup profiles for common scenarios
# ============================================================================

set -euo pipefail

_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &

# Developer cleanup patterns
DEV_PATTERNS=(
    # Node.js
    "node_modules"
    ".npm"
    ".yarn"
    ".pnpm-store"

    # Python
    "__pycache__"
    "*.pyc"
    "*.pyo"
    ".pytest_cache"
    ".mypy_cache"
    ".tox"
    "*.egg-info"
    ".eggs"
    "venv"
    ".venv"

    # Rust
    "target"

    # Go
    "go/pkg"

    # Java
    ".gradle"
    ".m2/repository"
    "build"

    # General
    ".cache"
    "dist"
    ".next"
    ".nuxt"
    ".output"
    "coverage"
    ".nyc_output"
)

# System cleanup patterns
SYSTEM_PATTERNS=(
    ".DS_Store"
    "Thumbs.db"
    "desktop.ini"
    "*.log"
    "*.tmp"
    "*.temp"
    ".localized"
)

# Browser cache patterns (be careful with these)
BROWSER_PATTERNS=(
    "Library/Caches/Google/Chrome"
    "Library/Caches/Firefox"
    "Library/Caches/com.apple.Safari"
    ".cache/chromium"
    ".cache/google-chrome"
    ".cache/mozilla"
)

# Preview cleanup (dry run)
preview_cleanup() {
    local preset=$1
    local search_path=${2:-.}

    print_header "Cleanup Preview: $preset"
    log_info "[DRY RUN] No files will be deleted"

    local patterns=()
    case "$preset" in
        dev|developer)
            patterns=("${DEV_PATTERNS[@]}")
            ;;
        system)
            patterns=("${SYSTEM_PATTERNS[@]}")
            ;;
        browser)
            patterns=("${BROWSER_PATTERNS[@]}")
            ;;
        all)
            patterns=("${DEV_PATTERNS[@]}" "${SYSTEM_PATTERNS[@]}")
            ;;
        *)
            log_error "Unknown preset: $preset"
            log_info "Available: dev, system, browser, all"
            return 1
            ;;
    esac

    local total_size=0
    local total_count=0

    declare -A pattern_sizes
    declare -A pattern_counts

    start_spinner "Scanning..."

    for pattern in "${patterns[@]}"; do
        local size=0
        local count=0

        while IFS= read -r -d '' item; do
            if [[ -d "$item" ]]; then
                local dir_size
                dir_size=$(du -s "$item" 2>/dev/null | cut -f1)
                size=$((size + dir_size * 512))
            else
                local file_size
                file_size=$(get_file_size "$item" 2>/dev/null || echo 0)
                size=$((size + file_size))
            fi
            ((count++))
        done < <(find "$search_path" -name "$pattern" -print0 2>/dev/null)

        if [[ $count -gt 0 ]]; then
            pattern_sizes[$pattern]=$size
            pattern_counts[$pattern]=$count
            total_size=$((total_size + size))
            total_count=$((total_count + count))
        fi
    done

    stop_spinner

    print_subheader "Items to be cleaned"

    printf "  ${WHITE}%-30s %10s %15s${NC}\n" "PATTERN" "COUNT" "SIZE"
    printf "  ${GRAY}%-30s %10s %15s${NC}\n" \
        "$(printf '─%.0s' {1..30})" "$(printf '─%.0s' {1..10})" "$(printf '─%.0s' {1..15})"

    for pattern in "${!pattern_counts[@]}"; do
        printf "  %-30s %10d %15s\n" \
            "$pattern" "${pattern_counts[$pattern]}" "$(human_size ${pattern_sizes[$pattern]})"
    done

    echo ""
    printf "  ${WHITE}%-30s %10d %15s${NC}\n" "TOTAL" "$total_count" "$(human_size $total_size)"

    return 0
}

# Execute cleanup
run_cleanup() {
    local preset=$1
    local search_path=${2:-.}

    print_header "Running Cleanup: $preset"

    local patterns=()
    case "$preset" in
        dev|developer)
            patterns=("${DEV_PATTERNS[@]}")
            ;;
        system)
            patterns=("${SYSTEM_PATTERNS[@]}")
            ;;
        browser)
            patterns=("${BROWSER_PATTERNS[@]}")
            if ! confirm_action "This will clear browser caches. Continue?"; then
                return 0
            fi
            ;;
        all)
            patterns=("${DEV_PATTERNS[@]}" "${SYSTEM_PATTERNS[@]}")
            ;;
        *)
            log_error "Unknown preset: $preset"
            return 1
            ;;
    esac

    if is_dry_run; then
        preview_cleanup "$preset" "$search_path"
        return 0
    fi

    # Preview first
    preview_cleanup "$preset" "$search_path"

    echo ""
    if ! confirm_action "Proceed with cleanup?"; then
        log_info "Cleanup cancelled"
        return 0
    fi

    local session_id
    session_id=$(create_undo_session "Cleanup: $preset")

    local deleted_count=0
    local freed_size=0

    for pattern in "${patterns[@]}"; do
        while IFS= read -r -d '' item; do
            local size=0
            if [[ -d "$item" ]]; then
                size=$(du -s "$item" 2>/dev/null | cut -f1)
                size=$((size * 512))
            else
                size=$(get_file_size "$item" 2>/dev/null || echo 0)
            fi

            safe_delete "$item" "$session_id"
            freed_size=$((freed_size + size))
            ((deleted_count++))
        done < <(find "$search_path" -name "$pattern" -print0 2>/dev/null)
    done

    echo ""
    log_success "Cleanup complete!"
    log_info "Deleted: $deleted_count items"
    log_info "Freed: $(human_size $freed_size)"
    log_info "Session ID: $session_id"
}

# Node.js specific cleanup
cleanup_node() {
    local search_path=${1:-.}

    print_header "Node.js Cleanup"

    local session_id
    session_id=$(create_undo_session "Node.js cleanup")

    local patterns=(
        "node_modules"
        ".npm"
        ".yarn"
        ".pnpm-store"
        ".next"
        ".nuxt"
        "dist"
        "build"
        ".cache"
        "coverage"
    )

    local total_freed=0

    for pattern in "${patterns[@]}"; do
        while IFS= read -r -d '' item; do
            local size
            size=$(du -s "$item" 2>/dev/null | cut -f1)
            size=$((size * 512))

            if is_dry_run; then
                log_info "[DRY RUN] Would delete: $item ($(human_size $size))"
            else
                safe_delete "$item" "$session_id"
                total_freed=$((total_freed + size))
            fi
        done < <(find "$search_path" -name "$pattern" -type d -print0 2>/dev/null)
    done

    log_success "Freed: $(human_size $total_freed)"
    log_info "Session ID: $session_id"
}

# Python specific cleanup
cleanup_python() {
    local search_path=${1:-.}

    print_header "Python Cleanup"

    local session_id
    session_id=$(create_undo_session "Python cleanup")

    local patterns=(
        "__pycache__"
        "*.pyc"
        "*.pyo"
        ".pytest_cache"
        ".mypy_cache"
        ".tox"
        "*.egg-info"
        ".eggs"
        "htmlcov"
        ".coverage"
    )

    local total_freed=0

    for pattern in "${patterns[@]}"; do
        while IFS= read -r -d '' item; do
            local size
            if [[ -d "$item" ]]; then
                size=$(du -s "$item" 2>/dev/null | cut -f1)
                size=$((size * 512))
            else
                size=$(get_file_size "$item" 2>/dev/null || echo 0)
            fi

            if is_dry_run; then
                log_info "[DRY RUN] Would delete: $item"
            else
                safe_delete "$item" "$session_id"
                total_freed=$((total_freed + size))
            fi
        done < <(find "$search_path" -name "$pattern" -print0 2>/dev/null)
    done

    log_success "Freed: $(human_size $total_freed)"
    log_info "Session ID: $session_id"
}

# Git cleanup
cleanup_git() {
    local search_path=${1:-.}

    print_header "Git Repository Cleanup"

    while IFS= read -r -d '' git_dir; do
        local repo_dir
        repo_dir=$(dirname "$git_dir")
        log_info "Cleaning: $repo_dir"

        (
            cd "$repo_dir" || exit

            # Garbage collection
            git gc --auto --quiet 2>/dev/null || true

            # Remove stale branches
            git remote prune origin 2>/dev/null || true

            # Clean untracked files (only if confirmed)
            if confirm_action "Remove untracked files in $repo_dir?"; then
                git clean -fd 2>/dev/null || true
            fi
        )
    done < <(find "$search_path" -name ".git" -type d -print0 2>/dev/null)

    log_success "Git cleanup complete"
}

# Custom rule-based cleanup
run_custom_cleanup() {
    local rules_file=${1:-"$DECLUTTER_RULES_FILE"}
    local search_path=${2:-.}

    if [[ ! -f "$rules_file" ]]; then
        log_error "Rules file not found: $rules_file"
        return 1
    fi

    print_header "Custom Rule-Based Cleanup"
    log_info "Loading rules from: $rules_file"

    # Simple YAML parsing for cleanup_targets
    local in_cleanup=false
    local current_patterns=()

    while IFS= read -r line; do
        if [[ "$line" =~ ^cleanup_targets: ]]; then
            in_cleanup=true
            continue
        fi

        if [[ $in_cleanup == true ]]; then
            if [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
                break  # End of cleanup_targets section
            fi

            if [[ "$line" =~ -[[:space:]]\"(.+)\" ]]; then
                current_patterns+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ -[[:space:]](.+) ]]; then
                current_patterns+=("${BASH_REMATCH[1]}")
            fi
        fi
    done < "$rules_file"

    if [[ ${#current_patterns[@]} -eq 0 ]]; then
        log_warn "No cleanup patterns found in rules file"
        return 0
    fi

    log_info "Found ${#current_patterns[@]} patterns"

    local session_id
    session_id=$(create_undo_session "Custom cleanup")

    for pattern in "${current_patterns[@]}"; do
        while IFS= read -r -d '' item; do
            safe_delete "$item" "$session_id"
        done < <(find "$search_path" -name "$pattern" -print0 2>/dev/null)
    done

    log_success "Custom cleanup complete"
    log_info "Session ID: $session_id"
}

# List available presets
list_presets() {
    print_header "Available Cleanup Presets"

    echo -e "  ${CYAN}dev${NC} / ${CYAN}developer${NC}"
    echo "    Clean development artifacts: node_modules, __pycache__, target, etc."
    echo ""

    echo -e "  ${CYAN}system${NC}"
    echo "    Clean system junk: .DS_Store, Thumbs.db, *.log, *.tmp"
    echo ""

    echo -e "  ${CYAN}browser${NC}"
    echo "    Clear browser caches (Chrome, Firefox, Safari)"
    echo ""

    echo -e "  ${CYAN}all${NC}"
    echo "    Run dev + system cleanup"
    echo ""

    echo -e "  ${CYAN}node${NC}"
    echo "    Node.js specific cleanup"
    echo ""

    echo -e "  ${CYAN}python${NC}"
    echo "    Python specific cleanup"
    echo ""

    echo -e "  ${CYAN}git${NC}"
    echo "    Git repository cleanup (gc, prune)"
    echo ""

    echo "Usage: declutter cleanup <preset> [path]"
}

export -f preview_cleanup run_cleanup cleanup_node cleanup_python
export -f cleanup_git run_custom_cleanup list_presets
