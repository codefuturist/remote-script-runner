#!/bin/bash
# =============================================================================
# Validate Registry - Check scripts/registry.json and script files
# =============================================================================
#
# This script validates:
# 1. registry.json is valid JSON with required fields
# 2. All referenced script files exist
# 3. Script files have required metadata headers
# 4. Shell variants are consistent
#
# With --write flag, it can auto-update:
# - rsr CLI script mappings (get_script_path function)
# - rsr CLI command routing (main function case statement)
#
# Usage: ./tools/validate.sh [--strict] [--write] [--dry-run]
#
# Options:
#   --strict    Exit with error on warnings
#   --write     Auto-update rsr with script mappings from registry
#   --dry-run   Show what --write would change (implies --write)
#
# Exit codes:
#   0 - All validations passed
#   1 - Errors found (missing files, invalid JSON)
#   2 - Warnings found (with --strict flag)

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
DIM='\033[2m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
STRICT=false
WRITE_MODE=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict)
            STRICT=true
            shift
            ;;
        --write)
            WRITE_MODE=true
            shift
            ;;
        --dry-run)
            WRITE_MODE=true
            DRY_RUN=true
            shift
            ;;
        -h | --help)
            echo "Usage: $0 [--strict] [--write] [--dry-run]"
            echo ""
            echo "Options:"
            echo "  --strict    Exit with error on warnings"
            echo "  --write     Auto-update rsr with script mappings from registry"
            echo "  --dry-run   Show what --write would change without modifying files"
            exit 0
            ;;
        *) shift ;;
    esac
done

log_info() { printf "${BLUE}▸${NC} %s\n" "$1"; }
log_ok() { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_warn() {
    printf "${YELLOW}⚠${NC} %s\n" "$1"
    WARNINGS=$((WARNINGS + 1))
}
log_error() {
    printf "${RED}✗${NC} %s\n" "$1" >&2
    ERRORS=$((ERRORS + 1))
}
log_diff() { printf "${CYAN}  %s${NC}\n" "$1"; }

# Check dependencies
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        echo "Install with: brew install jq (macOS) or apt install jq (Linux)"
        exit 1
    fi
}

# Validate registry.json exists and is valid JSON
validate_registry_json() {
    log_info "Validating registry.json..."

    if [ ! -f "$REGISTRY_FILE" ]; then
        log_error "Registry file not found: $REGISTRY_FILE"
        return 1
    fi

    if ! jq empty "$REGISTRY_FILE" 2> /dev/null; then
        log_error "Invalid JSON in $REGISTRY_FILE"
        return 1
    fi

    # Check required top-level fields
    if [ "$(jq 'has("scripts")' "$REGISTRY_FILE")" != "true" ]; then
        log_error "Missing required field: scripts"
        return 1
    fi

    log_ok "registry.json is valid JSON"
}

# Validate each script entry
validate_script_entries() {
    log_info "Validating script entries..."

    local script_count=$(jq '.scripts | length' "$REGISTRY_FILE")
    local validated=0

    for ((i = 0; i < script_count; i++)); do
        local id=$(jq -r ".scripts[$i].id" "$REGISTRY_FILE")
        local name=$(jq -r ".scripts[$i].name" "$REGISTRY_FILE")

        printf "  ${DIM}Checking ${NC}%s${DIM}...${NC}" "$id"

        # Required fields
        local required_fields=("id" "name" "displayName" "description" "shells")
        for field in "${required_fields[@]}"; do
            local value=$(jq -r ".scripts[$i].$field // empty" "$REGISTRY_FILE")
            if [ -z "$value" ] || [ "$value" = "null" ]; then
                echo
                log_error "Script '$id' missing required field: $field"
            fi
        done

        # Validate shells object
        local shells=$(jq -r ".scripts[$i].shells | keys[]" "$REGISTRY_FILE" 2> /dev/null)
        if [ -z "$shells" ]; then
            echo
            log_error "Script '$id' has no shell variants defined"
        fi

        # Check each shell variant file exists
        for shell in $shells; do
            local path=$(jq -r ".scripts[$i].shells.$shell" "$REGISTRY_FILE")
            local full_path="$ROOT_DIR/$path"

            if [ ! -f "$full_path" ]; then
                echo
                log_error "Script '$id' shell '$shell' file not found: $path"
            fi
        done

        # Check recommended shells (warning only)
        local has_bash=$(jq -r ".scripts[$i].shells.bash // empty" "$REGISTRY_FILE")
        if [ -z "$has_bash" ]; then
            echo
            log_warn "Script '$id' missing bash variant (recommended)"
        fi

        validated=$((validated + 1))
        printf " ${GREEN}✓${NC}\n"
    done

    log_ok "Validated $validated script entries"
}

# Validate script file metadata headers
validate_script_headers() {
    log_info "Validating script file headers..."

    local script_count=$(jq '.scripts | length' "$REGISTRY_FILE")
    local checked=0

    for ((i = 0; i < script_count; i++)); do
        local id=$(jq -r ".scripts[$i].id" "$REGISTRY_FILE")
        local shells=$(jq -r ".scripts[$i].shells | keys[]" "$REGISTRY_FILE" 2> /dev/null)

        for shell in $shells; do
            local path=$(jq -r ".scripts[$i].shells.$shell" "$REGISTRY_FILE")
            local full_path="$ROOT_DIR/$path"

            if [ -f "$full_path" ]; then
                # Check for @name header
                if ! grep -q "^# @name" "$full_path" 2> /dev/null; then
                    log_warn "Script '$path' missing @name header"
                fi

                # Check for @description header
                if ! grep -q "^# @description" "$full_path" 2> /dev/null; then
                    log_warn "Script '$path' missing @description header"
                fi

                # Check for @version header
                if ! grep -q "^# @version" "$full_path" 2> /dev/null; then
                    log_warn "Script '$path' missing @version header"
                fi

                checked=$((checked + 1))
            fi
        done
    done

    log_ok "Checked $checked script files"
}

# Check for orphan scripts (not in registry)
check_orphan_scripts() {
    log_info "Checking for orphan scripts..."

    local orphans=0

    for shell_dir in "$ROOT_DIR/scripts/"*/; do
        local shell=$(basename "$shell_dir")

        # Skip non-shell directories
        case "$shell" in
            bash | zsh | sh | fish | powershell) ;;
            *) continue ;;
        esac

        for script_file in "$shell_dir"*; do
            [ -f "$script_file" ] || continue

            local filename=$(basename "$script_file")
            local relative_path="scripts/$shell/$filename"

            # Check if this path is in the registry
            local in_registry=$(jq --arg path "$relative_path" \
                '[.scripts[].shells | to_entries[].value] | any(. == $path)' \
                "$REGISTRY_FILE")

            if [ "$in_registry" != "true" ]; then
                log_warn "Orphan script not in registry: $relative_path"
                orphans=$((orphans + 1))
            fi
        done
    done

    if [ "$orphans" -eq 0 ]; then
        log_ok "No orphan scripts found"
    fi
}

# =============================================================================
# Auto-Update Functions (--write mode)
# =============================================================================

# Generate the get_script_path() function content from registry
generate_get_script_path() {
    local script_count
    script_count=$(jq '.scripts | length' "$REGISTRY_FILE")

    cat << 'EOF'
get_script_path() {
    script_name="$1"
    shell_type="$2"

    case "$script_name" in
EOF

    for ((i = 0; i < script_count; i++)); do
        local id name default_shell
        id=$(jq -r ".scripts[$i].id" "$REGISTRY_FILE")
        name=$(jq -r ".scripts[$i].name" "$REGISTRY_FILE")
        default_shell=$(jq -r ".scripts[$i].defaultShell // \"bash\"" "$REGISTRY_FILE")

        # Get shell variants
        local shells
        shells=$(jq -r ".scripts[$i].shells | keys[]" "$REGISTRY_FILE" 2> /dev/null || echo "bash")

        echo "        $id)"
        echo "            case \"\$shell_type\" in"

        for shell in $shells; do
            local path
            path=$(jq -r ".scripts[$i].shells.$shell" "$REGISTRY_FILE")
            echo "                $shell) echo \"$path\" ;;"
        done

        # Default fallback
        local default_path
        default_path=$(jq -r ".scripts[$i].shells.$default_shell // .scripts[$i].shells | to_entries[0].value" "$REGISTRY_FILE")
        echo "                *) echo \"$default_path\" ;;"
        echo "            esac"
        echo "            ;;"
    done

    cat << 'EOF'
        *)
            echo ""
            ;;
    esac
}
EOF
}

# Generate the main() case routing from registry
generate_main_routing() {
    local script_count
    script_count=$(jq '.scripts | length' "$REGISTRY_FILE")

    local routes=""

    for ((i = 0; i < script_count; i++)); do
        local id name
        id=$(jq -r ".scripts[$i].id" "$REGISTRY_FILE")
        name=$(jq -r ".scripts[$i].name" "$REGISTRY_FILE")

        # Build case pattern with aliases
        local pattern="$id"
        [ "$id" != "$name" ] && pattern="$id | $name"

        routes+="        $pattern)\n"
        routes+="            run_script \"$id\" \"\$@\"\n"
        routes+="            ;;\n"
    done

    echo -e "$routes"
}

# Update rsr file with generated content
update_rsr_file() {
    log_info "Updating rsr file..."

    if [ ! -f "$RSR_FILE" ]; then
        log_error "rsr file not found: $RSR_FILE"
        return 1
    fi

    # Create backup
    local backup_file="${RSR_FILE}.bak"
    cp "$RSR_FILE" "$backup_file"

    local temp_file
    temp_file=$(mktemp)
    local in_get_script_path=false
    local in_main_case=false
    local brace_count=0
    local skip_until_esac=false
    local found_script_routing=false

    # Generate new content
    local new_get_script_path
    new_get_script_path=$(generate_get_script_path)

    # Read the file and replace get_script_path function
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Detect start of get_script_path function
        if [[ "$line" =~ ^get_script_path\(\) ]]; then
            in_get_script_path=true
            brace_count=0
            echo "$new_get_script_path" >> "$temp_file"
            continue
        fi

        # Track braces inside get_script_path
        if $in_get_script_path; then
            [[ "$line" == *"{"* ]] && brace_count=$((brace_count + 1))
            [[ "$line" == *"}"* ]] && brace_count=$((brace_count - 1))

            # End of function
            if [[ $brace_count -eq 0 && "$line" == "}" ]]; then
                in_get_script_path=false
            fi
            continue
        fi

        echo "$line" >> "$temp_file"
    done < "$RSR_FILE"

    if $DRY_RUN; then
        log_info "Dry run - showing diff:"
        echo ""
        if command -v diff &> /dev/null; then
            diff --color=auto -u "$RSR_FILE" "$temp_file" || true
        else
            log_info "Install 'diff' to see changes"
        fi
        rm -f "$temp_file" "$backup_file"
    else
        mv "$temp_file" "$RSR_FILE"
        chmod +x "$RSR_FILE"
        rm -f "$backup_file"
        log_ok "Updated rsr file"
    fi
}

# Show summary of what would be updated
show_update_preview() {
    log_info "Preview of updates from registry.json:"
    echo ""

    local script_count
    script_count=$(jq '.scripts | length' "$REGISTRY_FILE")

    printf "  ${DIM}%-12s %-25s %s${NC}\n" "ID" "Name" "Shells"
    printf "  ${DIM}%-12s %-25s %s${NC}\n" "---" "----" "------"

    for ((i = 0; i < script_count; i++)); do
        local id name shells
        id=$(jq -r ".scripts[$i].id" "$REGISTRY_FILE")
        name=$(jq -r ".scripts[$i].name" "$REGISTRY_FILE")
        shells=$(jq -r ".scripts[$i].shells | keys | join(\", \")" "$REGISTRY_FILE")

        printf "  %-12s %-25s %s\n" "$id" "$name" "$shells"
    done
    echo ""
}

# Check shell variant coverage
check_shell_coverage() {
    log_info "Checking shell variant coverage..."

    local script_count=$(jq '.scripts | length' "$REGISTRY_FILE")

    echo
    printf "  ${DIM}%-20s %5s %5s %5s %5s${NC}\n" "Script" "bash" "zsh" "sh" "fish"
    printf "  ${DIM}%-20s %5s %5s %5s %5s${NC}\n" "------" "----" "---" "--" "----"

    for ((i = 0; i < script_count; i++)); do
        local id=$(jq -r ".scripts[$i].id" "$REGISTRY_FILE")

        local has_bash=$(jq -r ".scripts[$i].shells.bash // empty" "$REGISTRY_FILE")
        local has_zsh=$(jq -r ".scripts[$i].shells.zsh // empty" "$REGISTRY_FILE")
        local has_sh=$(jq -r ".scripts[$i].shells.sh // empty" "$REGISTRY_FILE")
        local has_fish=$(jq -r ".scripts[$i].shells.fish // empty" "$REGISTRY_FILE")

        local bash_mark="${GREEN}✓${NC}"
        local zsh_mark="${YELLOW}✗${NC}"
        local sh_mark="${YELLOW}✗${NC}"
        local fish_mark="${YELLOW}✗${NC}"

        [ -n "$has_bash" ] && bash_mark="${GREEN}✓${NC}" || bash_mark="${RED}✗${NC}"
        [ -n "$has_zsh" ] && zsh_mark="${GREEN}✓${NC}"
        [ -n "$has_sh" ] && sh_mark="${GREEN}✓${NC}"
        [ -n "$has_fish" ] && fish_mark="${GREEN}✓${NC}"

        printf "  %-20s %b %b %b %b\n" "$id" "$bash_mark" "$zsh_mark" "$sh_mark" "$fish_mark"
    done
    echo
}

# Summary
print_summary() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "$ERRORS" -gt 0 ]; then
        printf "${RED}Validation failed:${NC} %d errors, %d warnings\n" "$ERRORS" "$WARNINGS"
    elif [ "$WARNINGS" -gt 0 ]; then
        printf "${YELLOW}Validation passed with warnings:${NC} %d warnings\n" "$WARNINGS"
    else
        printf "${GREEN}Validation passed:${NC} All checks passed!\n"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main
main() {
    echo
    echo "┌────────────────────────────────────┐"
    echo "│     Registry Validation Tool       │"
    echo "└────────────────────────────────────┘"
    echo

    check_dependencies

    validate_registry_json || exit 1
    echo

    validate_script_entries
    echo

    validate_script_headers
    echo

    check_orphan_scripts
    echo

    check_shell_coverage

    print_summary

    # Exit codes
    if [ "$ERRORS" -gt 0 ]; then
        exit 1
    elif [ "$WARNINGS" -gt 0 ] && [ "$STRICT" = true ]; then
        exit 2
    fi

    exit 0
}

main "$@"
