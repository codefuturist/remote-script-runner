#!/bin/bash
# lib/interactive.sh - Interactive mode utilities for Remote Script Runner
# Source this file in scripts: . "${0%/*}/../lib/interactive.sh"
#
# Requires: Bash 4.0+ (for associative arrays and read -t)
# Provides: Arrow-key menus, prompts, confirmations, progress indicators

# =============================================================================
# Interactive Mode Detection
# =============================================================================

# Check if interactive mode should be enabled
# Respects RSR_INTERACTIVE and RSR_NO_INTERACTIVE env vars
# Auto-enables if running in a terminal with no piped input
rsr_is_interactive() {
    # Explicitly disabled via flag or env
    [[ "${RSR_NO_INTERACTIVE:-0}" == "1" ]] && return 1
    [[ "${INTERACTIVE:-}" == "false" ]] && return 1
    
    # Explicitly enabled
    [[ "${RSR_INTERACTIVE:-0}" == "1" ]] && return 0
    [[ "${INTERACTIVE:-}" == "true" ]] && return 0
    
    # Auto-detect: terminal + not piped
    [[ -t 0 && -t 1 ]]
}

# Check if we can use fancy terminal features
rsr_has_fancy_terminal() {
    [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]]
}

# =============================================================================
# Color Setup for Interactive Elements
# =============================================================================

# Colors for interactive menus (extends base colors)
if [[ -t 1 ]]; then
    RSR_HIGHLIGHT='\033[7m'      # Reverse video for selection
    RSR_UNDERLINE='\033[4m'      # Underline
    RSR_BLINK='\033[5m'          # Blink (rarely used)
    RSR_GRAY='\033[90m'          # Gray text
    RSR_WHITE='\033[97m'         # White text
    RSR_BG_BLUE='\033[44m'       # Blue background
    RSR_BG_GREEN='\033[42m'      # Green background
    RSR_CURSOR_HIDE='\033[?25l' # Hide cursor
    RSR_CURSOR_SHOW='\033[?25h' # Show cursor
    RSR_CLEAR_LINE='\033[2K'    # Clear entire line
    RSR_MOVE_UP='\033[1A'       # Move cursor up
else
    RSR_HIGHLIGHT=''
    RSR_UNDERLINE=''
    RSR_BLINK=''
    RSR_GRAY=''
    RSR_WHITE=''
    RSR_BG_BLUE=''
    RSR_BG_GREEN=''
    RSR_CURSOR_HIDE=''
    RSR_CURSOR_SHOW=''
    RSR_CLEAR_LINE=''
    RSR_MOVE_UP=''
fi

# Use common.sh colors if available, otherwise define our own
: "${RSR_BLUE:=\033[0;34m}"
: "${RSR_GREEN:=\033[0;32m}"
: "${RSR_YELLOW:=\033[1;33m}"
: "${RSR_RED:=\033[0;31m}"
: "${RSR_CYAN:=\033[0;36m}"
: "${RSR_BOLD:=\033[1m}"
: "${RSR_DIM:=\033[2m}"
: "${RSR_NC:=\033[0m}"

# =============================================================================
# Prompt: Yes/No Confirmation
# =============================================================================

# Prompt user for yes/no confirmation
# Usage: prompt_yes_no "Question?" [default]
# Arguments:
#   $1 - Question to ask
#   $2 - Default value: "y", "n", or "" for no default (optional)
# Returns: 0 for yes, 1 for no
# Example: if prompt_yes_no "Continue?" "y"; then ...
prompt_yes_no() {
    local question="$1"
    local default="${2:-}"
    local prompt_hint response
    
    # Build hint based on default
    case "$default" in
        y|Y|yes|YES) prompt_hint="[Y/n]" ;;
        n|N|no|NO)   prompt_hint="[y/N]" ;;
        *)           prompt_hint="[y/n]" ;;
    esac
    
    # If not interactive, use default or fail
    if ! rsr_is_interactive; then
        case "$default" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO)   return 1 ;;
            *)           return 1 ;;  # Default to no if not interactive
        esac
    fi
    
    while true; do
        printf "${RSR_CYAN}?${RSR_NC} %s %s " "$question" "$prompt_hint"
        read -r response
        
        # Handle empty response (use default)
        if [[ -z "$response" && -n "$default" ]]; then
            case "$default" in
                y|Y|yes|YES) return 0 ;;
                n|N|no|NO)   return 1 ;;
            esac
        fi
        
        # Handle actual response
        case "$response" in
            y|Y|yes|YES) return 0 ;;
            n|N|no|NO)   return 1 ;;
            *) printf "${RSR_YELLOW}  Please answer yes or no${RSR_NC}\n" ;;
        esac
    done
}

# =============================================================================
# Prompt: Text Input
# =============================================================================

# Prompt user for text input with optional validation
# Usage: prompt_input "Prompt" [default] [validator_function]
# Arguments:
#   $1 - Prompt text
#   $2 - Default value (optional)
#   $3 - Validator function name (optional) - should return 0 for valid
# Output: Prints the input to stdout
# Example: name=$(prompt_input "Enter name" "John")
prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local validator="${3:-}"
    local response hint=""
    
    [[ -n "$default" ]] && hint=" ${RSR_DIM}(default: $default)${RSR_NC}"
    
    # If not interactive, use default
    if ! rsr_is_interactive; then
        echo "$default"
        return 0
    fi
    
    while true; do
        printf "${RSR_CYAN}?${RSR_NC} %s%s: " "$prompt" "$hint"
        read -r response
        
        # Use default if empty
        [[ -z "$response" ]] && response="$default"
        
        # Validate if validator provided
        if [[ -n "$validator" ]]; then
            if "$validator" "$response" 2>/dev/null; then
                echo "$response"
                return 0
            else
                printf "${RSR_YELLOW}  Invalid input, please try again${RSR_NC}\n"
            fi
        else
            echo "$response"
            return 0
        fi
    done
}

# Prompt for password (hidden input)
# Usage: password=$(prompt_password "Enter password")
prompt_password() {
    local prompt="$1"
    local response
    
    if ! rsr_is_interactive; then
        echo ""
        return 1
    fi
    
    printf "${RSR_CYAN}?${RSR_NC} %s: " "$prompt"
    read -rs response
    printf "\n"
    echo "$response"
}

# =============================================================================
# Prompt: Single Selection Menu (Arrow Keys)
# =============================================================================

# Display a single-selection menu with arrow-key navigation
# Usage: result=$(prompt_select "Title" "option1" "option2" "option3")
# Arguments:
#   $1 - Menu title/prompt
#   $2+ - Menu options
# Output: Prints the selected option to stdout
# Keys: ↑/↓ or j/k to navigate, Enter to select, q to cancel
prompt_select() {
    local title="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0
    local key
    
    # If not interactive, return first option
    if ! rsr_is_interactive; then
        echo "${options[0]}"
        return 0
    fi
    
    # Trap to restore cursor on exit
    trap 'printf "${RSR_CURSOR_SHOW}"' RETURN
    
    # Hide cursor for cleaner UI
    printf "${RSR_CURSOR_HIDE}"
    
    # Print title
    printf "\n${RSR_BOLD}${RSR_CYAN}?${RSR_NC} ${RSR_BOLD}%s${RSR_NC}\n" "$title"
    printf "${RSR_DIM}  Use ↑↓ arrows to move, Enter to select, q to cancel${RSR_NC}\n\n"
    
    # Draw menu function
    _draw_select_menu() {
        local i
        for ((i = 0; i < num_options; i++)); do
            if [[ $i -eq $selected ]]; then
                printf "  ${RSR_CYAN}❯${RSR_NC} ${RSR_BOLD}%s${RSR_NC}\n" "${options[$i]}"
            else
                printf "    ${RSR_DIM}%s${RSR_NC}\n" "${options[$i]}"
            fi
        done
    }
    
    # Clear menu function (move up and clear lines)
    _clear_select_menu() {
        local i
        for ((i = 0; i < num_options; i++)); do
            printf "${RSR_MOVE_UP}${RSR_CLEAR_LINE}"
        done
    }
    
    # Initial draw
    _draw_select_menu
    
    # Input loop
    while true; do
        # Read single character
        IFS= read -rsn1 key
        
        # Handle arrow keys (escape sequences)
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key
            case "$key" in
                '[A') key="up" ;;    # Up arrow
                '[B') key="down" ;;  # Down arrow
                *)    key="" ;;
            esac
        fi
        
        case "$key" in
            up|k)
                _clear_select_menu
                ((selected > 0)) && ((selected--))
                _draw_select_menu
                ;;
            down|j)
                _clear_select_menu
                ((selected < num_options - 1)) && ((selected++))
                _draw_select_menu
                ;;
            ''|$'\n')  # Enter key
                printf "${RSR_CURSOR_SHOW}"
                echo "${options[$selected]}"
                return 0
                ;;
            q|Q)  # Quit/Cancel
                printf "${RSR_CURSOR_SHOW}"
                return 1
                ;;
        esac
    done
}

# =============================================================================
# Prompt: Multi-Selection Menu (Arrow Keys + Space)
# =============================================================================

# Display a multi-selection menu with checkboxes
# Usage: readarray -t results < <(prompt_multiselect "Title" "opt1" "opt2" "opt3")
# Arguments:
#   $1 - Menu title/prompt
#   $2+ - Menu options
# Output: Prints selected options (one per line) to stdout
# Keys: ↑/↓ to navigate, Space to toggle, a to select all, n to select none, Enter to confirm
prompt_multiselect() {
    local title="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0
    local key
    declare -a checked
    
    # Initialize all as unchecked
    for ((i = 0; i < num_options; i++)); do
        checked[$i]=0
    done
    
    # If not interactive, return empty
    if ! rsr_is_interactive; then
        return 0
    fi
    
    # Trap to restore cursor
    trap 'printf "${RSR_CURSOR_SHOW}"' RETURN
    
    printf "${RSR_CURSOR_HIDE}"
    
    # Print title and instructions
    printf "\n${RSR_BOLD}${RSR_CYAN}?${RSR_NC} ${RSR_BOLD}%s${RSR_NC}\n" "$title"
    printf "${RSR_DIM}  ↑↓ move, Space toggle, a all, n none, Enter confirm${RSR_NC}\n\n"
    
    # Draw menu with checkboxes
    _draw_multiselect_menu() {
        local i
        for ((i = 0; i < num_options; i++)); do
            local checkbox
            if [[ ${checked[$i]} -eq 1 ]]; then
                checkbox="${RSR_GREEN}◉${RSR_NC}"
            else
                checkbox="${RSR_DIM}○${RSR_NC}"
            fi
            
            if [[ $i -eq $selected ]]; then
                printf "  ${RSR_CYAN}❯${RSR_NC} %s ${RSR_BOLD}%s${RSR_NC}\n" "$checkbox" "${options[$i]}"
            else
                printf "    %s ${RSR_DIM}%s${RSR_NC}\n" "$checkbox" "${options[$i]}"
            fi
        done
    }
    
    _clear_multiselect_menu() {
        local i
        for ((i = 0; i < num_options; i++)); do
            printf "${RSR_MOVE_UP}${RSR_CLEAR_LINE}"
        done
    }
    
    _draw_multiselect_menu
    
    while true; do
        IFS= read -rsn1 key
        
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key
            case "$key" in
                '[A') key="up" ;;
                '[B') key="down" ;;
                *)    key="" ;;
            esac
        fi
        
        case "$key" in
            up|k)
                _clear_multiselect_menu
                ((selected > 0)) && ((selected--))
                _draw_multiselect_menu
                ;;
            down|j)
                _clear_multiselect_menu
                ((selected < num_options - 1)) && ((selected++))
                _draw_multiselect_menu
                ;;
            ' ')  # Space - toggle selection
                _clear_multiselect_menu
                if [[ ${checked[$selected]} -eq 1 ]]; then
                    checked[$selected]=0
                else
                    checked[$selected]=1
                fi
                _draw_multiselect_menu
                ;;
            a|A)  # Select all
                _clear_multiselect_menu
                for ((i = 0; i < num_options; i++)); do
                    checked[$i]=1
                done
                _draw_multiselect_menu
                ;;
            n|N)  # Select none
                _clear_multiselect_menu
                for ((i = 0; i < num_options; i++)); do
                    checked[$i]=0
                done
                _draw_multiselect_menu
                ;;
            ''|$'\n')  # Enter - confirm
                printf "${RSR_CURSOR_SHOW}"
                # Output selected items
                for ((i = 0; i < num_options; i++)); do
                    if [[ ${checked[$i]} -eq 1 ]]; then
                        echo "${options[$i]}"
                    fi
                done
                return 0
                ;;
            q|Q)
                printf "${RSR_CURSOR_SHOW}"
                return 1
                ;;
        esac
    done
}

# =============================================================================
# Prompt: Numbered Menu (Fallback for non-fancy terminals)
# =============================================================================

# Simple numbered menu for terminals without arrow key support
# Usage: result=$(prompt_select_numbered "Title" "option1" "option2")
prompt_select_numbered() {
    local title="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local choice
    
    printf "\n${RSR_BOLD}%s${RSR_NC}\n" "$title"
    
    local i
    for ((i = 0; i < num_options; i++)); do
        printf "  ${RSR_CYAN}%d)${RSR_NC} %s\n" "$((i + 1))" "${options[$i]}"
    done
    
    while true; do
        printf "\n${RSR_CYAN}?${RSR_NC} Enter selection (1-%d): " "$num_options"
        read -r choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= num_options)); then
            echo "${options[$((choice - 1))]}"
            return 0
        else
            printf "${RSR_YELLOW}  Invalid selection${RSR_NC}\n"
        fi
    done
}

# =============================================================================
# Progress and Status Indicators
# =============================================================================

# Show a spinner while a command runs
# Usage: with_spinner "Loading..." command arg1 arg2
with_spinner() {
    local message="$1"
    shift
    local cmd=("$@")
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    local pid
    
    if ! rsr_has_fancy_terminal; then
        printf "%s... " "$message"
        "${cmd[@]}"
        local exit_code=$?
        printf "done\n"
        return $exit_code
    fi
    
    printf "${RSR_CURSOR_HIDE}"
    
    # Run command in background
    "${cmd[@]}" &
    pid=$!
    
    # Spin while command runs
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${RSR_CYAN}%s${RSR_NC} %s" "${spin_chars:i++%10:1}" "$message"
        sleep 0.1
    done
    
    # Get exit code
    wait "$pid"
    local exit_code=$?
    
    printf "\r${RSR_CLEAR_LINE}"
    printf "${RSR_CURSOR_SHOW}"
    
    if [[ $exit_code -eq 0 ]]; then
        printf "${RSR_GREEN}✓${RSR_NC} %s\n" "$message"
    else
        printf "${RSR_RED}✗${RSR_NC} %s\n" "$message"
    fi
    
    return $exit_code
}

# Show a progress bar
# Usage: show_progress 50 100 "Downloading..."
show_progress() {
    local current=$1
    local total=$2
    local message="${3:-Progress}"
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r${RSR_CYAN}▸${RSR_NC} %s [" "$message"
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$percent"
    
    [[ $current -eq $total ]] && printf "\n"
}

# =============================================================================
# Confirmation for Destructive Operations
# =============================================================================

# Require explicit confirmation for dangerous operations
# Usage: confirm_destructive "This will delete all data" || exit 1
confirm_destructive() {
    local message="$1"
    local confirm_word="${2:-yes}"
    
    if ! rsr_is_interactive; then
        printf "${RSR_RED}✗${RSR_NC} Cannot perform destructive operation without interactive confirmation\n" >&2
        printf "${RSR_DIM}  Run with -i or --interactive flag, or use --yes to skip confirmation${RSR_NC}\n" >&2
        return 1
    fi
    
    printf "\n${RSR_RED}${RSR_BOLD}⚠ WARNING${RSR_NC}\n"
    printf "${RSR_YELLOW}%s${RSR_NC}\n\n" "$message"
    printf "Type '${RSR_BOLD}%s${RSR_NC}' to confirm: " "$confirm_word"
    
    local response
    read -r response
    
    if [[ "$response" == "$confirm_word" ]]; then
        return 0
    else
        printf "${RSR_DIM}Operation cancelled${RSR_NC}\n"
        return 1
    fi
}

# =============================================================================
# Interactive Header and Summary
# =============================================================================

# Print a stylish header for interactive mode
print_interactive_header() {
    local title="$1"
    local version="${2:-}"
    
    printf "\n"
    printf "${RSR_BOLD}${RSR_CYAN}┌─────────────────────────────────────────────────────────┐${RSR_NC}\n"
    printf "${RSR_BOLD}${RSR_CYAN}│${RSR_NC}  ${RSR_BOLD}%s${RSR_NC}" "$title"
    if [[ -n "$version" ]]; then
        printf " ${RSR_DIM}v%s${RSR_NC}" "$version"
    fi
    # Calculate padding
    local title_len=${#title}
    local ver_len=${#version}
    local total_len=$((title_len + ver_len + 3))
    local padding=$((55 - total_len))
    printf "%${padding}s${RSR_BOLD}${RSR_CYAN}│${RSR_NC}\n"
    printf "${RSR_BOLD}${RSR_CYAN}└─────────────────────────────────────────────────────────┘${RSR_NC}\n"
    printf "\n"
}

# Print a summary box
print_summary_box() {
    local title="$1"
    shift
    local items=("$@")
    
    printf "\n${RSR_BOLD}${RSR_CYAN}── %s ──${RSR_NC}\n" "$title"
    for item in "${items[@]}"; do
        printf "  ${RSR_GREEN}✓${RSR_NC} %s\n" "$item"
    done
    printf "\n"
}

# =============================================================================
# Argument Parsing Helpers
# =============================================================================

# Standard interactive mode argument handling
# Call this in parse_args to handle -i/--interactive and --no-interactive
# Sets INTERACTIVE variable
handle_interactive_args() {
    case "$1" in
        -i|--interactive)
            INTERACTIVE=true
            RSR_INTERACTIVE=1
            return 0
            ;;
        --no-interactive|-y|--yes)
            INTERACTIVE=false
            RSR_NO_INTERACTIVE=1
            return 0
            ;;
    esac
    return 1
}

# Check if we should auto-enable interactive mode
# Call after parse_args with the original argument count
# Usage: maybe_enable_interactive "$#"
maybe_enable_interactive() {
    local arg_count="$1"
    
    # If already explicitly set, don't change
    [[ "${INTERACTIVE:-}" == "true" || "${INTERACTIVE:-}" == "false" ]] && return
    
    # Auto-enable if no arguments given and running interactively
    if [[ $arg_count -eq 0 ]] && rsr_is_interactive; then
        INTERACTIVE=true
        RSR_INTERACTIVE=1
    else
        INTERACTIVE=false
    fi
}

# =============================================================================
# Export for use in subshells
# =============================================================================

export RSR_INTERACTIVE RSR_NO_INTERACTIVE
