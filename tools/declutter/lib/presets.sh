#!/usr/bin/env bash
# =============================================================================
# Declutter Tool - Cleanup Presets Module
# Predefined cleanup rules for common scenarios
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"

# =============================================================================
# PRESET DEFINITIONS
# =============================================================================

# Development cleanup patterns
declare -A DEV_CLEANUP_PATTERNS=(
    # Node.js
    [node_modules]="node_modules"
    [npm_cache]=".npm"
    [yarn_cache]=".yarn/cache"
    [pnpm_store]=".pnpm-store"

    # Python
    [pycache]="__pycache__"
    [pytest_cache]=".pytest_cache"
    [eggs]="*.egg-info"
    [venv]="venv,.venv,env,.env"
    [pyc]="*.pyc"
    [pyo]="*.pyo"

    # Build artifacts
    [dist]="dist"
    [build]="build"
    [out]="out"
    [target]="target"
    [bin_debug]="bin/Debug,bin/Release"
    [obj]="obj"

    # IDE/Editor
    [idea]=".idea"
    [vscode]=".vscode"
    [eclipse]=".project,.classpath,.settings"

    # Version control
    [git_objects]=".git/objects/pack/*.pack"

    # Logs
    [logs]="*.log,logs"

    # Coverage
    [coverage]="coverage,.coverage,.nyc_output"
)

# System cleanup patterns
declare -A SYSTEM_CLEANUP_PATTERNS=(
    # macOS
    [ds_store]=".DS_Store"
    [spotlight]=".Spotlight-V100"
    [trashes]=".Trashes"
    [fseventsd]=".fseventsd"
    [temp_items]=".TemporaryItems"
    [apple_double]=".AppleDouble"
    [lso]="._*"

    # Windows
    [thumbs_db]="Thumbs.db"
    [desktop_ini]="desktop.ini"
    [recycle_bin]="\$RECYCLE.BIN"

    # Linux
    [trash]=".Trash-*"

    # Common temp files
    [tmp]="*.tmp,*.temp"
    [bak]="*.bak,*.backup,*.old"
    [swp]="*.swp,*.swo,*~"
    [lock]="*.lock"
)

# Cache cleanup patterns
declare -A CACHE_CLEANUP_PATTERNS=(
    # Browser caches
    [chrome_cache]="Library/Caches/Google/Chrome"
    [firefox_cache]="Library/Caches/Firefox"
    [safari_cache]="Library/Caches/com.apple.Safari"

    # Package managers
    [homebrew_cache]="Library/Caches/Homebrew"
    [pip_cache]="Library/Caches/pip,.cache/pip"
    [npm_cache]=".npm/_cacache"
    [yarn_cache]=".cache/yarn"
    [gradle_cache]=".gradle/caches"
    [maven_cache]=".m2/repository"

    # Misc caches
    [thumbnails]=".cache/thumbnails"
    [fontconfig]=".cache/fontconfig"
)

# =============================================================================
# PRESET EXECUTION
# =============================================================================

list_presets() {
    echo "Available cleanup presets:"
    echo ""
    echo "  ${C_BOLD}dev${C_RESET}      - Development artifacts (node_modules, __pycache__, build, etc.)"
    echo "  ${C_BOLD}system${C_RESET}   - System files (.DS_Store, Thumbs.db, temp files)"
    echo "  ${C_BOLD}cache${C_RESET}    - Cache directories (browser, package managers)"
    echo "  ${C_BOLD}logs${C_RESET}     - Log files"
    echo "  ${C_BOLD}all${C_RESET}      - All of the above"
    echo "  ${C_BOLD}custom${C_RESET}   - Custom rules from config file"
    echo ""
}

get_preset_patterns() {
    local preset="$1"

    case "$preset" in
        dev)
            for key in "${!DEV_CLEANUP_PATTERNS[@]}"; do
                echo "${DEV_CLEANUP_PATTERNS[$key]}"
            done
            ;;
        system)
            for key in "${!SYSTEM_CLEANUP_PATTERNS[@]}"; do
                echo "${SYSTEM_CLEANUP_PATTERNS[$key]}"
            done
            ;;
        cache)
            for key in "${!CACHE_CLEANUP_PATTERNS[@]}"; do
                echo "${CACHE_CLEANUP_PATTERNS[$key]}"
            done
            ;;
        logs)
            echo "*.log"
            echo "logs"
            echo "log"
            ;;
        all)
            get_preset_patterns "dev"
            get_preset_patterns "system"
            get_preset_patterns "cache"
            get_preset_patterns "logs"
            ;;
        *)
            log_error "Unknown preset: $preset"
            return 1
            ;;
    esac
}

scan_preset() {
    local dir="$1"
    local preset="$2"

    log_info "Scanning with preset: $preset"

    local patterns
    patterns=$(get_preset_patterns "$preset") || return 1

    local total_size=0
    local total_count=0

    echo ""
    echo "Files/directories found:"
    echo ""

    while IFS= read -r pattern; do
        # Handle comma-separated patterns
        IFS=',' read -ra sub_patterns <<< "$pattern"
        for sub_pattern in "${sub_patterns[@]}"; do
            sub_pattern=$(echo "$sub_pattern" | xargs)  # trim
            [[ -z "$sub_pattern" ]] && continue

            # Find matching items
            while IFS= read -r item; do
                [[ -z "$item" ]] && continue

                local size=0
                if [[ -d "$item" ]]; then
                    size=$(du -sk "$item" 2>/dev/null | cut -f1 || echo 0)
                    size=$((size * 1024))
                elif [[ -f "$item" ]]; then
                    size=$(stat -f%z "$item" 2>/dev/null || stat -c%s "$item" 2>/dev/null || echo 0)
                fi

                total_size=$((total_size + size))
                ((total_count++))

                echo "  $(human_readable_size "$size")"$'\t'"$item"
            done < <(find "$dir" -name "$sub_pattern" 2>/dev/null || true)
        done
    done <<< "$patterns"

    echo ""
    echo "${C_BOLD}Summary:${C_RESET}"
    echo "  Items found: $total_count"
    echo "  Total size:  $(human_readable_size "$total_size")"
}

run_preset() {
    local dir="$1"
    local preset="$2"
    local interactive="${3:-true}"

    log_info "Running cleanup preset: $preset"

    # First, scan and show what would be deleted
    scan_preset "$dir" "$preset"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] No files were deleted"
        return 0
    fi

    if [[ "$interactive" == "true" ]]; then
        echo ""
        if ! confirm "Proceed with cleanup?"; then
            log_info "Cleanup cancelled"
            return 0
        fi
    fi

    local patterns
    patterns=$(get_preset_patterns "$preset") || return 1

    local deleted_count=0
    local deleted_size=0

    while IFS= read -r pattern; do
        IFS=',' read -ra sub_patterns <<< "$pattern"
        for sub_pattern in "${sub_patterns[@]}"; do
            sub_pattern=$(echo "$sub_pattern" | xargs)
            [[ -z "$sub_pattern" ]] && continue

            while IFS= read -r item; do
                [[ -z "$item" ]] && continue

                local size=0
                if [[ -d "$item" ]]; then
                    size=$(du -sk "$item" 2>/dev/null | cut -f1 || echo 0)
                    size=$((size * 1024))
                elif [[ -f "$item" ]]; then
                    size=$(stat -f%z "$item" 2>/dev/null || stat -c%s "$item" 2>/dev/null || echo 0)
                fi

                if safe_delete "$item" false; then
                    deleted_size=$((deleted_size + size))
                    ((deleted_count++))
                fi
            done < <(find "$dir" -name "$sub_pattern" 2>/dev/null || true)
        done
    done <<< "$patterns"

    echo ""
    log_info "Cleanup complete!"
    echo "  Items deleted: $deleted_count"
    echo "  Space freed:   $(human_readable_size "$deleted_size")"
}

# =============================================================================
# NODE_MODULES SPECIFIC CLEANUP
# =============================================================================

cleanup_node_modules() {
    local dir="$1"
    local age_days="${2:-0}"  # 0 = all, otherwise only older than X days

    log_info "Scanning for node_modules directories..."

    local total_size=0
    local total_count=0

    while IFS= read -r nm_dir; do
        # Check age if specified
        if [[ $age_days -gt 0 ]]; then
            local mtime
            mtime=$(stat -f%m "$nm_dir" 2>/dev/null || stat -c%Y "$nm_dir" 2>/dev/null || echo 0)
            local now
            now=$(date +%s)
            local age=$(( (now - mtime) / 86400 ))
            [[ $age -lt $age_days ]] && continue
        fi

        local size
        size=$(du -sk "$nm_dir" 2>/dev/null | cut -f1 || echo 0)
        size=$((size * 1024))

        total_size=$((total_size + size))
        ((total_count++))

        local project_dir
        project_dir="$(dirname "$nm_dir")"
        local package_json="$project_dir/package.json"
        local project_name="unknown"

        if [[ -f "$package_json" ]]; then
            project_name=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$package_json" | \
                          head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi

        echo "  $(human_readable_size "$size")"$'\t'"$nm_dir ($project_name)"
    done < <(find "$dir" -type d -name "node_modules" -not -path "*/node_modules/*" 2>/dev/null)

    echo ""
    echo "${C_BOLD}Summary:${C_RESET}"
    echo "  node_modules found: $total_count"
    echo "  Total size:         $(human_readable_size "$total_size")"

    if [[ "$DRY_RUN" != "true" ]] && [[ $total_count -gt 0 ]]; then
        echo ""
        if confirm "Delete all node_modules directories?"; then
            find "$dir" -type d -name "node_modules" -not -path "*/node_modules/*" 2>/dev/null | \
                while read -r nm_dir; do
                    rm -rf "$nm_dir"
                    log_info "Deleted: $nm_dir"
                done
            log_info "Freed $(human_readable_size "$total_size")"
        fi
    fi
}

# =============================================================================
# GIT CLEANUP
# =============================================================================

cleanup_git_repos() {
    local dir="$1"
    local aggressive="${2:-false}"

    log_info "Scanning for Git repositories..."

    local total_freed=0

    while IFS= read -r git_dir; do
        local repo_dir
        repo_dir="$(dirname "$git_dir")"

        echo "Processing: $repo_dir"

        local before_size
        before_size=$(du -sk "$git_dir" 2>/dev/null | cut -f1 || echo 0)

        (
            cd "$repo_dir" || exit

            # Standard cleanup
            git gc --quiet 2>/dev/null || true
            git prune 2>/dev/null || true

            if [[ "$aggressive" == "true" ]]; then
                git gc --aggressive --quiet 2>/dev/null || true
                git repack -a -d --depth=250 --window=250 2>/dev/null || true
            fi
        )

        local after_size
        after_size=$(du -sk "$git_dir" 2>/dev/null | cut -f1 || echo 0)

        local freed=$(( (before_size - after_size) * 1024 ))
        if [[ $freed -gt 0 ]]; then
            total_freed=$((total_freed + freed))
            echo "  Freed: $(human_readable_size "$freed")"
        fi
    done < <(find "$dir" -type d -name ".git" 2>/dev/null)

    echo ""
    log_info "Total space freed: $(human_readable_size "$total_freed")"
}

# =============================================================================
# CUSTOM PRESET FROM CONFIG
# =============================================================================

load_custom_preset() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi

    declare -a patterns

    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        patterns+=("$line")
    done < "$config_file"

    printf '%s\n' "${patterns[@]}"
}

run_custom_preset() {
    local dir="$1"
    local config_file="$2"

    log_info "Running custom preset from: $config_file"

    local patterns
    patterns=$(load_custom_preset "$config_file") || return 1

    # Same logic as run_preset but with custom patterns
    local total_size=0
    local total_count=0

    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue

        while IFS= read -r item; do
            [[ -z "$item" ]] && continue

            local size=0
            if [[ -d "$item" ]]; then
                size=$(du -sk "$item" 2>/dev/null | cut -f1 || echo 0)
                size=$((size * 1024))
            elif [[ -f "$item" ]]; then
                size=$(stat -f%z "$item" 2>/dev/null || stat -c%s "$item" 2>/dev/null || echo 0)
            fi

            total_size=$((total_size + size))
            ((total_count++))

            echo "  $(human_readable_size "$size")"$'\t'"$item"
        done < <(find "$dir" -name "$pattern" 2>/dev/null || true)
    done <<< "$patterns"

    echo ""
    echo "Items found: $total_count"
    echo "Total size:  $(human_readable_size "$total_size")"
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f list_presets get_preset_patterns scan_preset run_preset
export -f cleanup_node_modules cleanup_git_repos
export -f load_custom_preset run_custom_preset
