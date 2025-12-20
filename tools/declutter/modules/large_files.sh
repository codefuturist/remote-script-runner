#!/usr/bin/env bash
# ============================================================================
# Large File Finder Module
# Find and manage large files
# ============================================================================

set -euo pipefail

_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &

# Find large files
find_large_files() {
    local search_path=${1:-.}
    local threshold_mb=${2:-100}
    local limit=${3:-50}
    local sort_by=${4:-size}  # size, time, name

    local threshold_bytes=$((threshold_mb * 1024 * 1024))

    print_header "Large File Finder"
    log_info "Searching in: $search_path"
    log_info "Threshold: ${threshold_mb}MB"

    local results=()
    local total_size=0
    local count=0

    start_spinner "Scanning files..."

    while IFS= read -r -d '' file; do
        local size
        size=$(get_file_size "$file")

        if [[ $size -ge $threshold_bytes ]]; then
            local mtime
            mtime=$(get_mod_time "$file")
            results+=("$size|$mtime|$file")
            total_size=$((total_size + size))
            ((count++))
        fi
    done < <(find "$search_path" -type f -print0 2>/dev/null)

    stop_spinner

    if [[ ${#results[@]} -eq 0 ]]; then
        log_info "No files larger than ${threshold_mb}MB found"
        return 0
    fi

    # Sort results
    local sorted_results
    case "$sort_by" in
        size)
            sorted_results=$(printf '%s\n' "${results[@]}" | sort -t'|' -k1 -rn | head -n "$limit")
            ;;
        time)
            sorted_results=$(printf '%s\n' "${results[@]}" | sort -t'|' -k2 -rn | head -n "$limit")
            ;;
        name)
            sorted_results=$(printf '%s\n' "${results[@]}" | sort -t'|' -k3 | head -n "$limit")
            ;;
    esac

    print_subheader "Found $count files ($(human_size $total_size) total)"

    printf "  ${WHITE}%-45s %12s %12s${NC}\n" "FILE" "SIZE" "MODIFIED"
    printf "  ${GRAY}%-45s %12s %12s${NC}\n" "$(printf '─%.0s' {1..45})" "$(printf '─%.0s' {1..12})" "$(printf '─%.0s' {1..12})"

    local idx=1
    while IFS='|' read -r size mtime filepath; do
        local human
        human=$(human_size "$size")
        local date_str
        date_str=$(date -r "$mtime" '+%Y-%m-%d' 2>/dev/null || date -d "@$mtime" '+%Y-%m-%d' 2>/dev/null || echo "unknown")
        local filename
        filename=$(basename "$filepath")

        # Truncate long filenames
        if [[ ${#filename} -gt 42 ]]; then
            filename="${filename:0:39}..."
        fi

        printf "  ${CYAN}[%2d]${NC} %-40s %12s %12s\n" "$idx" "$filename" "$human" "$date_str"
        ((idx++))
    done <<< "$sorted_results"

    echo ""
    echo "$sorted_results"  # Return for further processing
}

# Interactive large file cleanup
cleanup_large_files_interactive() {
    local search_path=${1:-.}
    local threshold_mb=${2:-100}

    local results
    results=$(find_large_files "$search_path" "$threshold_mb" 50 "size" 2>/dev/null | tail -n +1)

    if [[ -z "$results" ]]; then
        return 0
    fi

    # Create undo session
    local session_id
    session_id=$(create_undo_session "Large file cleanup")

    echo ""
    echo "Actions:"
    echo "  [number]  Select file"
    echo "  [d]       Delete selected"
    echo "  [m]       Move selected"
    echo "  [c]       Compress selected"
    echo "  [a]       Delete all shown"
    echo "  [q]       Quit"
    echo ""

    local files=()
    while IFS='|' read -r size mtime filepath; do
        files+=("$filepath")
    done <<< "$results"

    while true; do
        echo -n "Select file [1-${#files[@]}] or action: "
        read -r choice

        case "$choice" in
            q|Q)
                break
                ;;
            a|A)
                if confirm_action "Delete ALL ${#files[@]} large files?"; then
                    for file in "${files[@]}"; do
                        safe_delete "$file" "$session_id"
                    done
                    log_success "Deleted all files"
                    break
                fi
                ;;
            [0-9]*)
                local idx=$((choice - 1))
                if [[ $idx -ge 0 && $idx -lt ${#files[@]} ]]; then
                    local selected="${files[$idx]}"
                    echo ""
                    echo "Selected: $selected"
                    echo "  [d] Delete  [m] Move  [c] Compress  [o] Open folder  [b] Back"
                    echo -n "Action: "
                    read -r action

                    case "$action" in
                        d|D)
                            if confirm_action "Delete $selected?"; then
                                safe_delete "$selected" "$session_id"
                            fi
                            ;;
                        m|M)
                            echo -n "Move to: "
                            read -r dest
                            if [[ -n "$dest" ]]; then
                                safe_move "$selected" "$dest" "$session_id"
                            fi
                            ;;
                        c|C)
                            compress_file "$selected" "$session_id"
                            ;;
                        o|O)
                            open_file_manager "$(dirname "$selected")"
                            ;;
                    esac
                fi
                ;;
        esac
    done

    log_info "Session ID: $session_id (use for undo)"
}

# Compress a file
compress_file() {
    local file=$1
    local session_id=${2:-""}

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    local compressed="${file}.gz"

    if is_dry_run; then
        log_info "[DRY RUN] Would compress: $file"
        return 0
    fi

    log_info "Compressing: $file"
    start_spinner "Compressing..."

    if gzip -k "$file"; then
        stop_spinner

        local orig_size
        orig_size=$(get_file_size "$file")
        local new_size
        new_size=$(get_file_size "$compressed")
        local saved=$((orig_size - new_size))

        log_success "Compressed: $(human_size $orig_size) -> $(human_size $new_size) (saved $(human_size $saved))"

        if confirm_action "Delete original file?"; then
            safe_delete "$file" "$session_id"
        fi
    else
        stop_spinner
        log_error "Compression failed"
        return 1
    fi
}

# Find files by size ranges
analyze_file_sizes() {
    local search_path=${1:-.}

    print_header "File Size Analysis"

    local tiny=0 small=0 medium=0 large=0 huge=0
    local tiny_size=0 small_size=0 medium_size=0 large_size=0 huge_size=0

    start_spinner "Analyzing..."

    while IFS= read -r -d '' file; do
        local size
        size=$(get_file_size "$file")

        if [[ $size -lt 1024 ]]; then
            ((tiny++))
            tiny_size=$((tiny_size + size))
        elif [[ $size -lt 1048576 ]]; then
            ((small++))
            small_size=$((small_size + size))
        elif [[ $size -lt 104857600 ]]; then
            ((medium++))
            medium_size=$((medium_size + size))
        elif [[ $size -lt 1073741824 ]]; then
            ((large++))
            large_size=$((large_size + size))
        else
            ((huge++))
            huge_size=$((huge_size + size))
        fi
    done < <(find "$search_path" -type f -print0 2>/dev/null)

    stop_spinner

    echo ""
    printf "  ${WHITE}%-20s %10s %15s${NC}\n" "SIZE RANGE" "COUNT" "TOTAL SIZE"
    printf "  ${GRAY}%-20s %10s %15s${NC}\n" "$(printf '─%.0s' {1..20})" "$(printf '─%.0s' {1..10})" "$(printf '─%.0s' {1..15})"
    printf "  %-20s %10d %15s\n" "< 1 KB (tiny)" "$tiny" "$(human_size $tiny_size)"
    printf "  %-20s %10d %15s\n" "1 KB - 1 MB" "$small" "$(human_size $small_size)"
    printf "  %-20s %10d %15s\n" "1 MB - 100 MB" "$medium" "$(human_size $medium_size)"
    printf "  ${YELLOW}%-20s %10d %15s${NC}\n" "100 MB - 1 GB" "$large" "$(human_size $large_size)"
    printf "  ${RED}%-20s %10d %15s${NC}\n" "> 1 GB (huge)" "$huge" "$(human_size $huge_size)"
    echo ""

    local total=$((tiny + small + medium + large + huge))
    local total_size=$((tiny_size + small_size + medium_size + large_size + huge_size))
    printf "  ${WHITE}%-20s %10d %15s${NC}\n" "TOTAL" "$total" "$(human_size $total_size)"
}

export -f find_large_files cleanup_large_files_interactive
export -f compress_file analyze_file_sizes
