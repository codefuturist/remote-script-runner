#!/usr/bin/env bash
#
# Declutter - Orchestration Engine
# Central coordinator for scanners, actions, and pipeline execution
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_ENGINE_LOADED:-}" ]] && return 0
readonly _DECLUTTER_ENGINE_LOADED=1

# =============================================================================
# Dependencies
# =============================================================================

# Module directory
_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="$(dirname "$_MODULE_DIR")"

# Source core modules
# shellcheck source=utils.sh
source "$_MODULE_DIR/utils.sh"
# shellcheck source=logger.sh
source "$_MODULE_DIR/logger.sh"
# shellcheck source=config.sh
source "$_MODULE_DIR/config.sh"
# shellcheck source=ui.sh
source "$_MODULE_DIR/ui.sh"
# shellcheck source=../undo/journal.sh
source "$_LIB_DIR/undo/journal.sh"

# =============================================================================
# Module Registry
# =============================================================================

# Registered scanners
declare -A REGISTERED_SCANNERS=()

# Registered actions
declare -A REGISTERED_ACTIONS=()

# Registered presets
declare -A REGISTERED_PRESETS=()

# =============================================================================
# Module Registration
# =============================================================================

# Register a scanner module
register_scanner() {
    local name="$1"
    local function_name="$2"
    local description="${3:-}"

    REGISTERED_SCANNERS[$name]="$function_name"
    log_trace "Registered scanner: $name"
}

# Register an action module
register_action() {
    local name="$1"
    local function_name="$2"
    local description="${3:-}"

    REGISTERED_ACTIONS[$name]="$function_name"
    log_trace "Registered action: $name"
}

# Register a preset
register_preset() {
    local name="$1"
    local function_name="$2"
    local description="${3:-}"

    REGISTERED_PRESETS[$name]="$function_name"
    log_trace "Registered preset: $name"
}

# =============================================================================
# Module Loading
# =============================================================================

# Load all scanner modules
load_scanners() {
    local scanner_dir="$_LIB_DIR/scanners"

    if [[ -d "$scanner_dir" ]]; then
        for scanner_file in "$scanner_dir"/*.sh; do
            if [[ -f "$scanner_file" ]]; then
                # shellcheck source=/dev/null
                source "$scanner_file"
                log_trace "Loaded scanner: $(basename "$scanner_file")"
            fi
        done
    fi
}

# Load all action modules
load_actions() {
    local action_dir="$_LIB_DIR/actions"

    if [[ -d "$action_dir" ]]; then
        for action_file in "$action_dir"/*.sh; do
            if [[ -f "$action_file" ]]; then
                # shellcheck source=/dev/null
                source "$action_file"
                log_trace "Loaded action: $(basename "$action_file")"
            fi
        done
    fi
}

# Load all preset modules
load_presets() {
    local preset_dir="$_LIB_DIR/presets"

    if [[ -d "$preset_dir" ]]; then
        for preset_file in "$preset_dir"/*.sh; do
            if [[ -f "$preset_file" ]]; then
                # shellcheck source=/dev/null
                source "$preset_file"
                log_trace "Loaded preset: $(basename "$preset_file")"
            fi
        done
    fi
}

# Load all modules
load_all_modules() {
    load_scanners
    load_actions
    load_presets
}

# =============================================================================
# Engine Initialization
# =============================================================================

# Initialize the engine
engine_init() {
    log_debug "Initializing declutter engine..."

    # Load configuration
    load_config

    # Set log level from config
    DECLUTTER_LOG_LEVEL="${CONFIG_GLOBAL[log_level]}"

    # Ensure directories exist
    ensure_data_dirs

    # Initialize journal if enabled
    if is_journal_enabled; then
        journal_init
    fi

    # Load all modules
    load_all_modules

    # Check dependencies
    engine_check_dependencies

    log_debug "Engine initialized"
}

# Shutdown the engine
engine_shutdown() {
    log_debug "Shutting down engine..."

    # Close journal
    if is_journal_enabled; then
        journal_close
    fi

    log_debug "Engine shutdown complete"
}

# Check required dependencies
engine_check_dependencies() {
    local missing=()
    local optional_missing=()

    # Required
    for cmd in jq; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    # Recommended
    for cmd in fd fzf trash czkawka_cli dust; do
        if ! command -v "$cmd" &>/dev/null; then
            optional_missing+=("$cmd")
        fi
    done

    if ((${#missing[@]} > 0)); then
        log_error "Missing required dependencies: ${missing[*]}"
        log_info "Install with: brew install ${missing[*]}"
        return 1
    fi

    if ((${#optional_missing[@]} > 0)); then
        log_debug "Optional dependencies not found: ${optional_missing[*]}"
    fi

    return 0
}

# =============================================================================
# Pipeline Execution
# =============================================================================

# Scan results storage
declare -a SCAN_RESULTS=()
declare LAST_SCAN_FILE=""

# Run a scanner
engine_scan() {
    local scanner_name="$1"
    shift
    local args=("$@")

    # Get scanner function
    local scanner_fn="${REGISTERED_SCANNERS[$scanner_name]:-}"

    if [[ -z "$scanner_fn" ]]; then
        log_error "Unknown scanner: $scanner_name"
        log_info "Available scanners: ${!REGISTERED_SCANNERS[*]}" >&2
        return 1
    fi

    log_step "Running scanner: $scanner_name" >&2

    # Execute scanner
    local start_time
    start_time="$(timer_start)"

    local result
    result="$($scanner_fn "${args[@]}")"
    local exit_code=$?

    timer_end "$start_time" "Scan" >&2

    if ((exit_code != 0)); then
        log_error "Scanner failed: $scanner_name"
        return $exit_code
    fi

    # Store results
    LAST_SCAN_FILE="$(get_cache_dir)/scans/${scanner_name}_$(date +%Y%m%d_%H%M%S).json"
    mkdir -p "$(dirname "$LAST_SCAN_FILE")"
    echo "$result" > "$LAST_SCAN_FILE"

    log_debug "Results saved to: $LAST_SCAN_FILE"

    echo "$result"
}

# Execute an action
engine_action() {
    local action_name="$1"
    shift
    local args=("$@")

    # Get action function
    local action_fn="${REGISTERED_ACTIONS[$action_name]:-}"

    if [[ -z "$action_fn" ]]; then
        log_error "Unknown action: $action_name"
        log_info "Available actions: ${!REGISTERED_ACTIONS[*]}"
        return 1
    fi

    # Check dry run
    if is_dry_run; then
        log_info "[DRY-RUN] Would execute: $action_name ${args[*]}"
        return 0
    fi

    log_step "Executing action: $action_name"

    # Execute action
    $action_fn "${args[@]}"
}

# Run a preset
engine_preset() {
    local preset_name="$1"
    shift
    local args=("$@")

    # Get preset function
    local preset_fn="${REGISTERED_PRESETS[$preset_name]:-}"

    if [[ -z "$preset_fn" ]]; then
        log_error "Unknown preset: $preset_name"
        log_info "Available presets: ${!REGISTERED_PRESETS[*]}"
        return 1
    fi

    log_step "Running preset: $preset_name"

    # Execute preset
    $preset_fn "${args[@]}"
}

# =============================================================================
# Full Pipeline
# =============================================================================

# Run full pipeline: scan → review → action
engine_pipeline() {
    local scanner_name="$1"
    local action_name="${2:-delete}"
    local target_path="${3:-$PWD}"

    # Show header
    print_header "Declutter"

    # Show dry run banner if applicable
    if is_dry_run; then
        show_dry_run_banner
    fi

    # Phase 1: Scan
    log_step "Phase 1: Scanning"
    local scan_result
    scan_result="$(engine_scan "$scanner_name" "$target_path")"

    if [[ -z "$scan_result" ]] || [[ "$scan_result" == "[]" ]] || [[ "$scan_result" == "null" ]]; then
        log_success "No items found"
        return 0
    fi

    # Parse results
    local item_count
    item_count="$(echo "$scan_result" | jq 'if type == "array" then length else .items | length end' 2>/dev/null || echo "0")"

    log_info "Found $item_count items"

    # Phase 2: Review (if interactive)
    if is_interactive && ((item_count > 0)); then
        log_step "Phase 2: Review"

        # Show summary
        echo "$scan_result" | jq -r '
            if type == "array" then
                .[] | .path // .source // .
            else
                .items[]? | .path // .source // .
            end
        ' 2>/dev/null | head -20

        if ((item_count > 20)); then
            echo "  ... and $((item_count - 20)) more"
        fi

        echo ""
        if ! confirm "Proceed with $action_name?"; then
            log_info "Operation cancelled"
            return 0
        fi
    fi

    # Phase 3: Action
    log_step "Phase 3: Execute"

    local success=0
    local failed=0

    echo "$scan_result" | jq -r '
        if type == "array" then
            .[] | .path // .source // .
        else
            .items[]? | .path // .source // .
        end
    ' 2>/dev/null | while read -r item; do
        if [[ -n "$item" ]]; then
            if engine_action "$action_name" "$item"; then
                ((success++))
            else
                ((failed++))
            fi
        fi
    done

    # Summary
    print_divider
    log_success "Pipeline complete"
    print_kv "Successful" "$success"
    if ((failed > 0)); then
        print_kv "Failed" "$failed"
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# List available scanners
list_scanners() {
    echo "Available scanners:"
    for name in "${!REGISTERED_SCANNERS[@]}"; do
        echo "  - $name"
    done
}

# List available actions
list_actions() {
    echo "Available actions:"
    for name in "${!REGISTERED_ACTIONS[@]}"; do
        echo "  - $name"
    done
}

# List available presets
list_presets() {
    echo "Available presets:"
    for name in "${!REGISTERED_PRESETS[@]}"; do
        echo "  - $name"
    done
}

# Get last scan results
get_last_scan() {
    if [[ -f "$LAST_SCAN_FILE" ]]; then
        cat "$LAST_SCAN_FILE"
    else
        echo "[]"
    fi
}

# Clear scan cache
clear_scan_cache() {
    local cache_dir="$(get_cache_dir)/scans"
    if [[ -d "$cache_dir" ]]; then
        rm -rf "${cache_dir:?}"/*
        log_success "Scan cache cleared"
    fi
}
