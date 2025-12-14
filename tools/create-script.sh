#!/usr/bin/env bash
# =============================================================================
# Script Generator - Create new RSR scripts with complete scaffolding
# =============================================================================
#
# This interactive tool generates:
# 1. Script file from template with metadata
# 2. Test file skeleton with basic tests
# 3. Registry entry (with --update-registry flag)
# 4. Documentation stub (optional)
#
# Usage: ./tools/create-script.sh [OPTIONS] [SCRIPT_NAME]
#
# Options:
#   -n, --name NAME         Script name (interactive if not provided)
#   -c, --category CAT      Category (security, system, network, etc.)
#   -s, --subcategory SUB   Subcategory
#   -d, --description DESC  Description
#   --update-registry       Add entry to registry.json
#   --skip-tests            Don't create test file
#   --skip-docs             Don't create documentation stub
#   -y, --yes               Auto-confirm all prompts
#   -h, --help              Show this help

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
REGISTRY_FILE="$ROOT_DIR/scripts/registry.json"
TEMPLATE_DIR="$ROOT_DIR/scripts/_templates"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# Options
SCRIPT_NAME=""
CATEGORY=""
SUBCATEGORY=""
DESCRIPTION=""
UPDATE_REGISTRY=false
SKIP_TESTS=false
SKIP_DOCS=false
AUTO_YES=false

# Categories with subcategories
declare -A CATEGORIES=(
    ["security"]="audit hardening certificates ssh"
    ["system"]="health updates cleanup info packages"
    ["users"]="management setup"
    ["network"]="diagnostics dns"
    ["containers"]="docker compose"
    ["backup"]="database config git"
)

# =============================================================================
# Utilities
# =============================================================================

log_info() { printf "${BLUE}▸${NC} %s\n" "$1"; }
log_ok() { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
log_error() { printf "${RED}✗${NC} %s\n" "$1" >&2; }
log_step() { printf "\n${BOLD}${MAGENTA}▸ %s${NC}\n" "$1"; }

print_header() {
    echo
    echo "┌─────────────────────────────────────────┐"
    echo "│      RSR Script Generator v1.0          │"
    echo "└─────────────────────────────────────────┘"
    echo
}

prompt() {
    local prompt_text="$1"
    local default="$2"
    local result

    if [[ "$AUTO_YES" == "true" ]] && [[ -n "$default" ]]; then
        echo "$default"
        return
    fi

    if [[ -n "$default" ]]; then
        printf "${CYAN}?${NC} %s ${DIM}[%s]${NC}: " "$prompt_text" "$default"
    else
        printf "${CYAN}?${NC} %s: " "$prompt_text"
    fi

    read -r result
    echo "${result:-$default}"
}

confirm() {
    local prompt_text="$1"
    local default="${2:-n}"

    if [[ "$AUTO_YES" == "true" ]]; then
        return 0
    fi

    local yn
    printf "${CYAN}?${NC} %s ${DIM}[y/N]${NC}: " "$prompt_text"
    read -r yn

    case "${yn:-$default}" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

select_from_list() {
    local prompt_text="$1"
    shift
    local options=("$@")

    echo
    echo "${CYAN}${prompt_text}${NC}"
    echo

    local i=1
    for opt in "${options[@]}"; do
        printf "  ${DIM}%2d)${NC} %s\n" "$i" "$opt"
        ((i++))
    done
    echo

    local selection
    while true; do
        printf "${CYAN}?${NC} Enter number ${DIM}[1-%d]${NC}: " "${#options[@]}"
        read -r selection

        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#options[@]}" ]; then
            echo "${options[$((selection - 1))]}"
            return
        else
            log_error "Invalid selection. Try again."
        fi
    done
}

# =============================================================================
# Validation
# =============================================================================

validate_script_name() {
    local name="$1"

    # Check format (kebab-case)
    if ! [[ "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        log_error "Script name must be lowercase kebab-case (e.g., my-script)"
        return 1
    fi

    # Check if already exists
    if [[ -f "$ROOT_DIR/scripts/$CATEGORY/$SUBCATEGORY/$name.sh" ]]; then
        log_error "Script already exists: scripts/$CATEGORY/$SUBCATEGORY/$name.sh"
        return 1
    fi

    return 0
}

# =============================================================================
# Interactive Prompts
# =============================================================================

interactive_mode() {
    log_step "Script Configuration"

    # Script name
    if [[ -z "$SCRIPT_NAME" ]]; then
        while true; do
            SCRIPT_NAME=$(prompt "Script name (kebab-case)" "my-script")
            if validate_script_name "$SCRIPT_NAME"; then
                break
            fi
        done
    fi

    # Category
    if [[ -z "$CATEGORY" ]]; then
        local categories=("${!CATEGORIES[@]}")
        IFS=$'\n' categories=($(sort <<< "${categories[*]}"))
        unset IFS
        CATEGORY=$(select_from_list "Select category:" "${categories[@]}")
    fi

    # Subcategory
    if [[ -z "$SUBCATEGORY" ]]; then
        local subcats=(${CATEGORIES[$CATEGORY]})
        if [[ ${#subcats[@]} -gt 0 ]]; then
            SUBCATEGORY=$(select_from_list "Select subcategory:" "${subcats[@]}")
        else
            SUBCATEGORY=$(prompt "Subcategory" "general")
        fi
    fi

    # Description
    if [[ -z "$DESCRIPTION" ]]; then
        DESCRIPTION=$(prompt "Description" "Brief description of the script")
    fi

    echo
    log_step "Summary"
    echo
    printf "  ${DIM}Name:${NC}         %s\n" "$SCRIPT_NAME"
    printf "  ${DIM}Category:${NC}     %s\n" "$CATEGORY"
    printf "  ${DIM}Subcategory:${NC}  %s\n" "$SUBCATEGORY"
    printf "  ${DIM}Description:${NC}  %s\n" "$DESCRIPTION"
    printf "  ${DIM}Path:${NC}         scripts/%s/%s/%s.sh\n" "$CATEGORY" "$SUBCATEGORY" "$SCRIPT_NAME"
    echo

    if ! confirm "Create script with these settings?"; then
        log_warn "Cancelled"
        exit 0
    fi
}

# =============================================================================
# Generation Functions
# =============================================================================

create_script_file() {
    local script_dir="$ROOT_DIR/scripts/$CATEGORY/$SUBCATEGORY"
    local script_file="$script_dir/$SCRIPT_NAME.sh"

    log_info "Creating script file..."

    # Create directory
    mkdir -p "$script_dir"

    # Generate from template
    local template="$TEMPLATE_DIR/bash-script.template.sh"
    if [[ ! -f "$template" ]]; then
        log_error "Template not found: $template"
        return 1
    fi

    # Replace placeholders
    sed -e "s/{{SCRIPT_NAME}}/$SCRIPT_NAME/g" \
        -e "s/{{DESCRIPTION}}/$DESCRIPTION/g" \
        -e "s/{{AUTHOR}}/$(git config user.name 2> /dev/null || echo "RSR Team")/g" \
        "$template" > "$script_file"

    chmod +x "$script_file"

    log_ok "Created: $script_file"
    echo "       $(stat -f%z "$script_file" 2> /dev/null || stat -c%s "$script_file") bytes"
}

create_test_file() {
    if [[ "$SKIP_TESTS" == "true" ]]; then
        return
    fi

    local test_dir="$ROOT_DIR/test/unit"
    local test_file="$test_dir/$SCRIPT_NAME.bats"

    log_info "Creating test file..."

    # Create test file
    cat > "$test_file" << EOF
#!/usr/bin/env bats
# =============================================================================
# Tests for $SCRIPT_NAME.sh
# =============================================================================

load '../test_helper'

setup() {
    setup_test_env
    SCRIPT_PATH="scripts/$CATEGORY/$SUBCATEGORY/$SCRIPT_NAME.sh"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Basic Tests
# =============================================================================

@test "$SCRIPT_NAME: shows help with -h flag" {
    run bash "\$ROOT_DIR/\$SCRIPT_PATH" -h
    assert_success
    output=\$(strip_colors "\$output")
    assert_output --partial "Usage:"
}

@test "$SCRIPT_NAME: shows help with --help flag" {
    run bash "\$ROOT_DIR/\$SCRIPT_PATH" --help
    assert_success
    output=\$(strip_colors "\$output")
    assert_output --partial "Usage:"
}

@test "$SCRIPT_NAME: shows version with --version flag" {
    run bash "\$ROOT_DIR/\$SCRIPT_PATH" --version
    assert_success
    assert_output --partial "v1.0.0"
}

@test "$SCRIPT_NAME: fails with invalid option" {
    run bash "\$ROOT_DIR/\$SCRIPT_PATH" --invalid-option
    assert_failure
    output=\$(strip_colors "\$output")
    assert_output --partial "Unknown option"
}

@test "$SCRIPT_NAME: has valid bash syntax" {
    run bash -n "\$ROOT_DIR/\$SCRIPT_PATH"
    assert_success
}

@test "$SCRIPT_NAME: script is executable" {
    assert_file_executable "\$ROOT_DIR/\$SCRIPT_PATH"
}

@test "$SCRIPT_NAME: script has required metadata headers" {
    run grep "^# @name" "\$ROOT_DIR/\$SCRIPT_PATH"
    assert_success

    run grep "^# @description" "\$ROOT_DIR/\$SCRIPT_PATH"
    assert_success

    run grep "^# @version" "\$ROOT_DIR/\$SCRIPT_PATH"
    assert_success
}

# =============================================================================
# Functionality Tests
# =============================================================================

# TODO: Add specific functionality tests here

@test "$SCRIPT_NAME: dry-run mode works" {
    run bash "\$ROOT_DIR/\$SCRIPT_PATH" --dry-run
    assert_success
    output=\$(strip_colors "\$output")
    assert_output --partial "Dry run"
}
EOF

    chmod +x "$test_file"

    log_ok "Created: $test_file"
    echo "       Test template with 8 basic tests"
}

create_docs_stub() {
    if [[ "$SKIP_DOCS" == "true" ]]; then
        return
    fi

    local docs_dir="$ROOT_DIR/docs/scripts"
    local docs_file="$docs_dir/$SCRIPT_NAME.md"

    log_info "Creating documentation stub..."

    mkdir -p "$docs_dir"

    cat > "$docs_file" << EOF
# $SCRIPT_NAME

$DESCRIPTION

## Installation

\`\`\`bash
# Via rsr
rsr $SCRIPT_NAME --help

# Direct execution
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/$CATEGORY/$SUBCATEGORY/$SCRIPT_NAME.sh | bash -s -- --help
\`\`\`

## Usage

\`\`\`bash
$SCRIPT_NAME.sh [OPTIONS]
\`\`\`

### Options

| Option | Description |
|--------|-------------|
| \`-h, --help\` | Show help message |
| \`-v, --verbose\` | Enable verbose output |
| \`-d, --dry-run\` | Show what would be done |
| \`--version\` | Show version |

## Examples

\`\`\`bash
# Show help
./$SCRIPT_NAME.sh --help

# Run with verbose output
./$SCRIPT_NAME.sh -v

# Dry run mode
./$SCRIPT_NAME.sh --dry-run
\`\`\`

## Requirements

- Bash 4.0+
- TODO: Add specific requirements

## Platform Support

- ✅ Linux
- ✅ macOS
- ❌ Windows (use WSL)

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |

## See Also

- TODO: Add related scripts

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md)
EOF

    log_ok "Created: $docs_file"
}

add_to_registry() {
    if [[ "$UPDATE_REGISTRY" != "true" ]]; then
        return
    fi

    log_info "Adding to registry.json..."

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        log_error "Registry file not found: $REGISTRY_FILE"
        return 1
    fi

    # Generate script ID (remove .sh extension if present)
    local script_id="${SCRIPT_NAME%.sh}"
    local script_path="scripts/$CATEGORY/$SUBCATEGORY/$SCRIPT_NAME.sh"

    # Create registry entry
    local entry=$(
        cat << EOF
{
  "id": "$script_id",
  "name": "$SCRIPT_NAME",
  "command": "$script_id",
  "aliases": ["$script_id"],
  "description": "$DESCRIPTION",
  "example": "rsr $script_id",
  "category": "$CATEGORY",
  "subcategory": "$SUBCATEGORY",
  "path": "$script_path",
  "version": "1.0.0",
  "platforms": ["linux", "macos"],
  "requires": ["bash 4.0+"],
  "sudo": "none",
  "tags": ["$CATEGORY", "$SUBCATEGORY"]
}
EOF
    )

    # Add to registry (using jq)
    if command -v jq > /dev/null 2>&1; then
        local temp_file
        temp_file=$(mktemp)
        jq --argjson entry "$entry" '.scripts += [$entry]' "$REGISTRY_FILE" > "$temp_file"
        mv "$temp_file" "$REGISTRY_FILE"
        log_ok "Added to registry.json"
    else
        log_warn "jq not found - registry not updated"
        log_info "Install jq and run: ./tools/validate.sh --write"
    fi
}

# =============================================================================
# Summary
# =============================================================================

print_summary() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "${GREEN}${BOLD}✓ Script created successfully!${NC}\n"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    echo "${BOLD}Next steps:${NC}"
    echo
    printf "  ${DIM}1.${NC} Edit your script:\n"
    printf "     ${CYAN}%s${NC}\n" "vim scripts/$CATEGORY/$SUBCATEGORY/$SCRIPT_NAME.sh"
    echo

    if [[ "$SKIP_TESTS" != "true" ]]; then
        printf "  ${DIM}2.${NC} Add tests:\n"
        printf "     ${CYAN}%s${NC}\n" "vim test/unit/$SCRIPT_NAME.bats"
        echo
        printf "  ${DIM}3.${NC} Run tests:\n"
        printf "     ${CYAN}%s${NC}\n" "./test/run_tests.sh test/unit/$SCRIPT_NAME.bats"
        echo
    fi

    printf "  ${DIM}4.${NC} Validate:\n"
    printf "     ${CYAN}%s${NC}\n" "make lint test"
    echo

    if [[ "$UPDATE_REGISTRY" != "true" ]]; then
        printf "  ${DIM}5.${NC} Add to registry:\n"
        printf "     ${CYAN}%s${NC}\n" "./tools/create-script.sh --update-registry"
        echo
    fi

    echo "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

# =============================================================================
# Main
# =============================================================================

show_help() {
    cat << EOF
RSR Script Generator v1.0

Generate new scripts with complete scaffolding.

Usage:
    ${0##*/} [OPTIONS] [SCRIPT_NAME]

Options:
    -n, --name NAME         Script name (interactive if not provided)
    -c, --category CAT      Category (security, system, network, etc.)
    -s, --subcategory SUB   Subcategory
    -d, --description DESC  Description
    --update-registry       Add entry to registry.json
    --skip-tests            Don't create test file
    --skip-docs             Don't create documentation stub
    -y, --yes               Auto-confirm all prompts
    -h, --help              Show this help

Examples:
    # Interactive mode
    ./tools/create-script.sh

    # Specify all options
    ./tools/create-script.sh -n my-script -c system -s health -d "My script"

    # With registry update
    ./tools/create-script.sh --update-registry

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_help
                exit 0
                ;;
            -n | --name)
                SCRIPT_NAME="$2"
                shift 2
                ;;
            -c | --category)
                CATEGORY="$2"
                shift 2
                ;;
            -s | --subcategory)
                SUBCATEGORY="$2"
                shift 2
                ;;
            -d | --description)
                DESCRIPTION="$2"
                shift 2
                ;;
            --update-registry)
                UPDATE_REGISTRY=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --skip-docs)
                SKIP_DOCS=true
                shift
                ;;
            -y | --yes)
                AUTO_YES=true
                shift
                ;;
            *)
                if [[ -z "$SCRIPT_NAME" ]] && [[ ! "$1" =~ ^- ]]; then
                    SCRIPT_NAME="$1"
                fi
                shift
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    print_header

    # Interactive mode if missing required info
    if [[ -z "$SCRIPT_NAME" ]] || [[ -z "$CATEGORY" ]] || [[ -z "$SUBCATEGORY" ]]; then
        interactive_mode
    fi

    # Validate
    if ! validate_script_name "$SCRIPT_NAME"; then
        exit 1
    fi

    echo
    log_step "Generating Files"
    echo

    # Generate files
    create_script_file
    create_test_file
    create_docs_stub
    add_to_registry

    # Summary
    print_summary
}

main "$@"
