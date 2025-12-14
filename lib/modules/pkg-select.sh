#!/bin/bash
# lib/modules/pkg-select.sh - RSR Interactive Package Selector
# Bash 4.0+ required for associative arrays and advanced features
#
# Usage: . "${RSR_LIB_DIR:-./lib}/modules/pkg-select.sh"
#        rsr_pkg_select [profile]
#
# Provides:
#   - Interactive package selection with TUI
#   - Profile browser with search
#   - Package toggle with checkbox UI
#   - Installation summary and batch install
#   - Fast installed package detection (cached)

# =============================================================================
# Guard: Prevent double-sourcing
# =============================================================================

[[ -n "${_RSR_MODULE_PKG_SELECT_LOADED:-}" ]] && return 0
_RSR_MODULE_PKG_SELECT_LOADED=1
_RSR_PKG_SELECT_VERSION="1.0.0"

# =============================================================================
# Dependencies
# =============================================================================

# Ensure core modules are loaded
_pkg_select_script_dir="${BASH_SOURCE[0]%/*}"
if [[ -z "${_RSR_CORE_INIT_LOADED:-}" ]]; then
    source "${_pkg_select_script_dir}/../core/init.sh" 2> /dev/null \
        || source "./lib/core/init.sh" 2> /dev/null || {
        echo "ERROR: RSR core/init.sh must be sourced first" >&2
        return 1
    }
fi

# Source interactive module for TUI functions
if [[ -z "${_RSR_CORE_INTERACTIVE_LOADED:-}" ]]; then
    source "${_pkg_select_script_dir}/../core/interactive.sh" 2> /dev/null \
        || source "./lib/core/interactive.sh" 2> /dev/null || {
        rsr_log_error "RSR interactive module required"
        return 1
    }
fi

# Source packages module for installation functions
if [[ -z "${_RSR_MODULE_PACKAGES_LOADED:-}" ]]; then
    source "${_pkg_select_script_dir}/packages.sh" 2> /dev/null \
        || source "./lib/modules/packages.sh" 2> /dev/null || {
        rsr_log_error "RSR packages module required"
        return 1
    }
fi

# =============================================================================
# Configuration
# =============================================================================

RSR_PKG_SELECT_MAX_VISIBLE="${RSR_PKG_SELECT_MAX_VISIBLE:-15}"
RSR_PKG_SELECT_LISTS_DIR="${RSR_PKG_LISTS_DIR:-${RSR_LIB_DIR:-./lib}/../config/packages}"

# =============================================================================
# Internal State
# =============================================================================

_PKG_SELECT_PACKAGES=()
_PKG_SELECT_DESCRIPTIONS=()
_PKG_SELECT_SELECTED=()
_PKG_SELECT_INSTALLED=()
_PKG_SELECT_FILTERED=()
_PKG_SELECT_INSTALLED_CACHE=""
_PKG_SELECT_CURRENT=0
_PKG_SELECT_SCROLL=0
_PKG_SELECT_SEARCH=""
_PKG_SELECT_SEARCH_MODE=0

# =============================================================================
# Terminal Control
# =============================================================================

# Extended terminal sequences (beyond what core/init provides)
if [[ -t 1 ]]; then
    _PKG_SEL_REVERSE=$'\033[7m'
    _PKG_SEL_REVERSE_OFF=$'\033[27m'
else
    _PKG_SEL_REVERSE=''
    _PKG_SEL_REVERSE_OFF=''
fi

# =============================================================================
# Installed Package Cache
# =============================================================================

# Build cache of all installed packages (called once at startup)
# This makes is_installed() O(1) instead of O(n) shell commands
_rsr_pkg_select_build_cache() {
    local mgr
    mgr=$(rsr_pkg_manager)

    rsr_log_debug "Building installed package cache for: $mgr"

    case "$mgr" in
        brew)
            # Get both formulae and casks
            _PKG_SELECT_INSTALLED_CACHE=$(
                brew list --formula -1 2> /dev/null
                brew list --cask -1 2> /dev/null
            )
            ;;
        apt)
            _PKG_SELECT_INSTALLED_CACHE=$(dpkg-query -W -f='${Package}\n' 2> /dev/null)
            ;;
        dnf | yum)
            _PKG_SELECT_INSTALLED_CACHE=$(rpm -qa --qf '%{NAME}\n' 2> /dev/null)
            ;;
        pacman)
            _PKG_SELECT_INSTALLED_CACHE=$(pacman -Qq 2> /dev/null)
            ;;
        apk)
            _PKG_SELECT_INSTALLED_CACHE=$(apk info -q 2> /dev/null)
            ;;
        *)
            _PKG_SELECT_INSTALLED_CACHE=""
            ;;
    esac
}

# Fast installed check using cache
_rsr_pkg_select_is_installed() {
    local pkg="$1"

    if [[ -z "$_PKG_SELECT_INSTALLED_CACHE" ]]; then
        # Fallback: check if command exists
        command -v "$pkg" &> /dev/null
        return
    fi

    # Fast grep against cached list
    echo "$_PKG_SELECT_INSTALLED_CACHE" | grep -qx "$pkg"
}

# =============================================================================
# Profile Discovery
# =============================================================================

# List available profiles
_rsr_pkg_select_list_profiles() {
    local dir="$RSR_PKG_SELECT_LISTS_DIR"

    for f in "$dir"/*.yaml; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f" .yaml)
        # Skip reference/config files
        [[ "$name" == "methods" || "$name" == "bootstrap" || "$name" == "example-multimethod" ]] && continue

        local desc
        desc=$(grep -m1 '^description:' "$f" 2> /dev/null | sed 's/^description:[[:space:]]*//' | tr -d '"')
        printf "%s|%s\n" "$name" "${desc:-No description}"
    done | sort
}

# =============================================================================
# YAML Package Parsing (Enhanced)
# =============================================================================

# Parse packages from YAML with names and descriptions
# Output: name|description per line
_rsr_pkg_select_parse_yaml() {
    local yaml_file="$1"
    local group="${2:-}"

    [[ ! -f "$yaml_file" ]] && return 1

    local in_top_packages=0   # In top-level packages: section
    local in_groups=0         # In groups: section
    local in_group_packages=0 # In a group's packages: subsection
    local current_name=""
    local current_desc=""
    local indent_level=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Calculate indentation
        local stripped="${line#"${line%%[![:space:]]*}"}"
        local leading="${line%%[![:space:]]*}"
        indent_level=${#leading}

        # Detect top-level sections (no indentation)
        if [[ $indent_level -eq 0 ]]; then
            if [[ "$line" =~ ^packages: ]]; then
                in_top_packages=1
                in_groups=0
                in_group_packages=0
                continue
            elif [[ "$line" =~ ^groups: ]]; then
                in_top_packages=0
                in_groups=1
                in_group_packages=0
                continue
            elif [[ "$line" =~ ^[a-zA-Z] ]]; then
                # Other top-level key, exit all sections
                in_top_packages=0
                in_groups=0
                in_group_packages=0
                continue
            fi
        fi

        # Detect packages: within a group (indent level 4+)
        if [[ $in_groups -eq 1 && $indent_level -ge 4 && "$line" =~ packages: ]]; then
            in_group_packages=1
            continue
        fi

        # Exit group packages on dedent to group level
        if [[ $in_group_packages -eq 1 && $indent_level -le 2 ]]; then
            in_group_packages=0
        fi

        # Parse package entries from top-level packages OR group packages
        if [[ $in_top_packages -eq 1 ]] || [[ $in_group_packages -eq 1 ]]; then
            # Extended format: - name: xyz
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*([^[:space:]#]+) ]]; then
                [[ -n "$current_name" ]] && echo "$current_name|$current_desc"
                current_name="${BASH_REMATCH[1]}"
                current_desc=""
            # Description line (within package block)
            elif [[ "$line" =~ ^[[:space:]]*description:[[:space:]]*["\']*(.+)["\']*$ ]]; then
                current_desc="${BASH_REMATCH[1]//\"/}"
                current_desc="${current_desc//\'/}"
            # Simple format: - package (only package name, no colon)
            elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*([a-zA-Z0-9_@/.-]+)[[:space:]]*$ ]]; then
                [[ -n "$current_name" ]] && echo "$current_name|$current_desc"
                current_name="${BASH_REMATCH[1]}"
                current_desc=""
            fi
        fi
    done < "$yaml_file"

    # Output last package
    [[ -n "$current_name" ]] && echo "$current_name|$current_desc"
}

# Load packages from profile into arrays
_rsr_pkg_select_load() {
    local profile="$1"
    local group="${2:-}"
    local yaml_file="$RSR_PKG_SELECT_LISTS_DIR/${profile}.yaml"

    [[ ! -f "$yaml_file" ]] && {
        rsr_log_error "Profile not found: $profile"
        return 1
    }

    # Reset state
    _PKG_SELECT_PACKAGES=()
    _PKG_SELECT_DESCRIPTIONS=()
    _PKG_SELECT_SELECTED=()
    _PKG_SELECT_INSTALLED=()
    _PKG_SELECT_FILTERED=()
    _PKG_SELECT_CURRENT=0
    _PKG_SELECT_SCROLL=0
    _PKG_SELECT_SEARCH=""
    _PKG_SELECT_SEARCH_MODE=0

    # Parse YAML and populate arrays
    while IFS='|' read -r name desc; do
        [[ -z "$name" ]] && continue
        _PKG_SELECT_PACKAGES+=("$name")
        _PKG_SELECT_DESCRIPTIONS+=("${desc:-}")
        _PKG_SELECT_SELECTED+=(0)
        if _rsr_pkg_select_is_installed "$name"; then
            _PKG_SELECT_INSTALLED+=(1)
        else
            _PKG_SELECT_INSTALLED+=(0)
        fi
    done < <(_rsr_pkg_select_parse_yaml "$yaml_file" "$group")

    # Initialize filter (show all)
    _rsr_pkg_select_apply_filter
}

# =============================================================================
# Filter/Search
# =============================================================================

_rsr_pkg_select_apply_filter() {
    _PKG_SELECT_FILTERED=()
    local query_lower
    query_lower=$(echo "$_PKG_SELECT_SEARCH" | tr '[:upper:]' '[:lower:]')

    for ((i = 0; i < ${#_PKG_SELECT_PACKAGES[@]}; i++)); do
        if [[ -z "$_PKG_SELECT_SEARCH" ]]; then
            _PKG_SELECT_FILTERED+=($i)
        else
            local name_lower desc_lower
            name_lower=$(echo "${_PKG_SELECT_PACKAGES[$i]}" | tr '[:upper:]' '[:lower:]')
            desc_lower=$(echo "${_PKG_SELECT_DESCRIPTIONS[$i]}" | tr '[:upper:]' '[:lower:]')
            if [[ "$name_lower" == *"$query_lower"* ]] || [[ "$desc_lower" == *"$query_lower"* ]]; then
                _PKG_SELECT_FILTERED+=($i)
            fi
        fi
    done

    # Reset position
    _PKG_SELECT_CURRENT=0
    _PKG_SELECT_SCROLL=0
}

# =============================================================================
# TUI Rendering
# =============================================================================

_rsr_pkg_select_render_header() {
    local profile="$1"
    local total=${#_PKG_SELECT_PACKAGES[@]}
    local filtered=${#_PKG_SELECT_FILTERED[@]}
    local selected_count=0

    for s in "${_PKG_SELECT_SELECTED[@]}"; do
        ((s == 1)) && ((selected_count++))
    done

    printf "\n${RSR_COLOR_BOLD}${RSR_COLOR_CYAN}Package Selector${RSR_COLOR_RESET}\n"
    if [[ -n "$_PKG_SELECT_SEARCH" ]]; then
        printf "${RSR_COLOR_DIM}Profile: ${RSR_COLOR_RESET}%s ${RSR_COLOR_DIM}| Showing: ${RSR_COLOR_RESET}%d/%d ${RSR_COLOR_DIM}| Selected: ${RSR_COLOR_RESET}${RSR_COLOR_GREEN}%d${RSR_COLOR_RESET}\n" \
            "$profile" "$filtered" "$total" "$selected_count"
    else
        printf "${RSR_COLOR_DIM}Profile: ${RSR_COLOR_RESET}%s ${RSR_COLOR_DIM}| Packages: ${RSR_COLOR_RESET}%d ${RSR_COLOR_DIM}| Selected: ${RSR_COLOR_RESET}${RSR_COLOR_GREEN}%d${RSR_COLOR_RESET}\n" \
            "$profile" "$total" "$selected_count"
    fi
    printf "${RSR_COLOR_DIM}─────────────────────────────────────────────────────────────${RSR_COLOR_RESET}\n"

    # Search bar or help
    if ((_PKG_SELECT_SEARCH_MODE == 1)); then
        printf "${RSR_COLOR_YELLOW}/${RSR_COLOR_RESET}%s${_PKG_SEL_REVERSE} ${_PKG_SEL_REVERSE_OFF} ${RSR_COLOR_DIM}(type to filter, Esc to clear)${RSR_COLOR_RESET}\n\n" "$_PKG_SELECT_SEARCH"
    elif [[ -n "$_PKG_SELECT_SEARCH" ]]; then
        printf "${RSR_COLOR_DIM}Filter: ${RSR_COLOR_RESET}${RSR_COLOR_YELLOW}%s${RSR_COLOR_RESET} ${RSR_COLOR_DIM}(/ search | Esc clear)${RSR_COLOR_RESET}\n\n" "$_PKG_SELECT_SEARCH"
    else
        printf "${RSR_COLOR_DIM}↑↓/jk nav | Space/x toggle | / search | a all | n none | Enter confirm | q quit${RSR_COLOR_RESET}\n\n"
    fi
}

_rsr_pkg_select_render_list() {
    local total=${#_PKG_SELECT_FILTERED[@]}
    local max_visible=$RSR_PKG_SELECT_MAX_VISIBLE
    local visible_start=$_PKG_SELECT_SCROLL
    local visible_end=$((_PKG_SELECT_SCROLL + max_visible))
    ((visible_end > total)) && visible_end=$total

    if ((total == 0)); then
        printf "${RSR_CLEAR_LINE}  ${RSR_COLOR_DIM}No packages match '%s'${RSR_COLOR_RESET}\n" "$_PKG_SELECT_SEARCH"
        for ((i = 1; i < max_visible; i++)); do
            printf "${RSR_CLEAR_LINE}\n"
        done
        printf "\n\n"
        return
    fi

    for ((vi = visible_start; vi < visible_end; vi++)); do
        local i=${_PKG_SELECT_FILTERED[$vi]}
        local name="${_PKG_SELECT_PACKAGES[$i]}"
        local desc="${_PKG_SELECT_DESCRIPTIONS[$i]}"
        local is_selected=${_PKG_SELECT_SELECTED[$i]}
        local is_installed=${_PKG_SELECT_INSTALLED[$i]}

        # Truncate description
        ((${#desc} > 40)) && desc="${desc:0:37}..."

        # Build line components
        local prefix="  "
        local checkbox="[ ]"
        local status=""
        local name_color="$RSR_COLOR_RESET"

        if ((vi == _PKG_SELECT_CURRENT)); then
            prefix="${RSR_COLOR_CYAN}❯${RSR_COLOR_RESET} "
        fi

        if ((is_selected == 1)); then
            checkbox="${RSR_COLOR_GREEN}[✓]${RSR_COLOR_RESET}"
        fi

        if ((is_installed == 1)); then
            status=" ${RSR_COLOR_DIM}(installed)${RSR_COLOR_RESET}"
            name_color="$RSR_COLOR_DIM"
        fi

        # Highlight search match
        if [[ -n "$_PKG_SELECT_SEARCH" ]]; then
            local query_lower name_lower
            query_lower=$(echo "$_PKG_SELECT_SEARCH" | tr '[:upper:]' '[:lower:]')
            name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
            if [[ "$name_lower" == *"$query_lower"* ]]; then
                name_color="$RSR_COLOR_YELLOW"
            fi
        fi

        printf "${RSR_CLEAR_LINE}${prefix}${checkbox} ${name_color}%-25s${RSR_COLOR_RESET} ${RSR_COLOR_DIM}%s${RSR_COLOR_RESET}${status}\n" "$name" "$desc"
    done

    # Pad remaining lines
    for ((vi = visible_end; vi < visible_start + max_visible; vi++)); do
        printf "${RSR_CLEAR_LINE}\n"
    done

    # Scroll indicators
    if ((_PKG_SELECT_SCROLL > 0)); then
        printf "${RSR_COLOR_DIM}  ↑ more above${RSR_COLOR_RESET}\n"
    else
        printf "\n"
    fi

    if ((visible_end < total)); then
        printf "${RSR_COLOR_DIM}  ↓ more below (%d total)${RSR_COLOR_RESET}\n" "$total"
    else
        printf "\n"
    fi
}

_rsr_pkg_select_clear_list() {
    local lines=$(($RSR_PKG_SELECT_MAX_VISIBLE + 3))
    for ((i = 0; i < lines; i++)); do
        printf "${RSR_CURSOR_UP}${RSR_CLEAR_LINE}"
    done
}

# =============================================================================
# Input Handling
# =============================================================================

_rsr_pkg_select_handle_input() {
    local key
    local total=${#_PKG_SELECT_FILTERED[@]}
    local max_visible=$RSR_PKG_SELECT_MAX_VISIBLE

    # Preserve whitespace
    IFS= read -rsn1 key

    # Search mode
    if ((_PKG_SELECT_SEARCH_MODE == 1)); then
        case "$key" in
            $'\x1b') # Escape
                _PKG_SELECT_SEARCH_MODE=0
                ;;
            $'\x7f' | $'\b') # Backspace
                if [[ -n "$_PKG_SELECT_SEARCH" ]]; then
                    _PKG_SELECT_SEARCH="${_PKG_SELECT_SEARCH%?}"
                    _rsr_pkg_select_apply_filter
                fi
                ;;
            '') # Enter
                _PKG_SELECT_SEARCH_MODE=0
                ;;
            *)
                if [[ "$key" =~ [[:print:]] ]]; then
                    _PKG_SELECT_SEARCH+="$key"
                    _rsr_pkg_select_apply_filter
                fi
                ;;
        esac
        return 0
    fi

    # Normal mode
    case "$key" in
        $'\x1b') # Escape sequence (arrow keys) or plain Escape
            # Read next 2 chars for arrow key sequence
            read -rsn2 seq_rest
            case "$seq_rest" in
                '[A') # Up
                    ((_PKG_SELECT_CURRENT > 0)) && ((_PKG_SELECT_CURRENT--))
                    ((_PKG_SELECT_CURRENT < _PKG_SELECT_SCROLL)) && ((_PKG_SELECT_SCROLL--))
                    ;;
                '[B') # Down
                    ((_PKG_SELECT_CURRENT < total - 1)) && ((_PKG_SELECT_CURRENT++))
                    ((_PKG_SELECT_CURRENT >= _PKG_SELECT_SCROLL + max_visible)) && ((_PKG_SELECT_SCROLL++))
                    ;;
                *) # Plain Escape or unknown - clear filter
                    if [[ -n "$_PKG_SELECT_SEARCH" ]]; then
                        _PKG_SELECT_SEARCH=""
                        _rsr_pkg_select_apply_filter
                    fi
                    ;;
            esac
            ;;
        'k') # Vim up
            ((_PKG_SELECT_CURRENT > 0)) && ((_PKG_SELECT_CURRENT--))
            ((_PKG_SELECT_CURRENT < _PKG_SELECT_SCROLL)) && ((_PKG_SELECT_SCROLL--))
            ;;
        'j') # Vim down
            ((_PKG_SELECT_CURRENT < total - 1)) && ((_PKG_SELECT_CURRENT++))
            ((_PKG_SELECT_CURRENT >= _PKG_SELECT_SCROLL + max_visible)) && ((_PKG_SELECT_SCROLL++))
            ;;
        '/') # Enter search mode
            _PKG_SELECT_SEARCH_MODE=1
            ;;
        ' ' | 'x' | 't') # Toggle
            if ((total > 0)); then
                local real_idx=${_PKG_SELECT_FILTERED[$_PKG_SELECT_CURRENT]}
                if ((_PKG_SELECT_SELECTED[real_idx] == 0)); then
                    _PKG_SELECT_SELECTED[real_idx]=1
                else
                    _PKG_SELECT_SELECTED[real_idx]=0
                fi
            fi
            ;;
        'a') # Select all (filtered)
            for idx in "${_PKG_SELECT_FILTERED[@]}"; do
                _PKG_SELECT_SELECTED[$idx]=1
            done
            ;;
        'n') # Select none (filtered)
            for idx in "${_PKG_SELECT_FILTERED[@]}"; do
                _PKG_SELECT_SELECTED[$idx]=0
            done
            ;;
        'q') # Quit
            return 1
            ;;
        '') # Enter - confirm
            return 2
            ;;
    esac

    return 0
}

# =============================================================================
# Profile Selection TUI
# =============================================================================

_rsr_pkg_select_profile() {
    local -a profiles=()
    local -a descs=()

    while IFS='|' read -r name desc; do
        profiles+=("$name")
        descs+=("${desc:-No description}")
    done < <(_rsr_pkg_select_list_profiles)

    local total=${#profiles[@]}
    local selected=0

    [[ $total -eq 0 ]] && {
        rsr_log_error "No package profiles found in $RSR_PKG_SELECT_LISTS_DIR"
        return 1
    }

    printf "${RSR_CURSOR_HIDE}"
    trap 'printf "${RSR_CURSOR_SHOW}"' EXIT

    printf "\n${RSR_COLOR_BOLD}${RSR_COLOR_CYAN}Select a package profile:${RSR_COLOR_RESET}\n"
    printf "${RSR_COLOR_DIM}↑/↓ navigate | Enter select | q quit${RSR_COLOR_RESET}\n\n"

    while true; do
        for ((i = 0; i < total; i++)); do
            printf "${RSR_CLEAR_LINE}"
            if ((i == selected)); then
                printf "  ${RSR_COLOR_CYAN}❯${RSR_COLOR_RESET} ${_PKG_SEL_REVERSE}%-18s${_PKG_SEL_REVERSE_OFF} ${RSR_COLOR_DIM}%s${RSR_COLOR_RESET}\n" "${profiles[$i]}" "${descs[$i]}"
            else
                printf "    %-18s ${RSR_COLOR_DIM}%s${RSR_COLOR_RESET}\n" "${profiles[$i]}" "${descs[$i]}"
            fi
        done

        IFS= read -rsn1 key
        case "$key" in
            $'\x1b')
                read -rsn2 key
                case "$key" in
                    '[A') ((selected > 0)) && ((selected--)) ;;
                    '[B') ((selected < total - 1)) && ((selected++)) ;;
                esac
                ;;
            'k') ((selected > 0)) && ((selected--)) ;;
            'j') ((selected < total - 1)) && ((selected++)) ;;
            'q')
                printf "${RSR_CURSOR_SHOW}"
                return 1
                ;;
            '') break ;;
        esac

        # Move cursor up to redraw
        for ((i = 0; i < total; i++)); do
            printf "${RSR_CURSOR_UP}"
        done
    done

    printf "${RSR_CURSOR_SHOW}"
    trap - EXIT
    echo "${profiles[$selected]}"
}

# =============================================================================
# Installation Summary & Execution
# =============================================================================

_rsr_pkg_select_show_summary() {
    local -a to_install=()

    for ((i = 0; i < ${#_PKG_SELECT_PACKAGES[@]}; i++)); do
        if ((_PKG_SELECT_SELECTED[i] == 1 && _PKG_SELECT_INSTALLED[i] == 0)); then
            to_install+=("${_PKG_SELECT_PACKAGES[$i]}")
        fi
    done

    printf "\n${RSR_COLOR_BOLD}Installation Summary${RSR_COLOR_RESET}\n"
    printf "${RSR_COLOR_DIM}─────────────────────────────────────────${RSR_COLOR_RESET}\n"

    if ((${#to_install[@]} == 0)); then
        printf "${RSR_COLOR_YELLOW}No new packages to install.${RSR_COLOR_RESET}\n"
        return 1
    fi

    printf "Packages to install (%d):\n" "${#to_install[@]}"
    for pkg in "${to_install[@]}"; do
        printf "  ${RSR_COLOR_GREEN}+${RSR_COLOR_RESET} %s\n" "$pkg"
    done

    printf "\n"
    read -rp "Install these packages? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy] ]]
}

_rsr_pkg_select_run_install() {
    local -a to_install=()

    for ((i = 0; i < ${#_PKG_SELECT_PACKAGES[@]}; i++)); do
        if ((_PKG_SELECT_SELECTED[i] == 1 && _PKG_SELECT_INSTALLED[i] == 0)); then
            to_install+=("${_PKG_SELECT_PACKAGES[$i]}")
        fi
    done

    printf "\n${RSR_COLOR_BOLD}Installing packages...${RSR_COLOR_RESET}\n"

    local success=0
    local failed=0

    for pkg in "${to_install[@]}"; do
        printf "${RSR_COLOR_CYAN}▸${RSR_COLOR_RESET} Installing %s..." "$pkg"
        if rsr_pkg_install "$pkg" 2> /dev/null; then
            printf " ${RSR_COLOR_GREEN}done${RSR_COLOR_RESET}\n"
            ((success++))
        else
            printf " ${RSR_COLOR_RED}failed${RSR_COLOR_RESET}\n"
            ((failed++))
        fi
    done

    printf "\n"
    if ((failed == 0)); then
        rsr_log_success "Successfully installed $success package(s)"
    else
        rsr_log_warn "Installed $success, failed $failed"
    fi
}

# =============================================================================
# Main Entry Point
# =============================================================================

# Interactive package selector
# Usage: rsr_pkg_select [profile] [group]
rsr_pkg_select() {
    local profile="${1:-}"
    local group="${2:-}"

    # Require interactive terminal
    if ! rsr_should_interact; then
        rsr_log_error "Interactive mode required for package selector"
        return 1
    fi

    # Build installed package cache (fast)
    rsr_log_info "Checking installed packages..."
    _rsr_pkg_select_build_cache

    # Select profile if not provided
    if [[ -z "$profile" ]]; then
        profile=$(_rsr_pkg_select_profile) || return 0
        clear
    fi

    # Load packages
    rsr_log_info "Loading packages from $profile..."
    if ! _rsr_pkg_select_load "$profile" "$group"; then
        return 1
    fi

    if ((${#_PKG_SELECT_PACKAGES[@]} == 0)); then
        rsr_log_warn "No packages found in profile"
        return 0
    fi

    # Main TUI loop
    printf "${RSR_CURSOR_HIDE}"
    trap 'printf "${RSR_CURSOR_SHOW}"; exit 0' EXIT INT TERM

    while true; do
        # Full screen redraw each frame
        clear
        _rsr_pkg_select_render_header "$profile"
        _rsr_pkg_select_render_list

        _rsr_pkg_select_handle_input
        local result=$?

        if ((result == 1)); then
            printf "${RSR_CURSOR_SHOW}"
            printf "\n${RSR_COLOR_DIM}Cancelled.${RSR_COLOR_RESET}\n"
            return 0
        elif ((result == 2)); then
            break
        fi
    done

    printf "${RSR_CURSOR_SHOW}"
    trap - EXIT INT TERM

    # Show summary and install
    if _rsr_pkg_select_show_summary; then
        _rsr_pkg_select_run_install
    fi
}

# =============================================================================
# Backward Compatibility / Aliases
# =============================================================================

pkg_select() { rsr_pkg_select "$@"; }

# =============================================================================
# Initialization Complete
# =============================================================================

rsr_log_debug "RSR Package Selector module loaded (v$_RSR_PKG_SELECT_VERSION)"
