#!/usr/bin/env bash
# =============================================================================
# Declutter Tool - Directory Analysis Module
# Disk usage visualization and analysis
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"

# =============================================================================
# DIRECTORY SIZE ANALYSIS
# =============================================================================

analyze_disk_usage() {
    local dir="$1"
    local depth="${2:-1}"
    local sort_by="${3:-size}"  # size, name, count
    local limit="${4:-20}"

    log_info "Analyzing disk usage: $dir (depth: $depth)"

    case "$sort_by" in
        size)
            du -h -d "$depth" "$dir" 2>/dev/null | sort -hr | head -n "$limit"
            ;;
        name)
            du -h -d "$depth" "$dir" 2>/dev/null | sort -k2 | head -n "$limit"
            ;;
        count)
            # Sort by file count
            find "$dir" -maxdepth "$depth" -type d 2>/dev/null | while read -r subdir; do
                local count
                count=$(find "$subdir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
                local size
                size=$(du -sh "$subdir" 2>/dev/null | cut -f1)
                printf "%s\t%s\t%s\n" "$count" "$size" "$subdir"
            done | sort -rn | head -n "$limit"
            ;;
    esac
}

# =============================================================================
# TREE VIEW WITH SIZE
# =============================================================================

tree_with_size() {
    local dir="$1"
    local depth="${2:-3}"
    local min_size="${3:-0}"

    min_size=$(parse_size "$min_size")

    _tree_recursive() {
        local current_dir="$1"
        local current_depth="$2"
        local prefix="$3"

        [[ $current_depth -le 0 ]] && return

        local items=()
        while IFS= read -r item; do
            items+=("$item")
        done < <(find "$current_dir" -maxdepth 1 -mindepth 1 2>/dev/null | sort)

        local total=${#items[@]}
        local i=0

        for item in "${items[@]}"; do
            ((i++))
            local is_last=$([[ $i -eq $total ]] && echo true || echo false)
            local name
            name=$(basename "$item")

            # Skip hidden items
            [[ "$name" == .* ]] && continue

            local size=0
            local size_str=""

            if [[ -d "$item" ]]; then
                size=$(du -sk "$item" 2>/dev/null | cut -f1 || echo 0)
                size=$((size * 1024))
            else
                size=$(stat -f%z "$item" 2>/dev/null || stat -c%s "$item" 2>/dev/null || echo 0)
            fi

            # Skip if below min size
            [[ $size -lt $min_size ]] && continue

            size_str=$(human_readable_size "$size")

            # Print item
            local connector
            if [[ "$is_last" == "true" ]]; then
                connector="└── "
            else
                connector="├── "
            fi

            if [[ -d "$item" ]]; then
                printf "%s%s${C_BLUE}%s/${C_RESET} ${C_GRAY}[%s]${C_RESET}\n" "$prefix" "$connector" "$name" "$size_str"

                # Recurse into directory
                local new_prefix
                if [[ "$is_last" == "true" ]]; then
                    new_prefix="${prefix}    "
                else
                    new_prefix="${prefix}│   "
                fi

                _tree_recursive "$item" $((current_depth - 1)) "$new_prefix"
            else
                printf "%s%s%s ${C_GRAY}[%s]${C_RESET}\n" "$prefix" "$connector" "$name" "$size_str"
            fi
        done
    }

    local total_size
    total_size=$(du -sh "$dir" 2>/dev/null | cut -f1)

    echo "${C_BOLD}$dir${C_RESET} [$total_size]"
    _tree_recursive "$dir" "$depth" ""
}

# =============================================================================
# TOP N ANALYSIS
# =============================================================================

find_top_files() {
    local dir="$1"
    local count="${2:-20}"

    log_info "Finding top $count largest files..."

    echo ""
    printf "%-12s %-60s\n" "SIZE" "FILE"
    echo "$(printf '%0.s-' {1..72})"

    find "$dir" -type f 2>/dev/null | while read -r file; do
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        echo "$size|$file"
    done | sort -t'|' -k1 -rn | head -n "$count" | while IFS='|' read -r size file; do
        printf "%-12s %s\n" "$(human_readable_size "$size")" "$file"
    done
}

find_top_directories() {
    local dir="$1"
    local count="${2:-20}"

    log_info "Finding top $count largest directories..."

    echo ""
    printf "%-12s %-60s\n" "SIZE" "DIRECTORY"
    echo "$(printf '%0.s-' {1..72})"

    du -sk "$dir"/*/ 2>/dev/null | sort -rn | head -n "$count" | while read -r size subdir; do
        printf "%-12s %s\n" "$(human_readable_size $((size * 1024)))" "$subdir"
    done
}

# =============================================================================
# CATEGORY BREAKDOWN
# =============================================================================

analyze_by_category() {
    local dir="$1"

    log_info "Analyzing files by category..."

    declare -A category_size
    declare -A category_count

    while IFS= read -r file; do
        local category
        category=$(get_file_category "$file")

        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)

        category_size[$category]=$((${category_size[$category]:-0} + size))
        category_count[$category]=$((${category_count[$category]:-0} + 1))
    done < <(find "$dir" -type f 2>/dev/null)

    echo ""
    printf "%-15s %-12s %-10s %-40s\n" "CATEGORY" "SIZE" "COUNT" "BAR"
    echo "$(printf '%0.s-' {1..77})"

    # Find max for scaling bar
    local max_size=0
    for cat in "${!category_size[@]}"; do
        [[ ${category_size[$cat]} -gt $max_size ]] && max_size=${category_size[$cat]}
    done

    # Sort by size and display
    for cat in "${!category_size[@]}"; do
        echo "${category_size[$cat]}|$cat|${category_count[$cat]}"
    done | sort -t'|' -k1 -rn | while IFS='|' read -r size cat count; do
        local bar_len=40
        if [[ $max_size -gt 0 ]]; then
            bar_len=$((size * 40 / max_size))
        fi
        [[ $bar_len -lt 1 ]] && bar_len=1

        local bar
        bar=$(printf "%${bar_len}s" | tr ' ' '█')

        printf "%-15s %-12s %-10s ${C_CYAN}%s${C_RESET}\n" "$cat" "$(human_readable_size "$size")" "$count" "$bar"
    done
}

analyze_by_extension() {
    local dir="$1"
    local limit="${2:-20}"

    log_info "Analyzing files by extension..."

    declare -A ext_size
    declare -A ext_count

    while IFS= read -r file; do
        local ext="${file##*.}"
        ext="${ext,,}"
        [[ "$ext" == "$file" ]] && ext="(no ext)"

        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)

        ext_size[$ext]=$((${ext_size[$ext]:-0} + size))
        ext_count[$ext]=$((${ext_count[$ext]:-0} + 1))
    done < <(find "$dir" -type f 2>/dev/null)

    echo ""
    printf "%-12s %-12s %-10s\n" "EXTENSION" "SIZE" "COUNT"
    echo "$(printf '%0.s-' {1..34})"

    for ext in "${!ext_size[@]}"; do
        echo "${ext_size[$ext]}|$ext|${ext_count[$ext]}"
    done | sort -t'|' -k1 -rn | head -n "$limit" | while IFS='|' read -r size ext count; do
        printf "%-12s %-12s %-10s\n" ".$ext" "$(human_readable_size "$size")" "$count"
    done
}

# =============================================================================
# AGE ANALYSIS
# =============================================================================

analyze_by_age() {
    local dir="$1"

    log_info "Analyzing files by age..."

    local now
    now=$(date +%s)

    declare -A age_buckets_size
    declare -A age_buckets_count
    local buckets=("< 1 week" "1-4 weeks" "1-3 months" "3-6 months" "6-12 months" "> 1 year")

    for bucket in "${buckets[@]}"; do
        age_buckets_size["$bucket"]=0
        age_buckets_count["$bucket"]=0
    done

    while IFS= read -r file; do
        local mtime
        mtime=$(stat -f%m "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null || echo 0)

        local age_days=$(( (now - mtime) / 86400 ))

        local bucket
        if [[ $age_days -lt 7 ]]; then
            bucket="< 1 week"
        elif [[ $age_days -lt 28 ]]; then
            bucket="1-4 weeks"
        elif [[ $age_days -lt 90 ]]; then
            bucket="1-3 months"
        elif [[ $age_days -lt 180 ]]; then
            bucket="3-6 months"
        elif [[ $age_days -lt 365 ]]; then
            bucket="6-12 months"
        else
            bucket="> 1 year"
        fi

        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)

        age_buckets_size["$bucket"]=$((${age_buckets_size[$bucket]} + size))
        age_buckets_count["$bucket"]=$((${age_buckets_count[$bucket]} + 1))
    done < <(find "$dir" -type f 2>/dev/null)

    echo ""
    printf "%-15s %-12s %-10s\n" "AGE" "SIZE" "COUNT"
    echo "$(printf '%0.s-' {1..37})"

    for bucket in "${buckets[@]}"; do
        printf "%-15s %-12s %-10s\n" "$bucket" "$(human_readable_size "${age_buckets_size[$bucket]}")" "${age_buckets_count[$bucket]}"
    done
}

# =============================================================================
# BLOAT DETECTION
# =============================================================================

find_bloated_directories() {
    local dir="$1"
    local threshold="${2:-1GB}"
    local limit="${3:-20}"

    threshold=$(parse_size "$threshold")

    log_info "Finding directories larger than $(human_readable_size "$threshold")..."

    echo ""
    printf "%-12s %-60s\n" "SIZE" "DIRECTORY"
    echo "$(printf '%0.s-' {1..72})"

    find "$dir" -type d 2>/dev/null | while read -r subdir; do
        local size
        size=$(du -sk "$subdir" 2>/dev/null | cut -f1 || echo 0)
        size=$((size * 1024))

        if [[ $size -ge $threshold ]]; then
            echo "$size|$subdir"
        fi
    done | sort -t'|' -k1 -rn | head -n "$limit" | while IFS='|' read -r size subdir; do
        printf "%-12s %s\n" "$(human_readable_size "$size")" "$subdir"
    done
}

find_deep_nesting() {
    local dir="$1"
    local max_depth="${2:-10}"

    log_info "Finding deeply nested directories (depth > $max_depth)..."

    echo ""

    find "$dir" -type d 2>/dev/null | while read -r subdir; do
        local depth
        depth=$(echo "$subdir" | tr -cd '/' | wc -c)

        if [[ $depth -gt $max_depth ]]; then
            echo "$depth|$subdir"
        fi
    done | sort -t'|' -k1 -rn | while IFS='|' read -r depth subdir; do
        echo "Depth $depth: $subdir"
    done
}

# =============================================================================
# SUMMARY REPORT
# =============================================================================

generate_summary_report() {
    local dir="$1"
    local output_file="${2:-}"

    log_info "Generating summary report for: $dir"

    local report=""

    report+="═══════════════════════════════════════════════════════════════════════════════\n"
    report+="                         DIRECTORY ANALYSIS REPORT\n"
    report+="═══════════════════════════════════════════════════════════════════════════════\n"
    report+="\n"
    report+="Directory: $dir\n"
    report+="Generated: $(date '+%Y-%m-%d %H:%M:%S')\n"
    report+="\n"

    # Basic stats
    local total_size total_files total_dirs
    total_size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    total_files=$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
    total_dirs=$(find "$dir" -type d 2>/dev/null | wc -l | tr -d ' ')

    report+="───────────────────────────────────────────────────────────────────────────────\n"
    report+="OVERVIEW\n"
    report+="───────────────────────────────────────────────────────────────────────────────\n"
    report+="Total Size:        $total_size\n"
    report+="Total Files:       $total_files\n"
    report+="Total Directories: $total_dirs\n"
    report+="\n"

    # Top 10 largest files
    report+="───────────────────────────────────────────────────────────────────────────────\n"
    report+="TOP 10 LARGEST FILES\n"
    report+="───────────────────────────────────────────────────────────────────────────────\n"
    report+=$(find "$dir" -type f 2>/dev/null | while read -r file; do
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        echo "$size|$file"
    done | sort -t'|' -k1 -rn | head -10 | while IFS='|' read -r size file; do
        printf "%-12s %s\n" "$(human_readable_size "$size")" "$file"
    done)
    report+="\n\n"

    # Top 10 largest directories
    report+="───────────────────────────────────────────────────────────────────────────────\n"
    report+="TOP 10 LARGEST DIRECTORIES\n"
    report+="───────────────────────────────────────────────────────────────────────────────\n"
    report+=$(du -sk "$dir"/*/ 2>/dev/null | sort -rn | head -10 | while read -r size subdir; do
        printf "%-12s %s\n" "$(human_readable_size $((size * 1024)))" "$subdir"
    done)
    report+="\n\n"

    report+="═══════════════════════════════════════════════════════════════════════════════\n"

    if [[ -n "$output_file" ]]; then
        echo -e "$report" > "$output_file"
        log_info "Report saved to: $output_file"
    else
        echo -e "$report"
    fi
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f analyze_disk_usage tree_with_size
export -f find_top_files find_top_directories
export -f analyze_by_category analyze_by_extension analyze_by_age
export -f find_bloated_directories find_deep_nesting
export -f generate_summary_report
