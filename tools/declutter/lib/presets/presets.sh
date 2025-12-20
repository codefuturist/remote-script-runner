#!/usr/bin/env bash
# ============================================================================
# Cleanup Presets
# Pre-defined cleanup configurations for common use cases
# ============================================================================

set -euo pipefail

# Prevent double-sourcing
[[ "${_DECLUTTER_PRESETS_LOADED:-}" == "true" ]] && return 0
readonly _DECLUTTER_PRESETS_LOADED="true"

# =============================================================================
# Preset Definitions
# =============================================================================

# Each preset is a function that returns cleanup targets
# Format: type|pattern|description

preset_dev() {
    cat << 'EOF'
dir|node_modules|Node.js dependencies
dir|__pycache__|Python bytecode cache
dir|.pytest_cache|Pytest cache
dir|.mypy_cache|Mypy type checking cache
dir|.tox|Tox testing cache
dir|.coverage|Coverage data
dir|coverage|Coverage reports
dir|dist|Build distribution
dir|build|Build output
dir|.next|Next.js build
dir|.nuxt|Nuxt.js build
dir|target|Rust/Java build output
dir|.gradle|Gradle cache
dir|.idea|IntelliJ project files
dir|.vscode|VS Code project files (use with caution)
dir|vendor|Vendored dependencies (Go/PHP)
dir|.bundle|Ruby bundle cache
dir|.sass-cache|Sass compilation cache
file|*.pyc|Python compiled files
file|*.pyo|Python optimized files
file|*.class|Java compiled files
file|*.o|Object files
file|*.a|Static libraries
file|*.so|Shared libraries
file|*.dylib|macOS dynamic libraries
file|.DS_Store|macOS folder metadata
file|Thumbs.db|Windows thumbnail cache
file|desktop.ini|Windows folder settings
file|*.log|Log files
file|npm-debug.log*|npm debug logs
file|yarn-error.log|Yarn error logs
file|.env.local|Local environment files
EOF
}

preset_system() {
    cat << 'EOF'
file|*.tmp|Temporary files
file|*.temp|Temporary files
file|*.bak|Backup files
file|*.backup|Backup files
file|*.old|Old files
file|*.orig|Original files (from patches)
file|*.swp|Vim swap files
file|*.swo|Vim swap files
file|*~|Editor backup files
file|#*#|Emacs auto-save files
file|.#*|Emacs lock files
file|core|Core dump files
file|*.core|Core dump files
dir|.Trash|User trash
dir|.Trashes|System trash
file|.DS_Store|macOS metadata
file|.Spotlight-V100|Spotlight index
file|.fseventsd|File system events
EOF
}

preset_browser() {
    cat << 'EOF'
file|*.crdownload|Chrome partial downloads
file|*.part|Partial downloads
file|*.partial|Partial downloads
file|*.download|In-progress downloads
dir|Cache|Browser cache
dir|CacheStorage|Cache storage
dir|Code Cache|Chrome code cache
dir|GPUCache|GPU cache
dir|ShaderCache|Shader cache
EOF
}

preset_media() {
    cat << 'EOF'
file|*.thumb|Thumbnail files
file|*.thm|Thumbnail files
file|Thumbs.db|Windows thumbnails
dir|.thumbnails|Linux thumbnails
dir|thumbnails|Thumbnail directory
file|*.nfo|Media info files
file|*.sfv|Checksum files
file|*.srr|Scene release files
EOF
}

preset_logs() {
    cat << 'EOF'
file|*.log|Log files
file|*.log.*|Rotated log files
file|*.log.gz|Compressed logs
file|*.log.bz2|Compressed logs
file|*.log.xz|Compressed logs
dir|logs|Log directories
dir|log|Log directories
EOF
}

preset_xcode() {
    cat << 'EOF'
dir|DerivedData|Xcode derived data
dir|Archives|Xcode archives (old)
dir|iOS DeviceSupport|Device support files
dir|watchOS DeviceSupport|Watch device support
dir|tvOS DeviceSupport|TV device support
dir|Simulators|iOS Simulators (old)
EOF
}

preset_android() {
    cat << 'EOF'
dir|.gradle|Gradle cache
dir|build|Android build output
dir|.android|Android SDK cache
dir|Android/Sdk/.temp|SDK temp files
file|*.apk|APK files (if not needed)
file|*.aab|App bundles (if not needed)
EOF
}

# =============================================================================
# Preset Management
# =============================================================================

# List all available presets
list_presets() {
    print_section "Available Cleanup Presets"

    local presets=(dev system browser media logs xcode android)

    for preset in "${presets[@]}"; do
        local count
        count=$(eval "preset_$preset" 2>/dev/null | wc -l | tr -d ' ')
        printf "  ${CYAN}%-12s${NC}  %d rules\n" "$preset" "$count"
    done

    echo ""
    echo "Usage: declutter cleanup <preset> [path]"
}

# Get preset rules
get_preset() {
    local preset=$1

    if declare -f "preset_$preset" &>/dev/null; then
        eval "preset_$preset"
    else
        log_error "Unknown preset: $preset"
        return 1
    fi
}

# Show preset details
show_preset() {
    local preset=$1

    if ! declare -f "preset_$preset" &>/dev/null; then
        log_error "Unknown preset: $preset"
        return 1
    fi

    print_section "Preset: $preset"

    echo "Files:"
    get_preset "$preset" | grep "^file|" | while IFS='|' read -r type pattern desc; do
        printf "  %-20s  %s\n" "$pattern" "$desc"
    done

    echo ""
    echo "Directories:"
    get_preset "$preset" | grep "^dir|" | while IFS='|' read -r type pattern desc; do
        printf "  %-20s  %s\n" "$pattern" "$desc"
    done
}

# =============================================================================
# Preset Execution
# =============================================================================

# Scan for items matching preset
scan_preset() {
    local preset=$1
    local search_path=${2:-.}

    local rules
    rules=$(get_preset "$preset") || return 1

    log_step "Scanning for '$preset' cleanup targets in: $search_path"
    start_spinner "Scanning..."

    local output_file
    output_file="${DECLUTTER_CACHE_DIR:-$HOME/.cache/declutter}/preset_${preset}_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$output_file")"

    > "$output_file"  # Clear file

    while IFS='|' read -r type pattern desc; do
        case "$type" in
            file)
                if command -v fd &>/dev/null; then
                    fd -HI --glob "$pattern" "$search_path" --type f 2>/dev/null
                else
                    find "$search_path" -type f -name "$pattern" 2>/dev/null
                fi
                ;;
            dir)
                if command -v fd &>/dev/null; then
                    fd -HI --glob "$pattern" "$search_path" --type d 2>/dev/null
                else
                    find "$search_path" -type d -name "$pattern" 2>/dev/null
                fi
                ;;
        esac >> "$output_file"
    done <<< "$rules"

    stop_spinner

    # Remove duplicates
    sort -u "$output_file" -o "$output_file"

    if [[ -s "$output_file" ]]; then
        echo "$output_file"
    else
        rm -f "$output_file"
        log_success "No cleanup targets found!"
        echo ""
    fi
}

# Run cleanup preset
run_cleanup() {
    local preset=$1
    local search_path=${2:-.}
    local session_id=${3:-}

    local results_file
    results_file=$(scan_preset "$preset" "$search_path")

    if [[ -z "$results_file" || ! -f "$results_file" ]]; then
        return 0
    fi

    local count
    count=$(wc -l < "$results_file" | tr -d ' ')

    # Calculate total size
    local total_size=0
    while IFS= read -r item; do
        if [[ -e "$item" ]]; then
            if [[ -d "$item" ]]; then
                local size
                size=$(du -sk "$item" 2>/dev/null | cut -f1 || echo "0")
                total_size=$((total_size + size * 1024))
            elif [[ -f "$item" ]]; then
                local size
                size=$(get_file_size "$item" 2>/dev/null || echo "0")
                total_size=$((total_size + size))
            fi
        fi
    done < "$results_file"

    print_section "Cleanup Summary: $preset"
    echo "  Items found: $count"
    echo "  Total size:  $(format_bytes $total_size)"
    echo ""

    # Show preview
    echo "Preview (first 15 items):"
    head -15 "$results_file" | while IFS= read -r item; do
        echo "  - $item"
    done

    if ((count > 15)); then
        echo "  ... and $((count - 15)) more"
    fi
    echo ""

    if ! prompt_confirm "Delete these items?"; then
        log_info "Cleanup cancelled"
        rm -f "$results_file"
        return 0
    fi

    # Create undo session
    if [[ -z "$session_id" ]]; then
        session_id=$(undo_create_session "Cleanup preset: $preset")
    fi

    local deleted=0
    local failed=0

    while IFS= read -r item; do
        if [[ -e "$item" ]]; then
            if safe_delete "$item" "$session_id"; then
                ((deleted++))
            else
                ((failed++))
            fi
        fi
    done < "$results_file"

    undo_close_session "$session_id"
    rm -f "$results_file"

    echo ""
    print_divider
    log_success "Cleanup complete!"
    echo "  Deleted: $deleted items"
    echo "  Failed:  $failed items"
    echo "  Saved:   $(format_bytes $total_size)"
    echo ""
    log_info "Undo with: declutter undo $session_id"
}

# Run multiple presets
run_cleanup_all() {
    local search_path=${1:-.}
    local presets=(dev system browser)

    local session_id
    session_id=$(undo_create_session "Full cleanup")

    for preset in "${presets[@]}"; do
        run_cleanup "$preset" "$search_path" "$session_id"
    done

    undo_close_session "$session_id"
}

# =============================================================================
# Custom Presets
# =============================================================================

# Load custom preset from file
load_custom_preset() {
    local preset_file=$1
    local preset_name=$2

    if [[ ! -f "$preset_file" ]]; then
        log_error "Preset file not found: $preset_file"
        return 1
    fi

    # Create dynamic function
    eval "preset_$preset_name() { cat '$preset_file'; }"

    log_success "Loaded custom preset: $preset_name"
}

# Save current preset to file
save_preset() {
    local preset=$1
    local output_file=$2

    get_preset "$preset" > "$output_file"
    log_success "Saved preset to: $output_file"
}

# =============================================================================
# Export
# =============================================================================

export -f preset_dev preset_system preset_browser preset_media preset_logs
export -f preset_xcode preset_android
export -f list_presets get_preset show_preset
export -f scan_preset run_cleanup run_cleanup_all
export -f load_custom_preset save_preset
