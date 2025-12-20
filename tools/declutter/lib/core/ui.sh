#!/usr/bin/env bash
#
# Declutter - UI Components
# Interactive user interface helpers
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_UI_LOADED:-}" ]] && return 0
readonly _DECLUTTER_UI_LOADED=1

# =============================================================================
# Dependencies
# =============================================================================

# Source logger if not already loaded
# Module directory
_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=logger.sh
[[ -z "${_DECLUTTER_LOGGER_LOADED:-}" ]] && source "$_MODULE_DIR/logger.sh"

# =============================================================================
# Interactive Selection
# =============================================================================

# Check if fzf is available
has_fzf() {
    command -v fzf &>/dev/null
}

# Interactive file selection using fzf
# Reads from stdin, outputs selected items to stdout
select_files() {
    local header="${1:-Select files (TAB to multi-select, ENTER to confirm)}"
    local preview_cmd="${2:-ls -lah {}}"

    if ! has_fzf; then
        log_warn "fzf not available, returning all items"
        cat
        return
    fi

    fzf --multi \
        --header="$header" \
        --preview="$preview_cmd" \
        --preview-window=down:3:wrap \
        --bind="ctrl-a:select-all" \
        --bind="ctrl-d:deselect-all" \
        --bind="ctrl-t:toggle-all" \
        --height=80% \
        --layout=reverse \
        --border=rounded \
        --info=inline
}

# Select single item
select_one() {
    local header="${1:-Select an option}"

    if ! has_fzf; then
        head -1
        return
    fi

    fzf --header="$header" \
        --height=40% \
        --layout=reverse \
        --border=rounded
}

# Select from menu options
select_menu() {
    local header="$1"
    shift
    local options=("$@")

    if ! has_fzf; then
        # Fallback to numbered selection
        echo "$header" >&2
        local i=1
        for opt in "${options[@]}"; do
            echo "  $i) $opt" >&2
            ((i++))
        done
        read -rp "Enter number: " choice >&2
        echo "${options[$((choice-1))]}"
        return
    fi

    printf '%s\n' "${options[@]}" | fzf --header="$header" \
        --height=40% \
        --layout=reverse \
        --border=rounded
}

# =============================================================================
# Progress Indicators
# =============================================================================

# Spinner animation
declare -a SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_PID=""

# Start spinner
spinner_start() {
    local message="${1:-Processing...}"

    (
        local i=0
        while true; do
            printf "\r${LOG_CYAN}%s${LOG_RESET} %s" "${SPINNER_FRAMES[$i]}" "$message"
            i=$(( (i + 1) % ${#SPINNER_FRAMES[@]} ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown
}

# Stop spinner
spinner_stop() {
    local success="${1:-true}"

    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=""
    fi

    # Clear line
    printf "\r\033[K"
}

# Progress bar
progress_bar() {
    local current="$1"
    local total="$2"
    local label="${3:-Progress}"
    local width="${4:-40}"

    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    # Build bar
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    # Print
    printf "\r  %s: ${LOG_CYAN}[%s]${LOG_RESET} %3d%% (%d/%d)" \
        "$label" "$bar" "$percent" "$current" "$total"

    if ((current >= total)); then
        echo ""
    fi
}

# =============================================================================
# Tables
# =============================================================================

# Print table header
table_header() {
    local columns=("$@")
    local border=""
    local header=""

    for col in "${columns[@]}"; do
        local width="${col%%:*}"
        local title="${col#*:}"
        border+="$(printf '─%.0s' $(seq 1 $((width + 2))))"
        header+="$(printf " %-${width}s │" "$title")"
    done

    echo -e "${LOG_DIM}┌${border%│}┐${LOG_RESET}"
    echo -e "${LOG_BOLD}│${header%│}│${LOG_RESET}"
    echo -e "${LOG_DIM}├${border//─/─}┤${LOG_RESET}"
}

# Print table row
table_row() {
    local values=("$@")
    local row="│"

    for val in "${values[@]}"; do
        local width="${val%%:*}"
        local value="${val#*:}"
        row+="$(printf " %-${width}s │" "$value")"
    done

    echo "${row%│}│"
}

# Print table footer
table_footer() {
    local columns=("$@")
    local border=""

    for col in "${columns[@]}"; do
        local width="${col%%:*}"
        border+="$(printf '─%.0s' $(seq 1 $((width + 2))))"
    done

    echo -e "${LOG_DIM}└${border%│}┘${LOG_RESET}"
}

# =============================================================================
# Summary Display
# =============================================================================

# Print scan summary
print_scan_summary() {
    local scan_type="$1"
    local count="$2"
    local size="$3"
    local duration="$4"

    echo ""
    echo -e "${LOG_BOLD}Scan Summary${LOG_RESET}"
    print_divider
    print_kv "Type" "$scan_type"
    print_kv "Items found" "$count"
    print_kv "Total size" "$size"
    print_kv "Duration" "$duration"
}

# Print action summary
print_action_summary() {
    local action="$1"
    local success="$2"
    local failed="$3"
    local space_freed="$4"

    echo ""
    echo -e "${LOG_BOLD}Action Summary${LOG_RESET}"
    print_divider
    print_kv "Action" "$action"
    echo -e "  ${LOG_GREEN}✓ Success:${LOG_RESET}     $success"
    if ((failed > 0)); then
        echo -e "  ${LOG_RED}✗ Failed:${LOG_RESET}      $failed"
    fi
    if [[ -n "$space_freed" ]]; then
        print_kv "Space freed" "$space_freed"
    fi
}

# =============================================================================
# File Preview
# =============================================================================

# Preview file info
preview_file() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        echo "File not found: $path"
        return 1
    fi

    echo -e "${LOG_BOLD}$(basename "$path")${LOG_RESET}"
    print_divider

    # Get file info
    local size mtime type
    size="$(get_file_size "$path")"
    mtime="$(stat -f%Sm -t"%Y-%m-%d %H:%M" "$path" 2>/dev/null || stat -c%y "$path" 2>/dev/null | cut -d. -f1)"
    type="$(file -b "$path" 2>/dev/null | head -1)"

    print_kv "Path" "$path"
    print_kv "Size" "$(format_bytes "$size")"
    print_kv "Modified" "$mtime"
    print_kv "Type" "$type"

    # Show preview for text files
    if file "$path" 2>/dev/null | grep -q "text"; then
        echo ""
        echo -e "${LOG_DIM}Preview:${LOG_RESET}"
        head -10 "$path" | sed 's/^/  /'
    fi
}

# =============================================================================
# Tree Display
# =============================================================================

# Print directory tree (simplified)
print_tree() {
    local path="$1"
    local depth="${2:-2}"
    local prefix="${3:-}"

    local items=()
    while IFS= read -r item; do
        items+=("$item")
    done < <(ls -1 "$path" 2>/dev/null | head -20)

    local count="${#items[@]}"
    local i=0

    for item in "${items[@]}"; do
        ((i++))
        local is_last=$((i == count))
        local item_path="$path/$item"
        local connector

        if ((is_last)); then
            connector="└── "
            new_prefix="${prefix}    "
        else
            connector="├── "
            new_prefix="${prefix}│   "
        fi

        if [[ -d "$item_path" ]]; then
            echo -e "${prefix}${connector}${LOG_BLUE}${item}/${LOG_RESET}"
            if ((depth > 1)); then
                print_tree "$item_path" $((depth - 1)) "$new_prefix"
            fi
        else
            local size
            size="$(get_file_size "$item_path")"
            echo -e "${prefix}${connector}${item} ${LOG_DIM}($(format_bytes "$size"))${LOG_RESET}"
        fi
    done
}

# =============================================================================
# Error Display
# =============================================================================

# Display error with context
show_error() {
    local title="$1"
    local message="$2"
    local suggestion="${3:-}"

    echo ""
    echo -e "${LOG_RED}${LOG_BOLD}Error: ${title}${LOG_RESET}"
    echo -e "  ${message}"

    if [[ -n "$suggestion" ]]; then
        echo ""
        echo -e "${LOG_YELLOW}Suggestion:${LOG_RESET} ${suggestion}"
    fi
    echo ""
}

# Display warning box
show_warning() {
    local message="$1"

    echo ""
    echo -e "${LOG_YELLOW}╭─ Warning ────────────────────────────────╮${LOG_RESET}"
    echo -e "${LOG_YELLOW}│${LOG_RESET} $message"
    echo -e "${LOG_YELLOW}╰──────────────────────────────────────────╯${LOG_RESET}"
    echo ""
}

# =============================================================================
# Dry Run Display
# =============================================================================

# Show dry run banner
show_dry_run_banner() {
    echo -e "${LOG_YELLOW}╭─────────────────────────────────────────╮${LOG_RESET}"
    echo -e "${LOG_YELLOW}│${LOG_RESET}  ${LOG_BOLD}DRY RUN MODE${LOG_RESET} - No changes will be made  ${LOG_YELLOW}│${LOG_RESET}"
    echo -e "${LOG_YELLOW}╰─────────────────────────────────────────╯${LOG_RESET}"
    echo ""
}

# Format dry run action
dry_run_action() {
    local action="$1"
    local target="$2"
    local destination="${3:-}"

    echo -e "  ${LOG_DIM}[DRY-RUN]${LOG_RESET} ${LOG_CYAN}${action}${LOG_RESET}: $target"
    if [[ -n "$destination" ]]; then
        echo -e "            → $destination"
    fi
}
