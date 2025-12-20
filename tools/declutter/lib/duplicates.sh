#!/usr/bin/env bash
# =============================================================================
# Declutter Tool - Duplicate Detection Module
# Integration with czkawka and fallback hash-based detection
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"

# =============================================================================
# CZKAWKA INTEGRATION
# =============================================================================

CZKAWKA_CMD=""

init_czkawka() {
    CZKAWKA_CMD=$(check_czkawka)

    if [[ -z "$CZKAWKA_CMD" ]]; then
        log_warn "czkawka not found. Using fallback hash-based detection."
        log_info "Install czkawka for better performance: https://github.com/qarmin/czkawka"
        return 1
    fi

    log_info "Using czkawka for duplicate detection: $CZKAWKA_CMD"
    return 0
}

# =============================================================================
# CZKAWKA DUPLICATE DETECTION
# =============================================================================

find_duplicates_czkawka() {
    local dir="$1"
    local output_file="${2:-}"
    local min_size="${3:-1}"
    local hash_type="${4:-blake3}"

    if [[ -z "$CZKAWKA_CMD" ]]; then
        log_error "czkawka not initialized"
        return 1
    fi

    local temp_output
    temp_output=$(mktemp)

    log_info "Running czkawka duplicate scan on: $dir"

    "$CZKAWKA_CMD" dup \
        -d "$dir" \
        -m "$min_size" \
        -t "$hash_type" \
        -f "$temp_output" \
        --minimal-prehash-cache-file-size 0 \
        2>/dev/null

    if [[ -n "$output_file" ]]; then
        mv "$temp_output" "$output_file"
        echo "$output_file"
    else
        cat "$temp_output"
        rm -f "$temp_output"
    fi
}

find_similar_images_czkawka() {
    local dir="$1"
    local output_file="${2:-}"
    local similarity="${3:-High}"  # Very High, High, Medium, Small, Very Small, Minimal

    if [[ -z "$CZKAWKA_CMD" ]]; then
        log_error "czkawka not initialized"
        return 1
    fi

    local temp_output
    temp_output=$(mktemp)

    log_info "Running czkawka similar images scan on: $dir"

    "$CZKAWKA_CMD" image \
        -d "$dir" \
        -s "$similarity" \
        -f "$temp_output" \
        2>/dev/null

    if [[ -n "$output_file" ]]; then
        mv "$temp_output" "$output_file"
        echo "$output_file"
    else
        cat "$temp_output"
        rm -f "$temp_output"
    fi
}

find_similar_videos_czkawka() {
    local dir="$1"
    local output_file="${2:-}"

    if [[ -z "$CZKAWKA_CMD" ]]; then
        log_error "czkawka not initialized"
        return 1
    fi

    local temp_output
    temp_output=$(mktemp)

    log_info "Running czkawka similar videos scan on: $dir"

    "$CZKAWKA_CMD" video \
        -d "$dir" \
        -f "$temp_output" \
        2>/dev/null

    if [[ -n "$output_file" ]]; then
        mv "$temp_output" "$output_file"
        echo "$output_file"
    else
        cat "$temp_output"
        rm -f "$temp_output"
    fi
}

find_empty_files_czkawka() {
    local dir="$1"

    if [[ -z "$CZKAWKA_CMD" ]]; then
        log_error "czkawka not initialized"
        return 1
    fi

    log_info "Running czkawka empty files scan on: $dir"

    "$CZKAWKA_CMD" empty-files -d "$dir" 2>/dev/null
}

find_empty_dirs_czkawka() {
    local dir="$1"

    if [[ -z "$CZKAWKA_CMD" ]]; then
        log_error "czkawka not initialized"
        return 1
    fi

    log_info "Running czkawka empty directories scan on: $dir"

    "$CZKAWKA_CMD" empty-folders -d "$dir" 2>/dev/null
}

find_temporary_files_czkawka() {
    local dir="$1"

    if [[ -z "$CZKAWKA_CMD" ]]; then
        log_error "czkawka not initialized"
        return 1
    fi

    log_info "Running czkawka temporary files scan on: $dir"

    "$CZKAWKA_CMD" temp -d "$dir" 2>/dev/null
}

find_broken_symlinks_czkawka() {
    local dir="$1"

    if [[ -z "$CZKAWKA_CMD" ]]; then
        log_error "czkawka not initialized"
        return 1
    fi

    log_info "Running czkawka broken symlinks scan on: $dir"

    "$CZKAWKA_CMD" symlinks -d "$dir" 2>/dev/null
}

# =============================================================================
# FALLBACK HASH-BASED DUPLICATE DETECTION
# =============================================================================

find_duplicates_fallback() {
    local dir="$1"
    local min_size="${2:-1}"
    local algorithm="${3:-sha256}"

    log_info "Scanning for duplicates using $algorithm hashing..."

    declare -A hash_map
    declare -A size_map
    declare -a duplicates

    # First pass: group by size (quick filter)
    log_debug "Phase 1: Grouping files by size..."
    while IFS= read -r -d '' file; do
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)

        [[ $size -lt $min_size ]] && continue

        if [[ -n "${size_map[$size]:-}" ]]; then
            size_map[$size]="${size_map[$size]}|$file"
        else
            size_map[$size]="$file"
        fi
    done < <(find "$dir" -type f -print0 2>/dev/null)

    # Second pass: hash only files with matching sizes
    log_debug "Phase 2: Hashing potential duplicates..."
    local total_candidates=0
    local processed=0

    for size in "${!size_map[@]}"; do
        IFS='|' read -ra files <<< "${size_map[$size]}"
        [[ ${#files[@]} -lt 2 ]] && continue
        total_candidates=$((total_candidates + ${#files[@]}))
    done

    for size in "${!size_map[@]}"; do
        IFS='|' read -ra files <<< "${size_map[$size]}"
        [[ ${#files[@]} -lt 2 ]] && continue

        for file in "${files[@]}"; do
            ((processed++))
            show_progress "$processed" "$total_candidates" "Hashing"

            local hash
            hash=$(get_file_hash "$file" "$algorithm")

            if [[ -n "${hash_map[$hash]:-}" ]]; then
                hash_map[$hash]="${hash_map[$hash]}|$file"
            else
                hash_map[$hash]="$file"
            fi
        done
    done

    echo  # newline after progress

    # Output duplicates
    log_info "Duplicate groups found:"
    echo ""

    local group_num=0
    for hash in "${!hash_map[@]}"; do
        IFS='|' read -ra files <<< "${hash_map[$hash]}"
        [[ ${#files[@]} -lt 2 ]] && continue

        ((group_num++))
        local first_file="${files[0]}"
        local size
        size=$(stat -f%z "$first_file" 2>/dev/null || stat -c%s "$first_file" 2>/dev/null || echo 0)

        echo "=== Group $group_num ($(human_readable_size "$size") each, ${#files[@]} files) ==="
        for file in "${files[@]}"; do
            echo "  $file"
        done
        echo ""
    done

    [[ $group_num -eq 0 ]] && log_info "No duplicates found."
}

# =============================================================================
# NEAR-DUPLICATE DETECTION
# =============================================================================

find_similar_names() {
    local dir="$1"
    local threshold="${2:-3}"  # Max Levenshtein distance

    log_info "Scanning for files with similar names..."

    declare -a files
    while IFS= read -r file; do
        files+=("$file")
    done < <(find "$dir" -type f -printf "%f\n" 2>/dev/null | sort -u)

    local total=${#files[@]}
    local compared=0

    echo "Similar file names found:"
    echo ""

    for ((i=0; i<total; i++)); do
        for ((j=i+1; j<total; j++)); do
            local file1="${files[$i]}"
            local file2="${files[$j]}"

            # Quick pre-filter: similar length
            local len1=${#file1}
            local len2=${#file2}
            local len_diff=$((len1 > len2 ? len1 - len2 : len2 - len1))

            [[ $len_diff -gt $threshold ]] && continue

            # Check if names are similar (simple substring check)
            local base1="${file1%.*}"
            local base2="${file2%.*}"

            if [[ "$base1" == *"$base2"* ]] || [[ "$base2" == *"$base1"* ]]; then
                echo "Similar: $file1 <-> $file2"
            fi
        done

        ((compared++))
        if (( compared % 100 == 0 )); then
            show_progress "$compared" "$total" "Comparing"
        fi
    done
}

# =============================================================================
# UNIFIED DUPLICATE FINDER
# =============================================================================

find_duplicates() {
    local dir="$1"
    local method="${2:-auto}"  # auto, czkawka, hash
    local output_file="${3:-}"

    case "$method" in
        auto)
            if init_czkawka 2>/dev/null; then
                find_duplicates_czkawka "$dir" "$output_file"
            else
                find_duplicates_fallback "$dir"
            fi
            ;;
        czkawka)
            init_czkawka || return 1
            find_duplicates_czkawka "$dir" "$output_file"
            ;;
        hash)
            find_duplicates_fallback "$dir"
            ;;
        *)
            log_error "Unknown method: $method"
            return 1
            ;;
    esac
}

# =============================================================================
# INTERACTIVE DUPLICATE REVIEW
# =============================================================================

review_duplicates_interactive() {
    local dup_file="$1"

    if [[ ! -f "$dup_file" ]]; then
        log_error "Duplicate file not found: $dup_file"
        return 1
    fi

    log_info "Interactive duplicate review"
    echo ""

    local current_group=""
    local group_files=()
    local group_num=0

    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" == "#"* ]] && continue

        # Check for group separator
        if [[ "$line" == "---"* || "$line" == "==="* ]]; then
            # Process previous group
            if [[ ${#group_files[@]} -gt 1 ]]; then
                ((group_num++))
                review_duplicate_group "$group_num" "${group_files[@]}"
            fi
            group_files=()
            continue
        fi

        # Add file to current group
        group_files+=("$line")
    done < "$dup_file"

    # Process last group
    if [[ ${#group_files[@]} -gt 1 ]]; then
        ((group_num++))
        review_duplicate_group "$group_num" "${group_files[@]}"
    fi
}

review_duplicate_group() {
    local group_num="$1"
    shift
    local files=("$@")

    echo ""
    echo "${C_BOLD}=== Duplicate Group $group_num ===${C_RESET}"

    local i=1
    for file in "${files[@]}"; do
        local size mtime
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        mtime=$(stat -f%Sm -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || \
                stat -c%y "$file" 2>/dev/null | cut -d. -f1 || echo "unknown")

        echo "  $i) $file"
        echo "     Size: $(human_readable_size "$size"), Modified: $mtime"
        ((i++))
    done

    echo ""
    echo "Options:"
    echo "  k <num>  - Keep only file <num>, delete others"
    echo "  d <nums> - Delete specific files (e.g., d 2 3)"
    echo "  s        - Skip this group"
    echo "  q        - Quit review"
    echo ""

    read -rp "Action: " action args

    case "$action" in
        k|keep)
            local keep_idx="${args:-1}"
            for ((j=0; j<${#files[@]}; j++)); do
                if [[ $((j+1)) -ne $keep_idx ]]; then
                    safe_delete "${files[$j]}" true
                fi
            done
            ;;
        d|delete)
            for idx in $args; do
                if [[ $idx -ge 1 && $idx -le ${#files[@]} ]]; then
                    safe_delete "${files[$((idx-1))]}" true
                fi
            done
            ;;
        s|skip)
            log_info "Skipping group $group_num"
            ;;
        q|quit)
            log_info "Quitting review"
            exit 0
            ;;
        *)
            log_warn "Invalid action, skipping group"
            ;;
    esac
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f init_czkawka
export -f find_duplicates_czkawka find_similar_images_czkawka find_similar_videos_czkawka
export -f find_empty_files_czkawka find_empty_dirs_czkawka
export -f find_temporary_files_czkawka find_broken_symlinks_czkawka
export -f find_duplicates_fallback find_similar_names
export -f find_duplicates review_duplicates_interactive
