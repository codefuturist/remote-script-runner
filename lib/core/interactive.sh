#!/bin/bash
# lib/core/interactive.sh - RSR Interactive Mode Utilities
# Bash 4.0+ required for advanced features
#
# Usage: . "${RSR_LIB_DIR:-./lib}/core/interactive.sh"
#
# Provides:
#   - Yes/No prompts
#   - Text input with validation
#   - Password input (hidden)
#   - Single-select menu (arrow keys)
#   - Multi-select menu (checkbox style)
#   - Progress indicators
#   - Spinners

# =============================================================================
# Guard: Prevent double-sourcing
# =============================================================================

[[ -n "${_RSR_CORE_INTERACTIVE_LOADED:-}" ]] && return 0
_RSR_CORE_INTERACTIVE_LOADED=1

# Ensure core init is loaded
if [[ -z "${_RSR_CORE_INIT_LOADED:-}" ]]; then
    _script_source="${BASH_SOURCE[0]:-${0:-}}"
    if [[ -n "${_script_source}" && "${_script_source}" != "bash" && "${_script_source}" != "-bash" ]]; then
        _script_dir="$(cd "$(dirname "${_script_source}")" 2>/dev/null && pwd)" || _script_dir="./lib/core"
    else
        _script_dir="./lib/core"
    fi
    source "${_script_dir}/init.sh" 2>/dev/null || source "./lib/core/init.sh" 2>/dev/null || {
        echo "ERROR: RSR core/init.sh must be sourced first" >&2
        return 1
    }
fi

# =============================================================================
# Terminal Control Sequences
# =============================================================================

if [[ -t 1 ]]; then
    RSR_CURSOR_HIDE='\033[?25l'
    RSR_CURSOR_SHOW='\033[?25h'
    RSR_CURSOR_UP='\033[1A'
    RSR_CURSOR_DOWN='\033[1B'
    RSR_CLEAR_LINE='\033[2K'
    RSR_CLEAR_TO_END='\033[K'
    RSR_HIGHLIGHT='\033[7m'
    RSR_HIGHLIGHT_OFF='\033[27m'
else
    RSR_CURSOR_HIDE=''
    RSR_CURSOR_SHOW=''
    RSR_CURSOR_UP=''
    RSR_CURSOR_DOWN=''
    RSR_CLEAR_LINE=''
    RSR_CLEAR_TO_END=''
    RSR_HIGHLIGHT=''
    RSR_HIGHLIGHT_OFF=''
fi

# =============================================================================
# Interactive Mode Detection
# =============================================================================

# Check if interactive mode should be used
# Usage: if rsr_should_interact; then ...
rsr_should_interact() {
    # Explicitly disabled
    [[ "${RSR_NO_INTERACTIVE:-0}" == "1" ]] && return 1
    [[ "${INTERACTIVE:-}" == "false" ]] && return 1

    # Explicitly enabled
    [[ "${RSR_INTERACTIVE:-0}" == "1" ]] && return 0
    [[ "${INTERACTIVE:-}" == "true" ]] && return 0

    # Auto-detect: both stdin and stdout are terminals
    [[ -t 0 && -t 1 ]]
}

# Check if terminal supports fancy features
# Usage: if rsr_has_fancy_terminal; then ...
rsr_has_fancy_terminal() {
    [[ -t 1 && "${TERM:-dumb}" != "dumb" ]]
}

# =============================================================================
# Yes/No Prompt
# =============================================================================

# Prompt for yes/no confirmation
# Usage: if rsr_prompt_confirm "Continue?" "y"; then ...
# Arguments:
#   $1 - Question text
#   $2 - Default: "y", "n", or "" for no default
# Returns: 0 for yes, 1 for no
rsr_prompt_confirm() {
    local question="$1"
    local default="${2:-}"
    local hint response

    case "$default" in
        y|Y|yes) hint="[Y/n]" ;;
        n|N|no)  hint="[y/N]" ;;
        *)       hint="[y/n]" ;;
    esac

    # Non-interactive mode: use default
    if ! rsr_should_interact; then
        case "$default" in
            y|Y|yes) return 0 ;;
            n|N|no)  return 1 ;;
            *)       return 1 ;;
        esac
    fi

    while true; do
        printf "${RSR_COLOR_CYAN}?${RSR_COLOR_RESET} %s %s " "$question" "$hint"
        read -r response

        # Empty response: use default
        if [[ -z "$response" && -n "$default" ]]; then
            case "$default" in
                y|Y|yes) return 0 ;;
                n|N|no)  return 1 ;;
            esac
        fi

        case "$response" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO)   return 1 ;;
            *) printf "${RSR_COLOR_YELLOW}  Please answer yes or no${RSR_COLOR_RESET}\n" ;;
        esac
    done
}

# =============================================================================
# Text Input Prompt
# =============================================================================

# Prompt for text input
# Usage: name=$(rsr_prompt_input "Enter name" "default_value" "validator_func")
# Arguments:
#   $1 - Prompt text
#   $2 - Default value (optional)
#   $3 - Validator function name (optional) - should return 0 for valid
# Output: Prints the input to stdout
rsr_prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local validator="${3:-}"
    local response hint=""

    [[ -n "$default" ]] && hint=" ${RSR_COLOR_DIM}(default: $default)${RSR_COLOR_RESET}"

    # Non-interactive: return default
    if ! rsr_should_interact; then
        echo "$default"
        return 0
    fi

    while true; do
        printf "${RSR_COLOR_CYAN}?${RSR_COLOR_RESET} %s%b: " "$prompt" "$hint"
        read -r response

        # Use default if empty
        [[ -z "$response" ]] && response="$default"

        # Validate if validator provided
        if [[ -n "$validator" ]]; then
            if "$validator" "$response" 2>/dev/null; then
                echo "$response"
                return 0
            else
                printf "${RSR_COLOR_YELLOW}  Invalid input, please try again${RSR_COLOR_RESET}\n"
            fi
        else
            echo "$response"
            return 0
        fi
    done
}

# Prompt for password (hidden input)
# Usage: password=$(rsr_prompt_password "Enter password")
rsr_prompt_password() {
    local prompt="$1"
    local response

    if ! rsr_should_interact; then
        echo ""
        return 1
    fi

    printf "${RSR_COLOR_CYAN}?${RSR_COLOR_RESET} %s: " "$prompt"
    read -rs response
    printf "\n"
    echo "$response"
}

# Prompt for password with confirmation
# Usage: password=$(rsr_prompt_password_confirm "Enter password")
rsr_prompt_password_confirm() {
    local prompt="$1"
    local pass1 pass2

    if ! rsr_should_interact; then
        echo ""
        return 1
    fi

    while true; do
        printf "${RSR_COLOR_CYAN}?${RSR_COLOR_RESET} %s: " "$prompt"
        read -rs pass1
        printf "\n"

        printf "${RSR_COLOR_CYAN}?${RSR_COLOR_RESET} Confirm %s: " "$prompt"
        read -rs pass2
        printf "\n"

        if [[ "$pass1" == "$pass2" ]]; then
            echo "$pass1"
            return 0
        else
            printf "${RSR_COLOR_YELLOW}  Passwords do not match, please try again${RSR_COLOR_RESET}\n"
        fi
    done
}

# =============================================================================
# Single Selection Menu
# =============================================================================

# Display single-select menu with arrow key navigation
# Usage: result=$(rsr_prompt_select "Choose option" "opt1" "opt2" "opt3")
# Arguments:
#   $1 - Menu title/prompt
#   $2+ - Menu options
# Output: Prints selected option to stdout
rsr_prompt_select() {
    local title="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0
    local key

    # Non-interactive: return first option
    if ! rsr_should_interact || [[ $num_options -eq 0 ]]; then
        echo "${options[0]:-}"
        return 0
    fi

    # Hide cursor
    printf "${RSR_CURSOR_HIDE}"

    # Cleanup on exit
    trap 'printf "${RSR_CURSOR_SHOW}"' EXIT

    # Print title
    printf "${RSR_COLOR_CYAN}?${RSR_COLOR_RESET} %s ${RSR_COLOR_DIM}(↑/↓ to navigate, Enter to select)${RSR_COLOR_RESET}\n" "$title"

    # Render menu function
    _render_menu() {
        local i
        for ((i=0; i<num_options; i++)); do
            printf "\r${RSR_CLEAR_LINE}"
            if [[ $i -eq $selected ]]; then
                printf "  ${RSR_COLOR_CYAN}❯${RSR_COLOR_RESET} ${RSR_HIGHLIGHT}%s${RSR_HIGHLIGHT_OFF}\n" "${options[$i]}"
            else
                printf "    %s\n" "${options[$i]}"
            fi
        done
    }

    # Initial render
    _render_menu

    # Input loop
    while true; do
        # Read single character
        read -rsn1 key

        case "$key" in
            $'\x1b')  # Escape sequence
                read -rsn2 key
                case "$key" in
                    '[A')  # Up arrow
                        ((selected > 0)) && ((selected--))
                        ;;
                    '[B')  # Down arrow
                        ((selected < num_options - 1)) && ((selected++))
                        ;;
                esac
                ;;
            'k')  # Vim up
                ((selected > 0)) && ((selected--))
                ;;
            'j')  # Vim down
                ((selected < num_options - 1)) && ((selected++))
                ;;
            '')  # Enter
                break
                ;;
            'q')  # Quit
                printf "${RSR_CURSOR_SHOW}"
                return 1
                ;;
        esac

        # Move cursor up to redraw
        for ((i=0; i<num_options; i++)); do
            printf "${RSR_CURSOR_UP}"
        done

        _render_menu
    done

    # Show cursor
    printf "${RSR_CURSOR_SHOW}"
    trap - EXIT

    echo "${options[$selected]}"
}

# =============================================================================
# Multi-Selection Menu
# =============================================================================

# Display multi-select menu with checkboxes
# Usage: readarray -t selected < <(rsr_prompt_multiselect "Choose options" "opt1" "opt2" "opt3")
# Arguments:
#   $1 - Menu title/prompt
#   $2+ - Menu options
# Output: Prints selected options (one per line) to stdout
rsr_prompt_multiselect() {
    local title="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0
    local -a checked=()
    local key i

    # Initialize all unchecked
    for ((i=0; i<num_options; i++)); do
        checked[$i]=0
    done

    # Non-interactive: return nothing
    if ! rsr_should_interact || [[ $num_options -eq 0 ]]; then
        return 0
    fi

    printf "${RSR_CURSOR_HIDE}"
    trap 'printf "${RSR_CURSOR_SHOW}"' EXIT

    printf "${RSR_COLOR_CYAN}?${RSR_COLOR_RESET} %s ${RSR_COLOR_DIM}(↑/↓ navigate, Space toggle, Enter confirm)${RSR_COLOR_RESET}\n" "$title"

    _render_multiselect() {
        for ((i=0; i<num_options; i++)); do
            printf "\r${RSR_CLEAR_LINE}"
            local checkbox="[ ]"
            [[ ${checked[$i]} -eq 1 ]] && checkbox="[${RSR_COLOR_GREEN}✓${RSR_COLOR_RESET}]"

            if [[ $i -eq $selected ]]; then
                printf "  ${RSR_COLOR_CYAN}❯${RSR_COLOR_RESET} %s %s\n" "$checkbox" "${options[$i]}"
            else
                printf "    %s %s\n" "$checkbox" "${options[$i]}"
            fi
        done
    }

    _render_multiselect

    while true; do
        read -rsn1 key

        case "$key" in
            $'\x1b')
                read -rsn2 key
                case "$key" in
                    '[A') ((selected > 0)) && ((selected--)) ;;
                    '[B') ((selected < num_options - 1)) && ((selected++)) ;;
                esac
                ;;
            'k') ((selected > 0)) && ((selected--)) ;;
            'j') ((selected < num_options - 1)) && ((selected++)) ;;
            ' ')  # Space to toggle
                if [[ ${checked[$selected]} -eq 0 ]]; then
                    checked[$selected]=1
                else
                    checked[$selected]=0
                fi
                ;;
            '')  # Enter
                break
                ;;
            'q')
                printf "${RSR_CURSOR_SHOW}"
                return 1
                ;;
        esac

        for ((i=0; i<num_options; i++)); do
            printf "${RSR_CURSOR_UP}"
        done

        _render_multiselect
    done

    printf "${RSR_CURSOR_SHOW}"
    trap - EXIT

    # Output selected items
    for ((i=0; i<num_options; i++)); do
        [[ ${checked[$i]} -eq 1 ]] && echo "${options[$i]}"
    done
}

# =============================================================================
# Progress Indicators
# =============================================================================

# Show spinner while command runs
# Usage: rsr_spinner "Loading..." command arg1 arg2
rsr_spinner() {
    local message="$1"
    shift
    local -a spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local pid

    # Run command in background
    "$@" &
    pid=$!

    # Non-interactive: just wait
    if ! rsr_should_interact; then
        wait $pid
        return $?
    fi

    printf "${RSR_CURSOR_HIDE}"

    while kill -0 $pid 2>/dev/null; do
        printf "\r${RSR_COLOR_CYAN}%s${RSR_COLOR_RESET} %s" "${spinner[$i]}" "$message"
        i=$(( (i + 1) % ${#spinner[@]} ))
        sleep 0.1
    done

    wait $pid
    local exit_code=$?

    printf "\r${RSR_CLEAR_LINE}"
    printf "${RSR_CURSOR_SHOW}"

    if [[ $exit_code -eq 0 ]]; then
        printf "${RSR_COLOR_GREEN}✓${RSR_COLOR_RESET} %s\n" "$message"
    else
        printf "${RSR_COLOR_RED}✗${RSR_COLOR_RESET} %s\n" "$message"
    fi

    return $exit_code
}

# Show progress bar
# Usage: rsr_progress_bar 50 100 "Downloading"
rsr_progress_bar() {
    local current="$1"
    local total="$2"
    local message="${3:-Progress}"
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r${RSR_CLEAR_LINE}${RSR_COLOR_CYAN}%s${RSR_COLOR_RESET} [" "$message"
    printf '%*s' "$filled" | tr ' ' '█'
    printf '%*s' "$empty" | tr ' ' '░'
    printf "] %3d%%" "$percent"

    [[ $current -eq $total ]] && printf "\n"
}

# =============================================================================
# Interactive Header
# =============================================================================

# Print a stylish header for interactive mode
# Usage: print_interactive_header "Script Name" "1.0.0"
print_interactive_header() {
    local title="$1"
    local version="${2:-}"
    
    printf "\n"
    printf "${RSR_COLOR_CYAN}${RSR_BOLD}┌─────────────────────────────────────────────────────────┐${RSR_COLOR_RESET}\n"
    printf "${RSR_COLOR_CYAN}${RSR_BOLD}│${RSR_COLOR_RESET}  ${RSR_BOLD}%s${RSR_COLOR_RESET}" "$title"
    if [[ -n "$version" ]]; then
        printf " ${RSR_COLOR_DIM}v%s${RSR_COLOR_RESET}" "$version"
    fi
    # Calculate padding
    local title_len=${#title}
    local ver_len=${#version}
    local total_len=$((title_len + ver_len + 3))
    local padding=$((55 - total_len))
    printf "%${padding}s${RSR_COLOR_CYAN}${RSR_BOLD}│${RSR_COLOR_RESET}\n"
    printf "${RSR_COLOR_CYAN}${RSR_BOLD}└─────────────────────────────────────────────────────────┘${RSR_COLOR_RESET}\n"
    printf "\n"
}

# =============================================================================
# Initialization Complete
# =============================================================================

rsr_log_debug "RSR Interactive Library loaded"

