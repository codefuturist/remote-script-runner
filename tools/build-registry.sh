#!/bin/bash
# =============================================================================
# Build Registry - Generate files from scripts/registry.json
# =============================================================================
#
# This script reads scripts/registry.json and generates:
# 1. Script mappings in rsr (between --- BEGIN/END SCRIPT_MAPPINGS ---)
# 2. Script list in rsr (between --- BEGIN/END SCRIPT_LIST ---)
# 3. Script cards in index.html (between <!-- BEGIN/END SCRIPTS -->)
#
# Usage: ./tools/build-registry.sh
#
# Dependencies: jq (for JSON parsing)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
REGISTRY_FILE="$ROOT_DIR/scripts/registry.json"
RSR_FILE="$ROOT_DIR/rsr"
INDEX_FILE="$ROOT_DIR/index.html"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { printf "${BLUE}▸${NC} %s\n" "$1"; }
log_ok() { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
log_error() { printf "${RED}✗${NC} %s\n" "$1" >&2; }

# Check dependencies
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        echo "Install with: brew install jq (macOS) or apt install jq (Linux)"
        exit 1
    fi
}

# Generate script mappings for rsr
generate_script_mappings() {
    log_info "Generating script mappings..."
    
    local mappings=""
    local script_count=$(jq '.scripts | length' "$REGISTRY_FILE")
    
    for ((i=0; i<script_count; i++)); do
        local id=$(jq -r ".scripts[$i].id" "$REGISTRY_FILE")
        local name=$(jq -r ".scripts[$i].name" "$REGISTRY_FILE")
        local shells=$(jq -r ".scripts[$i].shells | keys[]" "$REGISTRY_FILE" 2>/dev/null || echo "bash")
        
        # Build aliases (id, name, and common variations)
        local aliases="$id"
        [ "$id" != "$name" ] && aliases="$aliases|$name"
        
        mappings+="        $aliases)\n"
        mappings+="            case \"\$shell_type\" in\n"
        
        # Add each shell variant
        for shell in $shells; do
            local path=$(jq -r ".scripts[$i].shells.$shell" "$REGISTRY_FILE")
            local ext=""
            case "$shell" in
                zsh) ext="zsh" ;;
                fish) ext="fish" ;;
                *) ext="sh" ;;
            esac
            mappings+="                $shell) echo \"$path\" ;;\n"
        done
        
        # Add fallback
        local default_path=$(jq -r ".scripts[$i].shells.bash // .scripts[$i].shells[.scripts[$i].defaultShell]" "$REGISTRY_FILE")
        mappings+="                *) echo \"$default_path\" ;;\n"
        mappings+="            esac\n"
        mappings+="            ;;\n"
    done
    
    mappings+="        *)\n"
    mappings+="            echo \"\"\n"
    mappings+="            ;;"
    
    echo -e "$mappings"
}

# Generate script list for rsr
generate_script_list() {
    log_info "Generating script list..."
    
    local list=""
    local script_count=$(jq '.scripts | length' "$REGISTRY_FILE")
    
    for ((i=0; i<script_count; i++)); do
        local id=$(jq -r ".scripts[$i].id" "$REGISTRY_FILE")
        local display=$(jq -r ".scripts[$i].displayName" "$REGISTRY_FILE")
        local desc=$(jq -r ".scripts[$i].description" "$REGISTRY_FILE")
        local example1=$(jq -r ".scripts[$i].examples[0].command // empty" "$REGISTRY_FILE")
        local example2=$(jq -r ".scripts[$i].examples[1].command // empty" "$REGISTRY_FILE")
        
        list+="        printf \"  \${GREEN}%-10s\${NC} %s\\\n\" \"$id\" \"$display\"\n"
        list+="        printf \"            %s\\\n\" \"$desc\"\n"
        [ -n "$example1" ] && list+="        printf \"            \${DIM}$example1\${NC}\\\n\"\n"
        [ -n "$example2" ] && list+="        printf \"            \${DIM}$example2\${NC}\\\n\"\n"
        list+="        printf \"\\\n\"\n"
    done
    
    echo -e "$list"
}

# Generate script cards HTML for index.html
generate_script_cards() {
    log_info "Generating script cards HTML..."
    
    local html=""
    local script_count=$(jq '.scripts | length' "$REGISTRY_FILE")
    
    for ((i=0; i<script_count; i++)); do
        local id=$(jq -r ".scripts[$i].id" "$REGISTRY_FILE")
        local name=$(jq -r ".scripts[$i].name" "$REGISTRY_FILE")
        local display=$(jq -r ".scripts[$i].displayName" "$REGISTRY_FILE")
        local desc=$(jq -r ".scripts[$i].description" "$REGISTRY_FILE")
        local tags=$(jq -r ".scripts[$i].tags | join(\",\")" "$REGISTRY_FILE")
        local example=$(jq -r ".scripts[$i].examples[0].command // \"rsr $id\"" "$REGISTRY_FILE")
        local example_desc=$(jq -r ".scripts[$i].examples[0].description // \"Run $display\"" "$REGISTRY_FILE")
        
        html+="      <div class=\"script-card searchable\" data-search=\"$id $name $tags\">\n"
        html+="        <h3>$display</h3>\n"
        html+="        <p>$desc</p>\n"
        html+="        <div class=\"command-block\">\n"
        html+="          <div class=\"command-header\">\n"
        html+="            <span class=\"command-label\">$example_desc</span>\n"
        html+="            <button class=\"copy-btn\" onclick=\"copyCommand(this)\">\n"
        html+="              <svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\"><rect x=\"9\" y=\"9\" width=\"13\" height=\"13\" rx=\"2\" ry=\"2\"/><path d=\"M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1\"/></svg>\n"
        html+="              Copy\n"
        html+="            </button>\n"
        html+="          </div>\n"
        html+="          <div class=\"command-code\">\n"
        html+="            <code>curl -fsSL https://codefuturist.github.io/remote-script-runner/rsr | sh -s -- $example</code>\n"
        html+="          </div>\n"
        html+="        </div>\n"
        html+="      </div>\n"
    done
    
    echo -e "$html"
}

# Update a file section between markers
update_section() {
    local file="$1"
    local begin_marker="$2"
    local end_marker="$3"
    local content="$4"
    local temp_file=$(mktemp)
    
    if ! grep -q "$begin_marker" "$file"; then
        log_warn "Marker '$begin_marker' not found in $file"
        return 1
    fi
    
    # Use awk to replace content between markers
    awk -v begin="$begin_marker" -v end="$end_marker" -v content="$content" '
        $0 ~ begin { print; printing=1; printf "%s", content; next }
        $0 ~ end { printing=0 }
        !printing { print }
    ' "$file" > "$temp_file"
    
    mv "$temp_file" "$file"
    return 0
}

# Main
main() {
    log_info "Building from registry..."
    echo
    
    check_dependencies
    
    if [ ! -f "$REGISTRY_FILE" ]; then
        log_error "Registry file not found: $REGISTRY_FILE"
        exit 1
    fi
    
    # Validate JSON
    if ! jq empty "$REGISTRY_FILE" 2>/dev/null; then
        log_error "Invalid JSON in $REGISTRY_FILE"
        exit 1
    fi
    
    local script_count=$(jq '.scripts | length' "$REGISTRY_FILE")
    log_ok "Found $script_count scripts in registry"
    echo
    
    # Generate and update rsr script mappings
    # Note: Manual update required - markers in rsr would need to be exact
    # For now, just show what would be generated
    log_info "Generated script mappings (update manually in rsr if needed):"
    echo "---"
    generate_script_mappings
    echo "---"
    echo
    
    # Generate and update rsr script list
    log_info "Generated script list (update manually in rsr if needed):"
    echo "---"
    generate_script_list
    echo "---"
    echo
    
    # Generate script cards HTML
    log_info "Generated script cards HTML:"
    echo "---"
    generate_script_cards
    echo "---"
    echo
    
    log_ok "Build complete!"
    echo
    log_info "To update files automatically, run with --write flag (TODO)"
}

main "$@"
