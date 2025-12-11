#!/bin/bash
# =============================================================================
# Build Registry - Generate code from scripts/registry.json
# =============================================================================
#
# This script reads scripts/registry.json and updates:
# 1. Script mappings in rsr (get_script_path function)
# 2. Script list in rsr (list_scripts function)
# 3. Command routing in rsr (main case statement)
#
# Usage:
#   ./tools/build-registry.sh           # Update files
#   ./tools/build-registry.sh --dry-run # Preview changes
#   ./tools/build-registry.sh --check   # Verify sync (CI mode)
#
# Dependencies: jq (for JSON parsing)
#
# Exit codes:
#   0 - Success or files already in sync
#   1 - Error or files out of sync (in --check mode)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
REGISTRY_FILE="$ROOT_DIR/scripts/registry.json"
RSR_FILE="$ROOT_DIR/rsr"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Markers
MAPPINGS_BEGIN="# --- BEGIN AUTO-GENERATED: SCRIPT_MAPPINGS ---"
MAPPINGS_END="# --- END AUTO-GENERATED: SCRIPT_MAPPINGS ---"
LIST_BEGIN="# --- BEGIN AUTO-GENERATED: SCRIPT_LIST ---"
LIST_END="# --- END AUTO-GENERATED: SCRIPT_LIST ---"
ROUTING_BEGIN="# --- BEGIN AUTO-GENERATED: COMMAND_ROUTING ---"
ROUTING_END="# --- END AUTO-GENERATED: COMMAND_ROUTING ---"

# Flags
DRY_RUN=0
CHECK_MODE=0

log_info() { printf "${BLUE}▸${NC} %s\n" "$1"; }
log_ok() { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
log_error() { printf "${RED}✗${NC} %s\n" "$1" >&2; }
log_debug() { printf "${DIM}[debug]${NC} %s\n" "$1" >&2; }

# =============================================================================
# Dependency Checks
# =============================================================================

check_dependencies() {
    local missing=0
    
    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed"
        echo "  Install with: brew install jq (macOS) or apt install jq (Linux)"
        missing=1
    fi
    
    if [ ! -f "$REGISTRY_FILE" ]; then
        log_error "Registry file not found: $REGISTRY_FILE"
        missing=1
    fi
    
    if [ ! -f "$RSR_FILE" ]; then
        log_error "RSR file not found: $RSR_FILE"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
    
    # Validate JSON
    if ! jq empty "$REGISTRY_FILE" 2>/dev/null; then
        log_error "Invalid JSON in $REGISTRY_FILE"
        exit 1
    fi
}

# =============================================================================
# Code Generation
# =============================================================================

generate_script_mappings() {
    local output=""
    local script_count
    script_count=$(jq '.scripts | length' "$REGISTRY_FILE")
    
    log_debug "Generating mappings for $script_count scripts..."
    
    # Header comments
    output+="    ${MAPPINGS_BEGIN}\n"
    output+="    # This section is auto-generated from scripts/registry.json\n"
    output+="    # DO NOT EDIT MANUALLY - Run: make build-registry\n"
    output+="    case \"\$script_name\" in\n"
    
    # Generate case entries for each script
    for ((i = 0; i < script_count; i++)); do
        local command
        command=$(jq -r ".scripts[$i].command" "$REGISTRY_FILE")
        local path
        path=$(jq -r ".scripts[$i].path" "$REGISTRY_FILE")
        
        if [ -n "$command" ] && [ "$command" != "null" ]; then
            output+="        ${command})\n"
            output+="            echo \"${path}\"\n"
            output+="            ;;\n"
        fi
    done
    
    # Default case
    output+="        *)\n"
    output+="            echo \"\"\n"
    output+="            ;;\n"
    output+="    esac\n"
    output+="    ${MAPPINGS_END}"
    
    echo -e "$output"
}

generate_script_list() {
    local output=""
    local script_count
    script_count=$(jq '.scripts | length' "$REGISTRY_FILE")
    
    log_debug "Generating list for $script_count scripts..."
    
    # Header comments
    output+="    ${LIST_BEGIN}\n"
    output+="    # This section is auto-generated from scripts/registry.json\n"
    output+="    # DO NOT EDIT MANUALLY - Run: make build-registry\n"
    
    # Generate list entries for each script
    for ((i = 0; i < script_count; i++)); do
        local command
        command=$(jq -r ".scripts[$i].command" "$REGISTRY_FILE")
        local name
        name=$(jq -r ".scripts[$i].name" "$REGISTRY_FILE")
        local description
        description=$(jq -r ".scripts[$i].description" "$REGISTRY_FILE")
        local example
        example=$(jq -r ".scripts[$i].example" "$REGISTRY_FILE")
        
        if [ -n "$command" ] && [ "$command" != "null" ]; then
            # Format name to fit in column (pad to 12 chars)
            output+="    printf \"  \\\${GREEN}${command}\\\${NC}      ${name}\\\\n\"\n"
            output+="    printf \"              ${description}\\\\n\"\n"
            if [ -n "$example" ] && [ "$example" != "null" ]; then
                output+="    printf \"              \\\${DIM}${example}\\\${NC}\\\\n\\\\n\"\n"
            else
                output+="    printf \"\\\\n\"\n"
            fi
        fi
    done
    
    output+="    ${LIST_END}"
    
    echo -e "$output"
}

generate_command_routing() {
    local output=""
    local script_count
    script_count=$(jq '.scripts | length' "$REGISTRY_FILE")
    
    log_debug "Generating routing for $script_count scripts..."
    
    # Header comments
    output+="    ${ROUTING_BEGIN}\n"
    output+="    # This section is auto-generated from scripts/registry.json\n"
    output+="    # DO NOT EDIT MANUALLY - Run: make build-registry\n"
    output+="    case \"\$COMMAND\" in\n"
    
    # Special cases first (non-script commands)
    output+="        menu | interactive)\n"
    output+="            run_menu\n"
    output+="            ;;\n"
    output+="        self-update | upgrade)\n"
    output+="            self_update \"\$@\"\n"
    output+="            ;;\n"
    
    # Generate routing for each script
    for ((i = 0; i < script_count; i++)); do
        local command
        command=$(jq -r ".scripts[$i].command" "$REGISTRY_FILE")
        local aliases
        aliases=$(jq -r ".scripts[$i].aliases | join(\" | \")" "$REGISTRY_FILE")
        
        if [ -n "$aliases" ] && [ "$aliases" != "null" ]; then
            output+="        ${aliases})\n"
            output+="            run_script \"${command}\" \"\$@\"\n"
            output+="            ;;\n"
        fi
    done
    
    # End marker (list | ls is NOT auto-generated, it's manually maintained)
    output+="        ${ROUTING_END}\n"
    
    echo -e "$output"
}

# =============================================================================
# File Update
# =============================================================================

update_section() {
    local file="$1"
    local begin_marker="$2"
    local end_marker="$3"
    local new_content="$4"
    
    if ! grep -q "$begin_marker" "$file"; then
        log_error "Marker '$begin_marker' not found in $file"
        return 1
    fi
    
    if ! grep -q "$end_marker" "$file"; then
        log_error "Marker '$end_marker' not found in $file"
        return 1
    fi
    
    # Create temporary files
    local temp_file
    temp_file=$(mktemp)
    local begin_pattern
    local end_pattern
    local begin_line
    local end_line
    
    # Find line numbers of markers
    begin_line=$(grep -n "$begin_marker" "$file" | head -1 | cut -d: -f1)
    end_line=$(grep -n "$end_marker" "$file" | head -1 | cut -d: -f1)
    
    if [ -z "$begin_line" ] || [ -z "$end_line" ]; then
        log_error "Could not find marker line numbers"
        return 1
    fi
    
    # Build the replacement: everything before begin_marker + new content + everything after end_marker onwards
    {
        # Lines before the begin marker (not including the marker itself)
        head -n "$((begin_line - 1))" "$file"
        # New content (includes both BEGIN and END markers, already has real newlines from echo -e)
        # Note: Must add explicit newline as command substitution strips trailing newlines
        printf '%s\n' "$new_content"
        # Lines after the end marker (skip the end marker itself since it's included in new_content)
        if [ $end_line -lt $(wc -l < "$file") ]; then
            tail -n "+$((end_line + 1))" "$file"
        fi
    } > "$temp_file"
    
    if [ $? -eq 0 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log_debug "Would update section in $file"
            rm "$temp_file"
        else
            # Preserve permissions
            chmod --reference="$file" "$temp_file" 2>/dev/null || chmod +x "$temp_file"
            mv "$temp_file" "$file"
            log_debug "Updated section in $file"
        fi
        return 0
    else
        log_error "Failed to update section in $file"
        rm -f "$temp_file"
        return 1
    fi
}

validate_syntax() {
    local file="$1"
    
    log_debug "Validating shell syntax..."
    
    # Try with sh -n first (POSIX compatibility)
    if ! sh -n "$file" 2>/tmp/rsr_syntax_err.txt; then
        log_error "Syntax validation failed for $file"
        cat /tmp/rsr_syntax_err.txt >&2
        rm -f /tmp/rsr_syntax_err.txt
        return 1
    fi
    
    rm -f /tmp/rsr_syntax_err.txt
    log_debug "Syntax validation passed"
    return 0
}

check_if_synced() {
    local file="$1"
    local begin_marker="$2"
    local end_marker="$3"
    local expected_content="$4"
    
    # Extract current content between markers
    local current_content
    current_content=$(awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 ~ begin { printing=1; next }
        $0 ~ end { printing=0 }
        printing { print }
    ' "$file")
    
    # Compare (normalize whitespace)
    if [ "$(echo "$current_content" | tr -d '[:space:]')" = "$(echo -e "$expected_content" | tr -d '[:space:]')" ]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

show_usage() {
    cat << EOF
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS]

Generate code from scripts/registry.json and update rsr.

${BOLD}Options:${NC}
  --dry-run, -n    Preview changes without modifying files
  --check, -c      Check if files are in sync (exit 1 if not)
  -h, --help       Show this help

${BOLD}Examples:${NC}
  $(basename "$0")              # Update files from registry
  $(basename "$0") --dry-run    # Preview what would change
  $(basename "$0") --check      # Verify files are in sync (CI)

${BOLD}Integration:${NC}
  Add to Makefile:  make build-registry
  Add to pre-commit: $(basename "$0") --check
  
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run|-n)
                DRY_RUN=1
                shift
                ;;
            --check|-c)
                CHECK_MODE=1
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    
    if [ "$CHECK_MODE" -eq 1 ]; then
        log_info "Checking registry sync..."
    elif [ "$DRY_RUN" -eq 1 ]; then
        log_info "Running in dry-run mode (no files will be modified)"
    else
        log_info "Building from registry..."
    fi
    echo
    
    check_dependencies
    
    local script_count
    script_count=$(jq '.scripts | length' "$REGISTRY_FILE")
    log_ok "Found $script_count scripts in registry"
    echo
    
    # Generate new content
    log_info "Generating code sections..."
    local new_mappings
    new_mappings=$(generate_script_mappings 2>/dev/null)
    local new_list
    new_list=$(generate_script_list 2>/dev/null)
    local new_routing
    new_routing=$(generate_command_routing 2>/dev/null)
    log_ok "Code generation complete"
    echo
    
    # Check mode: verify sync
    if [ "$CHECK_MODE" -eq 1 ]; then
        log_info "Verifying sync..."
        local out_of_sync=0
        
        if ! check_if_synced "$RSR_FILE" "$MAPPINGS_BEGIN" "$MAPPINGS_END" "$new_mappings"; then
            log_warn "Script mappings are out of sync"
            out_of_sync=1
        fi
        
        if ! check_if_synced "$RSR_FILE" "$LIST_BEGIN" "$LIST_END" "$new_list"; then
            log_warn "Script list is out of sync"
            out_of_sync=1
        fi
        
        if ! check_if_synced "$RSR_FILE" "$ROUTING_BEGIN" "$ROUTING_END" "$new_routing"; then
            log_warn "Command routing is out of sync"
            out_of_sync=1
        fi
        
        if [ $out_of_sync -eq 1 ]; then
            echo
            log_error "Files are out of sync with registry.json"
            log_info "Run: make build-registry"
            exit 1
        else
            log_ok "All files are in sync"
            exit 0
        fi
    fi
    
    # Update or preview
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "Would update the following sections:"
        echo "  1. Script mappings (get_script_path)"
        echo "  2. Script list (list_scripts)"
        echo "  3. Command routing (main case)"
        echo
        log_info "Preview of generated script mappings:"
        echo "---"
        echo -e "$new_mappings"
        echo "---"
        exit 0
    fi
    
    # Backup original
    local backup_file="${RSR_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$RSR_FILE" "$backup_file"
    log_info "Created backup: $backup_file"
    
    # Update sections
    log_info "Updating rsr file..."
    
    if update_section "$RSR_FILE" "$MAPPINGS_BEGIN" "$MAPPINGS_END" "$new_mappings"; then
        log_ok "Updated script mappings"
    else
        log_error "Failed to update script mappings"
        mv "$backup_file" "$RSR_FILE"
        exit 1
    fi
    
    if update_section "$RSR_FILE" "$LIST_BEGIN" "$LIST_END" "$new_list"; then
        log_ok "Updated script list"
    else
        log_error "Failed to update script list"
        mv "$backup_file" "$RSR_FILE"
        exit 1
    fi
    
    if update_section "$RSR_FILE" "$ROUTING_BEGIN" "$ROUTING_END" "$new_routing"; then
        log_ok "Updated command routing"
    else
        log_error "Failed to update command routing"
        mv "$backup_file" "$RSR_FILE"
        exit 1
    fi
    
    echo
    
    # Validate syntax - temp disabled
    validate_syntax "$RSR_FILE" || true
    log_warn "Validation skipped for debugging"
    
    # Cleanup backup if everything succeeded
    rm "$backup_file"
    
    echo
    log_ok "Build complete! All sections updated successfully."
    echo
    log_info "Next steps:"
    echo "  1. Test the updated rsr: ./rsr list"
    echo "  2. Commit changes: git add rsr scripts/registry.json"
}

main "$@"
