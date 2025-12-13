#!/bin/bash
# pkg-select-prototype.sh - Interactive Package Selector Prototype
# Tests feasibility of TUI-based package selection
#
# Usage: ./tools/pkg-select-prototype.sh [profile]

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PKG_DIR="$PROJECT_ROOT/config/packages"

# Colors
if [[ -t 1 ]]; then
    CYAN=$'\033[0;36m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    RED=$'\033[0;31m'
    BLUE=$'\033[0;34m'
    DIM=$'\033[2m'
    BOLD=$'\033[1m'
    NC=$'\033[0m'
    REVERSE=$'\033[7m'
    CURSOR_HIDE=$'\033[?25l'
    CURSOR_SHOW=$'\033[?25h'
    CLEAR_LINE=$'\033[2K'
    CURSOR_UP=$'\033[1A'
else
    CYAN='' GREEN='' YELLOW='' RED='' BLUE='' DIM='' BOLD='' NC=''
    REVERSE='' CURSOR_HIDE='' CURSOR_SHOW='' CLEAR_LINE='' CURSOR_UP=''
fi

# State
declare -a PACKAGES=()
declare -a DESCRIPTIONS=()
declare -a SELECTED=()
declare -a INSTALLED=()
declare -a FILTERED_INDICES=()  # Indices into PACKAGES array that match filter
CURRENT_INDEX=0
SCROLL_OFFSET=0
MAX_VISIBLE=15
SEARCH_QUERY=""
SEARCH_MODE=0

# =============================================================================
# Package Detection
# =============================================================================

PKG_MANAGER=""
INSTALLED_CACHE=""

detect_package_manager() {
    if [[ -n "$PKG_MANAGER" ]]; then
        echo "$PKG_MANAGER"
        return
    fi

    if command -v brew &>/dev/null; then
        PKG_MANAGER="brew"
    elif command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    else
        PKG_MANAGER="unknown"
    fi
    echo "$PKG_MANAGER"
}

# Build cache of installed packages (called once at startup)
build_installed_cache() {
    local mgr
    mgr=$(detect_package_manager)

    case "$mgr" in
        brew)
            # Get both formulae and casks in one go
            INSTALLED_CACHE=$(brew list --formula -1 2>/dev/null; brew list --cask -1 2>/dev/null)
            ;;
        apt)
            INSTALLED_CACHE=$(dpkg-query -W -f='${Package}\n' 2>/dev/null)
            ;;
        dnf)
            INSTALLED_CACHE=$(rpm -qa --qf '%{NAME}\n' 2>/dev/null)
            ;;
        *)
            INSTALLED_CACHE=""
            ;;
    esac
}

is_installed() {
    local pkg="$1"

    if [[ -z "$INSTALLED_CACHE" ]]; then
        # Fallback to command check if no cache
        command -v "$pkg" &>/dev/null
        return
    fi

    # Fast grep lookup against cached list
    echo "$INSTALLED_CACHE" | grep -qx "$pkg"
}

# =============================================================================
# YAML Parsing (Simple extraction)
# =============================================================================

parse_packages_from_yaml() {
    local yaml_file="$1"
    local group="${2:-}"

    [[ ! -f "$yaml_file" ]] && return 1

    # Extract packages with names and descriptions
    # Handle both simple format (- package) and extended format (- name: package)
    local in_packages=0
    local in_target_group=0
    local current_name=""
    local current_desc=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Check for groups section or specific group
        if [[ -n "$group" ]]; then
            if [[ "$line" =~ ^[[:space:]]{2}${group}: ]]; then
                in_target_group=1
                continue
            elif [[ $in_target_group -eq 1 && "$line" =~ ^[[:space:]]{2}[a-zA-Z] && ! "$line" =~ ^[[:space:]]{2}${group} ]]; then
                in_target_group=0
            fi
        fi

        # Look for packages section
        if [[ "$line" =~ ^[[:space:]]*packages: ]]; then
            in_packages=1
            continue
        fi

        # Exit packages section on new top-level key
        if [[ $in_packages -eq 1 && "$line" =~ ^[a-zA-Z] ]]; then
            in_packages=0
        fi

        # Parse package entries
        if [[ $in_packages -eq 1 ]] || [[ $in_target_group -eq 1 ]]; then
            # Extended format: - name: xyz
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*([^[:space:]#]+) ]]; then
                [[ -n "$current_name" ]] && echo "$current_name|$current_desc"
                current_name="${BASH_REMATCH[1]}"
                current_desc=""
            # Description line
            elif [[ "$line" =~ ^[[:space:]]*description:[[:space:]]*(.+) ]]; then
                current_desc="${BASH_REMATCH[1]//\"/}"
            # Simple format: - package
            elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*([a-zA-Z0-9_-]+)[[:space:]]*$ ]]; then
                [[ -n "$current_name" ]] && echo "$current_name|$current_desc"
                current_name="${BASH_REMATCH[1]}"
                current_desc=""
            fi
        fi
    done < "$yaml_file"

    # Output last package
    [[ -n "$current_name" ]] && echo "$current_name|$current_desc"
}

load_packages() {
    local profile="$1"
    local group="${2:-}"
    local yaml_file="$PKG_DIR/${profile}.yaml"

    [[ ! -f "$yaml_file" ]] && {
        echo "Profile not found: $profile" >&2
        return 1
    }

    PACKAGES=()
    DESCRIPTIONS=()
    SELECTED=()
    INSTALLED=()

    local pkg_data
    while IFS='|' read -r name desc; do
        [[ -z "$name" ]] && continue
        PACKAGES+=("$name")
        DESCRIPTIONS+=("${desc:-No description}")
        SELECTED+=(0)
        if is_installed "$name"; then
            INSTALLED+=(1)
        else
            INSTALLED+=(0)
        fi
    done < <(parse_packages_from_yaml "$yaml_file" "$group")
}

# =============================================================================
# TUI Rendering
# =============================================================================

apply_filter() {
    FILTERED_INDICES=()
    local query_lower
    query_lower=$(echo "$SEARCH_QUERY" | tr '[:upper:]' '[:lower:]')

    for ((i=0; i<${#PACKAGES[@]}; i++)); do
        if [[ -z "$SEARCH_QUERY" ]]; then
            FILTERED_INDICES+=($i)
        else
            local name_lower desc_lower
            name_lower=$(echo "${PACKAGES[$i]}" | tr '[:upper:]' '[:lower:]')
            desc_lower=$(echo "${DESCRIPTIONS[$i]}" | tr '[:upper:]' '[:lower:]')
            if [[ "$name_lower" == *"$query_lower"* ]] || [[ "$desc_lower" == *"$query_lower"* ]]; then
                FILTERED_INDICES+=($i)
            fi
        fi
    done

    # Reset position
    CURRENT_INDEX=0
    SCROLL_OFFSET=0
}

render_header() {
    local profile="$1"
    local total=${#PACKAGES[@]}
    local filtered=${#FILTERED_INDICES[@]}
    local selected_count=0

    for s in "${SELECTED[@]}"; do
        ((s == 1)) && ((selected_count++))
    done

    printf "\n${BOLD}${CYAN}Package Selector${NC} ${DIM}(prototype)${NC}\n"
    if [[ -n "$SEARCH_QUERY" ]]; then
        printf "${DIM}Profile: ${NC}${profile} ${DIM}| Showing: ${NC}${filtered}/${total} ${DIM}| Selected: ${NC}${GREEN}${selected_count}${NC}\n"
    else
        printf "${DIM}Profile: ${NC}${profile} ${DIM}| Packages: ${NC}${total} ${DIM}| Selected: ${NC}${GREEN}${selected_count}${NC}\n"
    fi
    printf "${DIM}─────────────────────────────────────────────────────────────${NC}\n"

    # Show search bar or help
    if ((SEARCH_MODE == 1)); then
        printf "${YELLOW}/${NC}${SEARCH_QUERY}${REVERSE} ${NC} ${DIM}(type to filter, Esc to clear)${NC}\n\n"
    elif [[ -n "$SEARCH_QUERY" ]]; then
        printf "${DIM}Filter: ${NC}${YELLOW}${SEARCH_QUERY}${NC} ${DIM}(/ search | Esc clear)${NC}\n\n"
    else
        printf "${DIM}↑↓/jk nav | Space toggle | / search | a all | n none | Enter confirm | q quit${NC}\n\n"
    fi
}

render_package_list() {
    local total=${#FILTERED_INDICES[@]}
    local visible_start=$SCROLL_OFFSET
    local visible_end=$((SCROLL_OFFSET + MAX_VISIBLE))
    ((visible_end > total)) && visible_end=$total

    if ((total == 0)); then
        printf "${CLEAR_LINE}  ${DIM}No packages match '${SEARCH_QUERY}'${NC}\n"
        for ((i=1; i<MAX_VISIBLE; i++)); do
            printf "${CLEAR_LINE}\n"
        done
        printf "\n\n"
        return
    fi

    for ((vi=visible_start; vi<visible_end; vi++)); do
        local i=${FILTERED_INDICES[$vi]}
        local name="${PACKAGES[$i]}"
        local desc="${DESCRIPTIONS[$i]}"
        local is_selected=${SELECTED[$i]}
        local is_installed=${INSTALLED[$i]}

        # Truncate description
        ((${#desc} > 45)) && desc="${desc:0:42}..."

        # Build line
        local prefix="  "
        local checkbox="[ ]"
        local status=""
        local name_color="$NC"

        if ((vi == CURRENT_INDEX)); then
            prefix="${CYAN}❯${NC} "
        fi

        if ((is_selected == 1)); then
            checkbox="${GREEN}[✓]${NC}"
        fi

        if ((is_installed == 1)); then
            status=" ${DIM}(installed)${NC}"
            name_color="$DIM"
        fi

        # Highlight search match in name
        if [[ -n "$SEARCH_QUERY" ]]; then
            local query_lower name_lower match_start
            query_lower=$(echo "$SEARCH_QUERY" | tr '[:upper:]' '[:lower:]')
            name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
            if [[ "$name_lower" == *"$query_lower"* ]]; then
                # Simple highlight - just show the name with color
                name_color="$YELLOW"
            fi
        fi

        printf "${CLEAR_LINE}${prefix}${checkbox} ${name_color}%-25s${NC} ${DIM}%s${NC}${status}\n" "$name" "$desc"
    done

    # Pad remaining lines
    for ((vi=visible_end; vi<visible_start + MAX_VISIBLE; vi++)); do
        printf "${CLEAR_LINE}\n"
    done

    # Scroll indicators
    if ((SCROLL_OFFSET > 0)); then
        printf "${DIM}  ↑ more above${NC}\n"
    else
        printf "\n"
    fi

    if ((visible_end < total)); then
        printf "${DIM}  ↓ more below (${total} total)${NC}\n"
    else
        printf "\n"
    fi
}

clear_package_list() {
    local lines=$((MAX_VISIBLE + 3))
    for ((i=0; i<lines; i++)); do
        printf "${CURSOR_UP}${CLEAR_LINE}"
    done
}

# =============================================================================
# Input Handling
# =============================================================================

handle_input() {
    local key
    local total=${#FILTERED_INDICES[@]}

    # Use IFS= to preserve whitespace characters like space
    IFS= read -rsn1 key

    # Search mode input handling
    if ((SEARCH_MODE == 1)); then
        case "$key" in
            $'\x1b')  # Escape - exit search mode
                SEARCH_MODE=0
                ;;
            $'\x7f'|$'\b')  # Backspace
                if [[ -n "$SEARCH_QUERY" ]]; then
                    SEARCH_QUERY="${SEARCH_QUERY%?}"
                    apply_filter
                fi
                ;;
            '')  # Enter - confirm search and exit search mode
                SEARCH_MODE=0
                ;;
            *)  # Add character to search
                if [[ "$key" =~ [[:print:]] ]]; then
                    SEARCH_QUERY+="$key"
                    apply_filter
                fi
                ;;
        esac
        return 0
    fi

    # Normal mode input handling
    case "$key" in
        $'\x1b')  # Escape sequence or clear filter
            read -rsn1 -t 0.01 seq_check
            if [[ -n "$seq_check" ]]; then
                read -rsn1 seq_end
                case "$seq_check$seq_end" in
                    '[A')  # Up
                        ((CURRENT_INDEX > 0)) && ((CURRENT_INDEX--))
                        ((CURRENT_INDEX < SCROLL_OFFSET)) && ((SCROLL_OFFSET--))
                        ;;
                    '[B')  # Down
                        ((CURRENT_INDEX < total - 1)) && ((CURRENT_INDEX++))
                        ((CURRENT_INDEX >= SCROLL_OFFSET + MAX_VISIBLE)) && ((SCROLL_OFFSET++))
                        ;;
                esac
            else
                # Plain Escape - clear filter
                if [[ -n "$SEARCH_QUERY" ]]; then
                    SEARCH_QUERY=""
                    apply_filter
                fi
            fi
            ;;
        'k')  # Vim up
            ((CURRENT_INDEX > 0)) && ((CURRENT_INDEX--))
            ((CURRENT_INDEX < SCROLL_OFFSET)) && ((SCROLL_OFFSET--))
            ;;
        'j')  # Vim down
            ((CURRENT_INDEX < total - 1)) && ((CURRENT_INDEX++))
            ((CURRENT_INDEX >= SCROLL_OFFSET + MAX_VISIBLE)) && ((SCROLL_OFFSET++))
            ;;
        '/')  # Enter search mode
            SEARCH_MODE=1
            ;;
        ' ')  # Space - toggle selection
            if ((total > 0)); then
                local real_idx=${FILTERED_INDICES[$CURRENT_INDEX]}
                if ((SELECTED[real_idx] == 0)); then
                    SELECTED[real_idx]=1
                else
                    SELECTED[real_idx]=0
                fi
            fi
            ;;
        't'|'x')  # Alternative toggle keys
            if ((total > 0)); then
                local real_idx=${FILTERED_INDICES[$CURRENT_INDEX]}
                if ((SELECTED[real_idx] == 0)); then
                    SELECTED[real_idx]=1
                else
                    SELECTED[real_idx]=0
                fi
            fi
            ;;
        'a')  # Select all (visible/filtered)
            for idx in "${FILTERED_INDICES[@]}"; do
                SELECTED[$idx]=1
            done
            ;;
        'n')  # Select none (visible/filtered)
            for idx in "${FILTERED_INDICES[@]}"; do
                SELECTED[$idx]=0
            done
            ;;
        'q')  # Quit
            return 1
            ;;
        '')  # Enter - confirm
            return 2
            ;;
    esac

    return 0
}

# =============================================================================
# Profile Selection
# =============================================================================

list_profiles() {
    for f in "$PKG_DIR"/*.yaml; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f" .yaml)
        # Skip reference files
        [[ "$name" == "methods" || "$name" == "bootstrap" || "$name" == "example-multimethod" ]] && continue

        local desc
        desc=$(grep -m1 '^description:' "$f" 2>/dev/null | sed 's/^description:[[:space:]]*//' | tr -d '"')
        printf "%-20s %s\n" "$name" "${desc:-}"
    done
}

select_profile() {
    local -a profiles=()
    local -a descs=()

    for f in "$PKG_DIR"/*.yaml; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f" .yaml)
        [[ "$name" == "methods" || "$name" == "bootstrap" || "$name" == "example-multimethod" ]] && continue

        profiles+=("$name")
        local desc
        desc=$(grep -m1 '^description:' "$f" 2>/dev/null | sed 's/^description:[[:space:]]*//' | tr -d '"')
        descs+=("${desc:-No description}")
    done

    local total=${#profiles[@]}
    local selected=0

    printf "${CURSOR_HIDE}"
    trap 'printf "${CURSOR_SHOW}"' EXIT

    printf "\n${BOLD}${CYAN}Select a package profile:${NC}\n"
    printf "${DIM}↑/↓ navigate | Enter select | q quit${NC}\n\n"

    while true; do
        for ((i=0; i<total; i++)); do
            printf "${CLEAR_LINE}"
            if ((i == selected)); then
                printf "  ${CYAN}❯${NC} ${REVERSE}%-18s${NC} ${DIM}%s${NC}\n" "${profiles[$i]}" "${descs[$i]}"
            else
                printf "    %-18s ${DIM}%s${NC}\n" "${profiles[$i]}" "${descs[$i]}"
            fi
        done

        read -rsn1 key
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
            'q') printf "${CURSOR_SHOW}"; exit 0 ;;
            '') break ;;
        esac

        # Move cursor up to redraw
        for ((i=0; i<total; i++)); do
            printf "${CURSOR_UP}"
        done
    done

    printf "${CURSOR_SHOW}"
    echo "${profiles[$selected]}"
}

# =============================================================================
# Main UI Loop
# =============================================================================

show_summary() {
    local -a to_install=()

    for ((i=0; i<${#PACKAGES[@]}; i++)); do
        if ((SELECTED[i] == 1 && INSTALLED[i] == 0)); then
            to_install+=("${PACKAGES[$i]}")
        fi
    done

    printf "\n${BOLD}Installation Summary${NC}\n"
    printf "${DIM}─────────────────────────────────────────${NC}\n"

    if ((${#to_install[@]} == 0)); then
        printf "${YELLOW}No new packages to install.${NC}\n"
        return 1
    fi

    printf "Packages to install (${#to_install[@]}):\n"
    for pkg in "${to_install[@]}"; do
        printf "  ${GREEN}+${NC} %s\n" "$pkg"
    done

    printf "\n"
    read -rp "Install these packages? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy] ]]
}

run_install() {
    local mgr
    mgr=$(detect_package_manager)

    printf "\n${BOLD}Installing packages...${NC}\n"

    for ((i=0; i<${#PACKAGES[@]}; i++)); do
        if ((SELECTED[i] == 1 && INSTALLED[i] == 0)); then
            local pkg="${PACKAGES[$i]}"
            printf "${BLUE}▸${NC} Installing %s..." "$pkg"

            case "$mgr" in
                brew) brew install -q "$pkg" 2>/dev/null && printf " ${GREEN}done${NC}\n" || printf " ${RED}failed${NC}\n" ;;
                apt) sudo apt-get install -y -qq "$pkg" 2>/dev/null && printf " ${GREEN}done${NC}\n" || printf " ${RED}failed${NC}\n" ;;
                dnf) sudo dnf install -y -q "$pkg" 2>/dev/null && printf " ${GREEN}done${NC}\n" || printf " ${RED}failed${NC}\n" ;;
                *) printf " ${YELLOW}skipped (unknown manager)${NC}\n" ;;
            esac
        fi
    done

    printf "\n${GREEN}Installation complete.${NC}\n"
}

main() {
    local profile="${1:-}"

    # Select profile if not provided
    if [[ -z "$profile" ]]; then
        profile=$(select_profile)
        [[ -z "$profile" ]] && exit 0
        clear
    fi

    # Build installed package cache (one-time, fast)
    printf "Checking installed packages...\n"
    build_installed_cache

    # Load packages
    printf "Loading packages from %s...\n" "$profile"
    if ! load_packages "$profile"; then
        printf "${RED}Failed to load profile: %s${NC}\n" "$profile"
        exit 1
    fi

    if ((${#PACKAGES[@]} == 0)); then
        printf "${YELLOW}No packages found in profile.${NC}\n"
        exit 0
    fi

    # Initialize filter (show all packages)
    apply_filter

    # Main UI loop
    printf "${CURSOR_HIDE}"
    trap 'printf "${CURSOR_SHOW}"; exit 0' EXIT INT TERM

    clear
    render_header "$profile"
    render_package_list

    while true; do
        handle_input
        local result=$?

        if ((result == 1)); then
            # Quit
            printf "${CURSOR_SHOW}"
            printf "\n${DIM}Cancelled.${NC}\n"
            exit 0
        elif ((result == 2)); then
            # Confirm
            break
        fi

        clear_package_list
        render_package_list
    done

    printf "${CURSOR_SHOW}"

    # Show summary and install
    if show_summary; then
        run_install
    fi
}

# =============================================================================
# Entry Point
# =============================================================================

main "$@"
