#!/usr/bin/env bash
#
# Declutter - Core Utilities
# Common utility functions used across all modules
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_UTILS_LOADED:-}" ]] && return 0
readonly _DECLUTTER_UTILS_LOADED=1

# =============================================================================
# Path Utilities
# =============================================================================

# Get absolute path
get_absolute_path() {
    local path="$1"
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    elif [[ -f "$path" ]]; then
        local dir
        dir="$(dirname "$path")"
        echo "$(cd "$dir" && pwd)/$(basename "$path")"
    else
        echo "$path"
    fi
}

# Check if path is safe to operate on
is_safe_path() {
    local path="$1"
    local abs_path
    abs_path="$(get_absolute_path "$path")"

    # Dangerous paths that should never be modified
    local dangerous_paths=(
        "/"
        "/bin"
        "/sbin"
        "/usr"
        "/etc"
        "/var"
        "/System"
        "/Library"
        "/Applications"
        "/private"
        "$HOME/.ssh"
        "$HOME/.gnupg"
    )

    for dangerous in "${dangerous_paths[@]}"; do
        if [[ "$abs_path" == "$dangerous" ]] || [[ "$abs_path" == "$dangerous/"* && "$abs_path" == "$dangerous" ]]; then
            return 1
        fi
    done

    return 0
}

# Check if path exists and is accessible
path_exists() {
    local path="$1"
    [[ -e "$path" ]] || [[ -L "$path" ]]
}

# Get file extension
get_extension() {
    local filename="$1"
    local ext="${filename##*.}"
    [[ "$ext" != "$filename" ]] && echo "$ext" || echo ""
}

# Get filename without extension
get_basename_no_ext() {
    local filename="$1"
    local base
    base="$(basename "$filename")"
    echo "${base%.*}"
}

# =============================================================================
# Size Utilities
# =============================================================================

# Convert bytes to human readable
format_bytes() {
    local bytes="$1"
    if ((bytes >= 1099511627776)); then
        printf "%.2f TB" "$(echo "scale=2; $bytes / 1099511627776" | bc)"
    elif ((bytes >= 1073741824)); then
        printf "%.2f GB" "$(echo "scale=2; $bytes / 1073741824" | bc)"
    elif ((bytes >= 1048576)); then
        printf "%.2f MB" "$(echo "scale=2; $bytes / 1048576" | bc)"
    elif ((bytes >= 1024)); then
        printf "%.2f KB" "$(echo "scale=2; $bytes / 1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

# Parse human-readable size to bytes
parse_size() {
    local size="$1"
    local number unit

    # Extract number and unit
    number="${size//[^0-9.]/}"
    unit="${size//[0-9.]/}"
    unit="${unit^^}"  # Uppercase

    case "$unit" in
        TB|T) echo "$(echo "$number * 1099511627776" | bc | cut -d. -f1)" ;;
        GB|G) echo "$(echo "$number * 1073741824" | bc | cut -d. -f1)" ;;
        MB|M) echo "$(echo "$number * 1048576" | bc | cut -d. -f1)" ;;
        KB|K) echo "$(echo "$number * 1024" | bc | cut -d. -f1)" ;;
        B|"") echo "${number%.*}" ;;
        *) echo "0" ;;
    esac
}

# Get file size in bytes
get_file_size() {
    local path="$1"
    if [[ -f "$path" ]]; then
        stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null || echo "0"
    elif [[ -d "$path" ]]; then
        du -sk "$path" 2>/dev/null | cut -f1 | awk '{print $1 * 1024}'
    else
        echo "0"
    fi
}

# =============================================================================
# Time Utilities
# =============================================================================

# Get current timestamp in ISO format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get file modification time
get_mtime() {
    local path="$1"
    stat -f%m "$path" 2>/dev/null || stat -c%Y "$path" 2>/dev/null || echo "0"
}

# Get file access time
get_atime() {
    local path="$1"
    stat -f%a "$path" 2>/dev/null || stat -c%X "$path" 2>/dev/null || echo "0"
}

# Calculate days since epoch timestamp
days_since() {
    local timestamp="$1"
    local now
    now="$(date +%s)"
    echo $(( (now - timestamp) / 86400 ))
}

# Parse relative time to days
parse_relative_time() {
    local time_str="$1"
    local number unit

    number="${time_str//[^0-9]/}"
    unit="${time_str//[0-9 ]/}"
    unit="${unit,,}"  # Lowercase

    case "$unit" in
        day|days|d) echo "$number" ;;
        week|weeks|w) echo "$((number * 7))" ;;
        month|months|m) echo "$((number * 30))" ;;
        year|years|y) echo "$((number * 365))" ;;
        *) echo "$number" ;;
    esac
}

# =============================================================================
# String Utilities
# =============================================================================

# Trim whitespace
trim() {
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    echo "$str"
}

# Generate UUID v4
generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        # Fallback using /dev/urandom
        od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}'
    fi
}

# Escape string for JSON
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

# =============================================================================
# Array Utilities
# =============================================================================

# Check if array contains element
array_contains() {
    local needle="$1"
    shift
    local element
    for element in "$@"; do
        [[ "$element" == "$needle" ]] && return 0
    done
    return 1
}

# Join array with delimiter
array_join() {
    local delimiter="$1"
    shift
    local first=true
    local result=""
    for element in "$@"; do
        if [[ "$first" == "true" ]]; then
            result="$element"
            first=false
        else
            result="${result}${delimiter}${element}"
        fi
    done
    echo "$result"
}

# =============================================================================
# Hash Utilities
# =============================================================================

# Get file hash (uses fastest available)
get_file_hash() {
    local path="$1"
    local algorithm="${2:-xxhash}"

    case "$algorithm" in
        xxhash|xxh)
            if command -v xxhsum &>/dev/null; then
                xxhsum "$path" 2>/dev/null | cut -d' ' -f1
            elif command -v xxh128sum &>/dev/null; then
                xxh128sum "$path" 2>/dev/null | cut -d' ' -f1
            else
                # Fallback to md5
                get_file_hash "$path" "md5"
            fi
            ;;
        md5)
            if command -v md5sum &>/dev/null; then
                md5sum "$path" 2>/dev/null | cut -d' ' -f1
            else
                md5 -q "$path" 2>/dev/null
            fi
            ;;
        sha256)
            if command -v sha256sum &>/dev/null; then
                sha256sum "$path" 2>/dev/null | cut -d' ' -f1
            else
                shasum -a 256 "$path" 2>/dev/null | cut -d' ' -f1
            fi
            ;;
        *)
            get_file_hash "$path" "md5"
            ;;
    esac
}

# Get partial file hash (first N bytes)
get_partial_hash() {
    local path="$1"
    local bytes="${2:-4096}"

    head -c "$bytes" "$path" 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1 || \
    head -c "$bytes" "$path" 2>/dev/null | md5 -q 2>/dev/null
}

# =============================================================================
# Validation Utilities
# =============================================================================

# Validate that required commands exist
require_commands() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if ((${#missing[@]} > 0)); then
        echo "Missing required commands: ${missing[*]}" >&2
        return 1
    fi
    return 0
}

# Check if running on macOS
is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

# Check if running on Linux
is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}

# =============================================================================
# File Type Detection
# =============================================================================

# Detect file category by extension
get_file_category() {
    local path="$1"
    local ext
    ext="$(get_extension "$path")"
    ext="${ext,,}"  # Lowercase

    case "$ext" in
        # Documents
        pdf|doc|docx|txt|md|rtf|odt|pages|tex|epub)
            echo "documents"
            ;;
        # Images
        jpg|jpeg|png|gif|webp|svg|bmp|tiff|ico|heic|raw|cr2|nef)
            echo "images"
            ;;
        # Videos
        mp4|mkv|avi|mov|wmv|flv|webm|m4v|mpg|mpeg)
            echo "videos"
            ;;
        # Audio
        mp3|flac|wav|aac|ogg|m4a|wma|aiff|opus)
            echo "audio"
            ;;
        # Code
        js|ts|jsx|tsx|py|go|rs|java|c|cpp|h|hpp|rb|php|swift|kt|scala|sh|bash|zsh|ps1)
            echo "code"
            ;;
        # Data
        json|yaml|yml|xml|csv|sql|toml|ini|env)
            echo "data"
            ;;
        # Archives
        zip|tar|gz|bz2|xz|7z|rar|tgz|tbz2)
            echo "archives"
            ;;
        # Executables
        exe|msi|dmg|pkg|deb|rpm|app|bin)
            echo "executables"
            ;;
        *)
            echo "other"
            ;;
    esac
}

# Detect project type by marker files
detect_project_type() {
    local dir="$1"

    [[ -f "$dir/package.json" ]] && { echo "nodejs"; return; }
    [[ -f "$dir/Cargo.toml" ]] && { echo "rust"; return; }
    [[ -f "$dir/go.mod" ]] && { echo "go"; return; }
    [[ -f "$dir/requirements.txt" ]] && { echo "python"; return; }
    [[ -f "$dir/pyproject.toml" ]] && { echo "python"; return; }
    [[ -f "$dir/setup.py" ]] && { echo "python"; return; }
    [[ -f "$dir/Gemfile" ]] && { echo "ruby"; return; }
    [[ -f "$dir/pom.xml" ]] && { echo "java-maven"; return; }
    [[ -f "$dir/build.gradle" ]] && { echo "java-gradle"; return; }
    [[ -f "$dir/composer.json" ]] && { echo "php"; return; }
    [[ -f "$dir/mix.exs" ]] && { echo "elixir"; return; }
    [[ -f "$dir/Makefile" ]] && { echo "make"; return; }
    [[ -d "$dir/.git" ]] && { echo "git-repo"; return; }

    echo "unknown"
}
