#!/usr/bin/env bash
# ============================================================================
# Directory Analysis Module
# Tree view, size breakdown, and disk usage visualization
# ============================================================================

set -euo pipefail

_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Already sourced by main: &
# Already sourced by main: &
# Already sourced by main: &

# Analyze directory sizes
analyze_directory() {
    local search_path=${1:-.}
    local depth=${2:-2}
    local limit=${3:-20}

    print_header "Directory Size Analysis"
    log_info "Analyzing: $search_path (depth: $depth)"

    local results=()

    start_spinner "Calculating sizes..."

    # Get directory sizes
    while IFS=$'\t' read -r size dir; do
        # Convert to bytes (du returns in 512-byte blocks on some systems)
        local bytes=$((size * 512))
        results+=("$bytes|$dir")
    done < <(du -d "$depth" "$search_path" 2>/dev/null | sort -rn | head -n "$limit")

    stop_spinner

    if [[ ${#results[@]} -eq 0 ]]; then
        log_warn "Could not analyze directory"
        return 1
    fi

    # Get total size (first entry is the root)
    local total_size
    total_size=$(echo "${results[0]}" | cut -d'|' -f1)

    print_subheader "Top $limit directories by size"

    printf "  ${WHITE}%-45s %15s %8s${NC}\n" "DIRECTORY" "SIZE" "%"
    printf "  ${GRAY}%-45s %15s %8s${NC}\n" \
        "$(printf '─%.0s' {1..45})" "$(printf '─%.0s' {1..15})" "$(printf '─%.0s' {1..8})"

    for result in "${results[@]}"; do
        IFS='|' read -r size dir <<< "$result"

        local display_dir="$dir"
        if [[ ${#display_dir} -gt 42 ]]; then
            display_dir="...${display_dir: -39}"
        fi

        local pct=0
        [[ $total_size -gt 0 ]] && pct=$((size * 100 / total_size))

        # Color based on size
        local color=""
        if [[ $pct -gt 50 ]]; then
            color="${RED}"
        elif [[ $pct -gt 25 ]]; then
            color="${YELLOW}"
        elif [[ $pct -gt 10 ]]; then
            color="${CYAN}"
        fi

        printf "  ${color}%-45s %15s %7d%%${NC}\n" \
            "$display_dir" "$(human_size $size)" "$pct"
    done
}

# Visual bar chart of disk usage
show_disk_usage_chart() {
    local search_path=${1:-.}
    local depth=${2:-1}

    print_header "Disk Usage Visualization"

    local results=()
    local max_size=0

    start_spinner "Calculating..."

    while IFS=$'\t' read -r size dir; do
        local bytes=$((size * 512))
        [[ $bytes -gt $max_size ]] && max_size=$bytes
        results+=("$bytes|$dir")
    done < <(du -d "$depth" "$search_path" 2>/dev/null | sort -rn | head -n 15)

    stop_spinner

    local bar_width=40

    for result in "${results[@]:1}"; do  # Skip first (total)
        IFS='|' read -r size dir <<< "$result"

        local name
        name=$(basename "$dir")
        if [[ ${#name} -gt 20 ]]; then
            name="${name:0:17}..."
        fi

        local filled=0
        [[ $max_size -gt 0 ]] && filled=$((size * bar_width / max_size))
        local empty=$((bar_width - filled))

        local bar=""
        local i
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done

        printf "  %-20s ${CYAN}%s${NC} %s\n" "$name" "$bar" "$(human_size $size)"
    done
}

# Tree view with sizes
show_tree_with_sizes() {
    local search_path=${1:-.}
    local depth=${2:-3}

    print_header "Directory Tree"

    # Check if tree command is available
    if command -v tree &>/dev/null; then
        tree -h -L "$depth" --du "$search_path" 2>/dev/null | head -100
    else
        # Fallback to custom implementation
        _custom_tree "$search_path" "" 0 "$depth"
    fi
}

# Custom tree implementation
_custom_tree() {
    local dir=$1
    local prefix=$2
    local current_depth=$3
    local max_depth=$4

    [[ $current_depth -ge $max_depth ]] && return

    local entries=()
    local sizes=()

    while IFS= read -r -d '' entry; do
        entries+=("$entry")
        if [[ -d "$entry" ]]; then
            local size
            size=$(du -s "$entry" 2>/dev/null | cut -f1)
            sizes+=($((size * 512)))
        else
            sizes+=($(get_file_size "$entry"))
        fi
    done < <(find "$dir" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z)

    local count=${#entries[@]}
    local i=0

    for entry in "${entries[@]}"; do
        ((i++))
        local name
        name=$(basename "$entry")
        local size=${sizes[$((i-1))]}
        local human
        human=$(human_size "$size")

        local connector="├──"
        local new_prefix="│   "
        if [[ $i -eq $count ]]; then
            connector="└──"
            new_prefix="    "
        fi

        if [[ -d "$entry" ]]; then
            echo -e "${prefix}${connector} ${CYAN}${name}/${NC} ${GRAY}[${human}]${NC}"
            _custom_tree "$entry" "${prefix}${new_prefix}" $((current_depth + 1)) "$max_depth"
        else
            echo -e "${prefix}${connector} ${name} ${GRAY}[${human}]${NC}"
        fi
    done
}

# Find bloated directories
find_bloated_dirs() {
    local search_path=${1:-.}
    local threshold_mb=${2:-500}

    print_header "Bloated Directory Finder"
    log_info "Threshold: ${threshold_mb}MB"

    local threshold_bytes=$((threshold_mb * 1024 * 1024))
    local results=()

    start_spinner "Scanning directories..."

    while IFS=$'\t' read -r size dir; do
        local bytes=$((size * 512))
        if [[ $bytes -ge $threshold_bytes ]]; then
            # Count files in directory
            local file_count
            file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
            results+=("$bytes|$file_count|$dir")
        fi
    done < <(du -d 3 "$search_path" 2>/dev/null)

    stop_spinner

    if [[ ${#results[@]} -eq 0 ]]; then
        log_info "No directories larger than ${threshold_mb}MB found"
        return 0
    fi

    # Sort by size
    local sorted
    sorted=$(printf '%s\n' "${results[@]}" | sort -t'|' -k1 -rn)

    print_subheader "Bloated Directories (>${threshold_mb}MB)"

    printf "  ${WHITE}%-40s %12s %10s${NC}\n" "DIRECTORY" "SIZE" "FILES"
    printf "  ${GRAY}%-40s %12s %10s${NC}\n" \
        "$(printf '─%.0s' {1..40})" "$(printf '─%.0s' {1..12})" "$(printf '─%.0s' {1..10})"

    while IFS='|' read -r size file_count dir; do
        local display_dir="$dir"
        if [[ ${#display_dir} -gt 37 ]]; then
            display_dir="...${display_dir: -34}"
        fi

        printf "  ${YELLOW}%-40s${NC} %12s %10d\n" \
            "$display_dir" "$(human_size $size)" "$file_count"
    done <<< "$sorted"
}

# Disk space summary
disk_space_summary() {
    print_header "Disk Space Summary"

    echo ""
    df -h 2>/dev/null | head -1
    df -h 2>/dev/null | grep -E '^/|^[A-Z]:' | while read -r line; do
        echo "$line"
    done

    echo ""

    # Home directory breakdown
    if [[ -d "$HOME" ]]; then
        print_subheader "Home Directory Breakdown"

        for dir in "$HOME"/*; do
            [[ -d "$dir" ]] || continue
            local size
            size=$(du -s "$dir" 2>/dev/null | cut -f1)
            size=$((size * 512))
            printf "  %-30s %15s\n" "$(basename "$dir")" "$(human_size $size)"
        done | sort -t$'\t' -k2 -rn | head -10
    fi
}

# Compare two directories
compare_directories() {
    local dir1=$1
    local dir2=$2

    print_header "Directory Comparison"

    if [[ ! -d "$dir1" || ! -d "$dir2" ]]; then
        log_error "Both paths must be directories"
        return 1
    fi

    local size1 size2 count1 count2
    size1=$(du -s "$dir1" 2>/dev/null | cut -f1)
    size2=$(du -s "$dir2" 2>/dev/null | cut -f1)
    size1=$((size1 * 512))
    size2=$((size2 * 512))

    count1=$(find "$dir1" -type f 2>/dev/null | wc -l)
    count2=$(find "$dir2" -type f 2>/dev/null | wc -l)

    printf "  ${WHITE}%-20s %20s %20s${NC}\n" "METRIC" "$(basename "$dir1")" "$(basename "$dir2")"
    printf "  ${GRAY}%-20s %20s %20s${NC}\n" \
        "$(printf '─%.0s' {1..20})" "$(printf '─%.0s' {1..20})" "$(printf '─%.0s' {1..20})"
    printf "  %-20s %20s %20s\n" "Total Size" "$(human_size $size1)" "$(human_size $size2)"
    printf "  %-20s %20d %20d\n" "File Count" "$count1" "$count2"

    # Find unique files
    echo ""
    print_subheader "Unique to $(basename "$dir1")"
    comm -23 <(cd "$dir1" && find . -type f | sort) <(cd "$dir2" && find . -type f | sort) | head -10

    echo ""
    print_subheader "Unique to $(basename "$dir2")"
    comm -13 <(cd "$dir1" && find . -type f | sort) <(cd "$dir2" && find . -type f | sort) | head -10
}

export -f analyze_directory show_disk_usage_chart show_tree_with_sizes
export -f find_bloated_dirs disk_space_summary compare_directories
