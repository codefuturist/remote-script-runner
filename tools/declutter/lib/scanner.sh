#!/usr/bin/env bash
# =============================================================================
# Declutter Tool - File Scanner Module
# Efficient file discovery and metadata collection
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"

# =============================================================================
# SCANNER CONFIGURATION
# =============================================================================

declare -a EXCLUDE_PATTERNS=(
    ".git"
    ".svn"
    ".hg"
    "node_modules"
    "__pycache__"
    ".cache"
    ".npm"
    ".yarn"
)

declare -a INCLUDE_HIDDEN="${INCLUDE_HIDDEN:-false}"

# =============================================================================
# FILE TYPE DETECTION
# =============================================================================

declare -A FILE_CATEGORIES=(
    # Documents
    [pdf]="documents" [doc]="documents" [docx]="documents" [txt]="documents"
    [rtf]="documents" [odt]="documents" [xls]="documents" [xlsx]="documents"
    [ppt]="documents" [pptx]="documents" [csv]="documents" [md]="documents"

    # Images
    [jpg]="images" [jpeg]="images" [png]="images" [gif]="images"
    [bmp]="images" [svg]="images" [webp]="images" [ico]="images"
    [tiff]="images" [raw]="images" [heic]="images" [heif]="images"

    # Videos
    [mp4]="videos" [mkv]="videos" [avi]="videos" [mov]="videos"
    [wmv]="videos" [flv]="videos" [webm]="videos" [m4v]="videos"

    # Audio
    [mp3]="audio" [wav]="audio" [flac]="audio" [aac]="audio"
    [ogg]="audio" [wma]="audio" [m4a]="audio" [opus]="audio"

    # Code
    [js]="code" [ts]="code" [py]="code" [rb]="code" [go]="code"
    [rs]="code" [java]="code" [c]="code" [cpp]="code" [h]="code"
    [cs]="code" [php]="code" [swift]="code" [kt]="code" [sh]="code"
    [bash]="code" [zsh]="code" [fish]="code" [ps1]="code" [psm1]="code"

    # Archives
    [zip]="archives" [tar]="archives" [gz]="archives" [bz2]="archives"
    [xz]="archives" [7z]="archives" [rar]="archives" [iso]="archives"

    # Data
    [json]="data" [xml]="data" [yaml]="data" [yml]="data" [toml]="data"
    [ini]="data" [cfg]="data" [conf]="data" [db]="data" [sqlite]="data"

    # Executables
    [exe]="executables" [msi]="executables" [app]="executables"
    [dmg]="executables" [deb]="executables" [rpm]="executables"
)

get_file_category() {
    local file="$1"
    local ext="${file##*.}"
    ext="${ext,,}"  # lowercase

    echo "${FILE_CATEGORIES[$ext]:-other}"
}

# =============================================================================
# ORPHAN FILE PATTERNS
# =============================================================================

declare -a ORPHAN_PATTERNS=(
    ".DS_Store"
    "Thumbs.db"
    "desktop.ini"
    "._.DS_Store"
    "*.tmp"
    "*.temp"
    "*.bak"
    "*.swp"
    "*.swo"
    "*~"
    ".Spotlight-V100"
    ".Trashes"
    ".fseventsd"
    ".TemporaryItems"
)

is_orphan_file() {
    local file="$1"
    local basename
    basename="$(basename "$file")"

    for pattern in "${ORPHAN_PATTERNS[@]}"; do
        if [[ "$basename" == $pattern ]]; then
            return 0
        fi
    done
    return 1
}

# =============================================================================
# SCANNING FUNCTIONS
# =============================================================================

scan_directory() {
    local dir="$1"
    local max_depth="${2:--1}"
    local output_format="${3:-default}"

    if [[ ! -d "$dir" ]]; then
        log_error "Directory not found: $dir"
        return 1
    fi

    local find_opts=()

    # Add depth limit
    if [[ "$max_depth" -gt 0 ]]; then
        find_opts+=(-maxdepth "$max_depth")
    fi

    # Build exclude patterns
    local exclude_args=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_args="$exclude_args -name '$pattern' -prune -o"
    done

    # Exclude hidden files if configured
    if [[ "$INCLUDE_HIDDEN" != "true" ]]; then
        exclude_args="$exclude_args -name '.*' -prune -o"
    fi

    case "$output_format" in
        json)
            scan_to_json "$dir" "$max_depth"
            ;;
        csv)
            scan_to_csv "$dir" "$max_depth"
            ;;
        *)
            scan_default "$dir" "$max_depth"
            ;;
    esac
}

scan_default() {
    local dir="$1"
    local max_depth="$2"

    local depth_opt=""
    [[ "$max_depth" -gt 0 ]] && depth_opt="-maxdepth $max_depth"

    find "$dir" $depth_opt -type f 2>/dev/null | while read -r file; do
        local excluded=false
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            if [[ "$file" == *"/$pattern/"* ]]; then
                excluded=true
                break
            fi
        done

        [[ "$excluded" == "true" ]] && continue
        [[ "$INCLUDE_HIDDEN" != "true" && "$(basename "$file")" == .* ]] && continue

        echo "$file"
    done
}

scan_to_json() {
    local dir="$1"
    local max_depth="$2"

    echo "["
    local first=true

    scan_default "$dir" "$max_depth" | while read -r file; do
        [[ ! -f "$file" ]] && continue

        local size mtime atime category
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        mtime=$(stat -f%m "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null || echo 0)
        atime=$(stat -f%a "$file" 2>/dev/null || stat -c%X "$file" 2>/dev/null || echo 0)
        category=$(get_file_category "$file")

        [[ "$first" == "true" ]] && first=false || echo ","

        cat <<EOF
  {
    "path": "$file",
    "size": $size,
    "mtime": $mtime,
    "atime": $atime,
    "category": "$category"
  }
EOF
    done

    echo "]"
}

scan_to_csv() {
    local dir="$1"
    local max_depth="$2"

    echo "path,size,mtime,atime,category"

    scan_default "$dir" "$max_depth" | while read -r file; do
        [[ ! -f "$file" ]] && continue

        local size mtime atime category
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        mtime=$(stat -f%m "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null || echo 0)
        atime=$(stat -f%a "$file" 2>/dev/null || stat -c%X "$file" 2>/dev/null || echo 0)
        category=$(get_file_category "$file")

        echo "\"$file\",$size,$mtime,$atime,\"$category\""
    done
}

# =============================================================================
# SPECIALIZED SCANS
# =============================================================================

scan_large_files() {
    local dir="$1"
    local min_size="${2:-100MB}"
    local limit="${3:-50}"

    min_size=$(parse_size "$min_size")

    log_info "Scanning for files larger than $(human_readable_size "$min_size")..."

    find "$dir" -type f -size +"${min_size}c" 2>/dev/null | while read -r file; do
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        echo "$size $file"
    done | sort -rn | head -n "$limit" | while read -r size file; do
        echo "$(human_readable_size "$size")|$file"
    done
}

scan_old_files() {
    local dir="$1"
    local days="${2:-365}"
    local by_access="${3:-true}"

    log_info "Scanning for files not ${by_access:+accessed}${by_access:-modified} in $days days..."

    local time_opt
    if [[ "$by_access" == "true" ]]; then
        time_opt="-atime"
    else
        time_opt="-mtime"
    fi

    find "$dir" -type f $time_opt +"$days" 2>/dev/null | while read -r file; do
        local atime mtime
        atime=$(stat -f%a "$file" 2>/dev/null || stat -c%X "$file" 2>/dev/null || echo 0)
        mtime=$(stat -f%m "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null || echo 0)
        echo "$atime|$mtime|$file"
    done | sort -n
}

scan_empty_dirs() {
    local dir="$1"

    log_info "Scanning for empty directories..."

    find "$dir" -type d -empty 2>/dev/null
}

scan_orphan_files() {
    local dir="$1"

    log_info "Scanning for orphan/system files..."

    for pattern in "${ORPHAN_PATTERNS[@]}"; do
        find "$dir" -name "$pattern" -type f 2>/dev/null
    done
}

scan_by_category() {
    local dir="$1"
    local category="$2"

    log_info "Scanning for $category files..."

    scan_default "$dir" -1 | while read -r file; do
        if [[ "$(get_file_category "$file")" == "$category" ]]; then
            echo "$file"
        fi
    done
}

# =============================================================================
# DIRECTORY SIZE ANALYSIS
# =============================================================================

analyze_directory_sizes() {
    local dir="$1"
    local depth="${2:-1}"

    log_info "Analyzing directory sizes (depth: $depth)..."

    if command -v du &>/dev/null; then
        du -h -d "$depth" "$dir" 2>/dev/null | sort -hr
    else
        # Fallback for systems without du -d
        find "$dir" -maxdepth "$depth" -type d 2>/dev/null | while read -r subdir; do
            local size=0
            while IFS= read -r -d '' file; do
                local fsize
                fsize=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
                size=$((size + fsize))
            done < <(find "$subdir" -maxdepth 1 -type f -print0 2>/dev/null)
            echo "$(human_readable_size "$size")|$subdir"
        done | sort -t'|' -k1 -hr
    fi
}

get_directory_stats() {
    local dir="$1"

    local total_files=0
    local total_size=0
    local total_dirs=0

    while IFS= read -r -d '' item; do
        if [[ -f "$item" ]]; then
            ((total_files++))
            local size
            size=$(stat -f%z "$item" 2>/dev/null || stat -c%s "$item" 2>/dev/null || echo 0)
            total_size=$((total_size + size))
        elif [[ -d "$item" ]]; then
            ((total_dirs++))
        fi
    done < <(find "$dir" -print0 2>/dev/null)

    cat <<EOF
{
  "directory": "$dir",
  "total_files": $total_files,
  "total_directories": $total_dirs,
  "total_size": $total_size,
  "total_size_human": "$(human_readable_size "$total_size")"
}
EOF
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f get_file_category is_orphan_file
export -f scan_directory scan_default scan_to_json scan_to_csv
export -f scan_large_files scan_old_files scan_empty_dirs scan_orphan_files scan_by_category
export -f analyze_directory_sizes get_directory_stats
