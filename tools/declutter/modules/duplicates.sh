#!/usr/bin/env bash
# ============================================================================
# Duplicate Detection Module
# Integration with czkawka for duplicate file detection
# ============================================================================

set -euo pipefail

_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &

# Czkawka wrapper
CZKAWKA_CMD=""

# Find czkawka installation
find_czkawka() {
    # Check config first
    local config_path
    config_path=$(get_config czkawka_path "")

    if [[ -n "$config_path" && -x "$config_path" ]]; then
        CZKAWKA_CMD="$config_path"
        return 0
    fi

    # Auto-detect
    for cmd in czkawka_cli czkawka; do
        if command -v "$cmd" &>/dev/null; then
            CZKAWKA_CMD="$cmd"
            return 0
        fi
    done

    # Check common installation paths
    local paths=(
        "/usr/local/bin/czkawka_cli"
        "/opt/homebrew/bin/czkawka_cli"
        "$HOME/.cargo/bin/czkawka_cli"
        "$HOME/bin/czkawka_cli"
    )

    for path in "${paths[@]}"; do
        if [[ -x "$path" ]]; then
            CZKAWKA_CMD="$path"
            return 0
        fi
    done

    return 1
}

# Install czkawka if not present
install_czkawka() {
    log_info "Installing czkawka..."

    case "$PLATFORM" in
        macos)
            if command -v brew &>/dev/null; then
                brew install czkawka
            elif command -v cargo &>/dev/null; then
                cargo install czkawka_cli
            else
                log_error "Please install Homebrew or Cargo to install czkawka"
                return 1
            fi
            ;;
        linux)
            if command -v cargo &>/dev/null; then
                cargo install czkawka_cli
            elif command -v apt &>/dev/null; then
                log_info "Installing via cargo (apt package may be outdated)"
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
                source "$HOME/.cargo/env"
                cargo install czkawka_cli
            else
                log_error "Please install Cargo: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
                return 1
            fi
            ;;
        *)
            log_error "Please install czkawka manually: https://github.com/qarmin/czkawka"
            return 1
            ;;
    esac

    find_czkawka
}

# Check czkawka availability
check_czkawka() {
    if ! find_czkawka; then
        log_warn "czkawka not found"
        if confirm_action "Would you like to install czkawka?"; then
            install_czkawka
        else
            return 1
        fi
    fi

    log_info "Using czkawka: $CZKAWKA_CMD"
    return 0
}

# Find duplicate files
find_duplicates() {
    local search_paths=("$@")

    if [[ ${#search_paths[@]} -eq 0 ]]; then
        search_paths=(".")
    fi

    if ! check_czkawka; then
        log_error "Cannot proceed without czkawka"
        return 1
    fi

    local output_file
    output_file=$(mktemp)
    local hash_type
    hash_type=$(get_config hash_type "Blake3")
    local min_size
    min_size=$(get_config duplicate_min_size "1024")

    log_info "Scanning for duplicates in: ${search_paths[*]}"
    start_spinner "Analyzing files..."

    # Run czkawka
    "$CZKAWKA_CMD" dup \
        --directories "${search_paths[@]}" \
        --minimal-file-size "$min_size" \
        --hash-type "$hash_type" \
        --file-to-save "$output_file" \
        2>/dev/null || true

    stop_spinner

    if [[ ! -s "$output_file" ]]; then
        log_info "No duplicates found"
        rm -f "$output_file"
        return 0
    fi

    echo "$output_file"
}

# Parse czkawka output and display interactively
show_duplicates_interactive() {
    local output_file=$1

    if [[ ! -f "$output_file" ]]; then
        log_error "Output file not found"
        return 1
    fi

    print_header "Duplicate Files Found"

    local group_num=0
    local current_group=()
    local total_size=0
    local total_duplicates=0

    while IFS= read -r line; do
        # Skip empty lines and headers
        [[ -z "$line" || "$line" =~ ^-+$ || "$line" =~ ^"Found" ]] && continue

        if [[ "$line" =~ ^[[:space:]]*$ ]]; then
            # End of group
            if [[ ${#current_group[@]} -gt 0 ]]; then
                display_duplicate_group "$group_num" "${current_group[@]}"
                current_group=()
                ((group_num++))
            fi
        else
            # File in current group
            current_group+=("$line")
            ((total_duplicates++))
        fi
    done < "$output_file"

    # Handle last group
    if [[ ${#current_group[@]} -gt 0 ]]; then
        display_duplicate_group "$group_num" "${current_group[@]}"
    fi

    echo ""
    log_info "Found $group_num groups with $total_duplicates duplicate files"

    rm -f "$output_file"
}

# Display a single duplicate group
display_duplicate_group() {
    local group_num=$1
    shift
    local files=("$@")

    if [[ ${#files[@]} -lt 2 ]]; then
        return
    fi

    echo ""
    echo -e "${CYAN}Group $((group_num + 1))${NC} (${#files[@]} files)"
    echo -e "${GRAY}$(printf '─%.0s' {1..50})${NC}"

    local idx=1
    for file in "${files[@]}"; do
        local size
        size=$(get_file_size "$file" 2>/dev/null || echo "0")
        local human
        human=$(human_size "$size")

        if [[ $idx -eq 1 ]]; then
            echo -e "  ${GREEN}[KEEP]${NC} $file ($human)"
        else
            echo -e "  ${RED}[$idx]${NC}   $file ($human)"
        fi
        ((idx++))
    done
}

# Interactive duplicate cleanup
cleanup_duplicates_interactive() {
    local search_paths=("$@")

    local output_file
    output_file=$(find_duplicates "${search_paths[@]}")

    if [[ -z "$output_file" || ! -f "$output_file" ]]; then
        return 0
    fi

    # Create undo session
    local session_id
    session_id=$(create_undo_session "Duplicate cleanup")

    print_header "Interactive Duplicate Cleanup"
    echo "Options:"
    echo "  [Enter] Keep first, delete rest"
    echo "  [number] Keep specific file"
    echo "  [s] Skip this group"
    echo "  [q] Quit"
    echo ""

    local group_num=0
    local current_group=()
    local deleted_count=0
    local saved_bytes=0

    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^-+$ || "$line" =~ ^"Found" ]] && continue

        if [[ "$line" =~ ^[[:space:]]*$ ]]; then
            if [[ ${#current_group[@]} -gt 1 ]]; then
                process_duplicate_group "$session_id" "$group_num" "${current_group[@]}"
                local result=$?
                if [[ $result -eq 255 ]]; then
                    break  # User quit
                fi
                ((group_num++))
            fi
            current_group=()
        else
            current_group+=("$line")
        fi
    done < "$output_file"

    # Process last group
    if [[ ${#current_group[@]} -gt 1 ]]; then
        process_duplicate_group "$session_id" "$group_num" "${current_group[@]}"
    fi

    rm -f "$output_file"

    echo ""
    log_success "Cleanup complete. Session ID: $session_id"
    log_info "Use 'declutter undo $session_id' to restore deleted files"
}

# Process a single duplicate group
process_duplicate_group() {
    local session_id=$1
    local group_num=$2
    shift 2
    local files=("$@")

    display_duplicate_group "$group_num" "${files[@]}"

    echo -n "Action: "
    read -r choice

    case "$choice" in
        q|Q)
            return 255  # Signal to quit
            ;;
        s|S)
            log_info "Skipping group"
            return 0
            ;;
        [0-9]*)
            # Keep specific file
            local keep_idx=$((choice - 1))
            if [[ $keep_idx -ge 0 && $keep_idx -lt ${#files[@]} ]]; then
                for i in "${!files[@]}"; do
                    if [[ $i -ne $keep_idx ]]; then
                        safe_delete "${files[$i]}" "$session_id"
                    fi
                done
            else
                log_warn "Invalid selection, skipping"
            fi
            ;;
        *)
            # Default: keep first, delete rest
            for i in "${!files[@]}"; do
                if [[ $i -gt 0 ]]; then
                    safe_delete "${files[$i]}" "$session_id"
                fi
            done
            ;;
    esac

    return 0
}

# Find near-duplicates (similar names)
find_near_duplicates() {
    local search_path=${1:-.}
    local similarity_threshold=${2:-80}  # percentage

    print_header "Scanning for Near-Duplicates"
    log_info "Searching in: $search_path"

    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$search_path" -type f -print0 2>/dev/null)

    local total=${#files[@]}
    log_info "Analyzing $total files..."

    local near_dupes=()

    for ((i=0; i<total; i++)); do
        show_progress $((i+1)) "$total" "Comparing"

        local name1
        name1=$(basename "${files[$i]}")
        local base1="${name1%.*}"

        for ((j=i+1; j<total; j++)); do
            local name2
            name2=$(basename "${files[$j]}")
            local base2="${name2%.*}"

            # Simple similarity check (common prefix)
            local common_len=0
            local max_len=${#base1}
            [[ ${#base2} -gt $max_len ]] && max_len=${#base2}

            for ((k=0; k<${#base1} && k<${#base2}; k++)); do
                if [[ "${base1:$k:1}" == "${base2:$k:1}" ]]; then
                    ((common_len++))
                else
                    break
                fi
            done

            local similarity=$((common_len * 100 / max_len))

            if [[ $similarity -ge $similarity_threshold ]]; then
                near_dupes+=("${files[$i]}|${files[$j]}|$similarity")
            fi
        done
    done

    echo ""
    echo ""

    if [[ ${#near_dupes[@]} -eq 0 ]]; then
        log_info "No near-duplicates found"
        return 0
    fi

    print_subheader "Near-Duplicate Pairs"

    for pair in "${near_dupes[@]}"; do
        IFS='|' read -r file1 file2 sim <<< "$pair"
        echo -e "  ${CYAN}${sim}% similar:${NC}"
        echo "    - $file1"
        echo "    - $file2"
        echo ""
    done
}

# Export functions
export -f find_czkawka check_czkawka find_duplicates
export -f show_duplicates_interactive cleanup_duplicates_interactive
export -f find_near_duplicates
