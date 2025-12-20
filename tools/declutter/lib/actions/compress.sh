#!/usr/bin/env bash
#
# Declutter - Compress Action
# Archive and compress files
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_ACTION_COMPRESS_LOADED:-}" ]] && return 0
readonly _DECLUTTER_ACTION_COMPRESS_LOADED=1

# =============================================================================
# Dependencies
# =============================================================================

# Module directory
_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/utils.sh
source "$_MODULE_DIR/../core/utils.sh"
# shellcheck source=../core/logger.sh
source "$_MODULE_DIR/../core/logger.sh"
# shellcheck source=../core/config.sh
source "$_MODULE_DIR/../core/config.sh"

# =============================================================================
# Action Registration
# =============================================================================

if declare -F register_action &>/dev/null; then
    register_action "compress" "action_compress" "Compress files"
    register_action "archive" "action_archive" "Archive files"
fi

# =============================================================================
# Compress Operations
# =============================================================================

# Main compress function
action_compress() {
    local source="$1"
    local format="${2:-}"
    local level="${3:-}"
    local keep_original="${4:-false}"

    if [[ ! -e "$source" ]]; then
        log_error "Source not found: $source"
        return 1
    fi

    # Get format from config if not specified
    if [[ -z "$format" ]]; then
        format="$(config_action "compress_format" "gzip")"
    fi

    if [[ -z "$level" ]]; then
        level="$(config_action "compress_level" "6")"
    fi

    # Check dry run
    if is_dry_run; then
        dry_run_action "compress ($format)" "$source"
        return 0
    fi

    local dest
    case "$format" in
        gzip|gz)
            dest="${source}.gz"
            _compress_gzip "$source" "$dest" "$level"
            ;;
        zstd|zst)
            dest="${source}.zst"
            _compress_zstd "$source" "$dest" "$level"
            ;;
        xz)
            dest="${source}.xz"
            _compress_xz "$source" "$dest" "$level"
            ;;
        bzip2|bz2)
            dest="${source}.bz2"
            _compress_bzip2 "$source" "$dest" "$level"
            ;;
        zip)
            dest="${source}.zip"
            _compress_zip "$source" "$dest" "$level"
            ;;
        *)
            log_error "Unknown compression format: $format"
            return 1
            ;;
    esac

    local exit_code=$?

    if ((exit_code == 0)); then
        log_success "Compressed: $source → $(basename "$dest")"

        # Record in journal
        if is_journal_enabled; then
            journal_record "compress" "$source" "$dest" "{\"format\":\"$format\"}"
        fi

        # Remove original if not keeping
        if [[ "$keep_original" != "true" ]] && [[ -f "$dest" ]]; then
            rm -f "$source"
            log_debug "Removed original: $source"
        fi

        # Report savings
        local orig_size comp_size savings
        orig_size="$(get_file_size "$source" 2>/dev/null || echo 0)"
        comp_size="$(get_file_size "$dest")"
        if ((orig_size > 0)); then
            savings=$(( (orig_size - comp_size) * 100 / orig_size ))
            log_info "Compression ratio: ${savings}% savings"
        fi
    else
        log_error "Failed to compress: $source"
    fi

    return $exit_code
}

# Gzip compression
_compress_gzip() {
    local source="$1"
    local dest="$2"
    local level="$3"

    gzip -"$level" -c "$source" > "$dest"
}

# Zstd compression
_compress_zstd() {
    local source="$1"
    local dest="$2"
    local level="$3"

    if command -v zstd &>/dev/null; then
        zstd -"$level" -q "$source" -o "$dest"
    else
        log_error "zstd not installed"
        return 1
    fi
}

# XZ compression
_compress_xz() {
    local source="$1"
    local dest="$2"
    local level="$3"

    xz -"$level" -c "$source" > "$dest"
}

# Bzip2 compression
_compress_bzip2() {
    local source="$1"
    local dest="$2"
    local level="$3"

    bzip2 -"$level" -c "$source" > "$dest"
}

# Zip compression
_compress_zip() {
    local source="$1"
    local dest="$2"
    local level="$3"

    if [[ -d "$source" ]]; then
        zip -"$level" -r -q "$dest" "$source"
    else
        zip -"$level" -q "$dest" "$source"
    fi
}

# =============================================================================
# Archive Operations
# =============================================================================

# Archive multiple files/directories
action_archive() {
    local dest="$1"
    local format="${2:-tar.gz}"
    shift 2
    local -a sources=("$@")

    if ((${#sources[@]} == 0)); then
        log_error "No sources specified"
        return 1
    fi

    # Check dry run
    if is_dry_run; then
        dry_run_action "archive" "${sources[*]}" "$dest"
        return 0
    fi

    local exit_code=0

    case "$format" in
        tar.gz|tgz)
            tar -czf "$dest" "${sources[@]}"
            exit_code=$?
            ;;
        tar.bz2|tbz2)
            tar -cjf "$dest" "${sources[@]}"
            exit_code=$?
            ;;
        tar.xz|txz)
            tar -cJf "$dest" "${sources[@]}"
            exit_code=$?
            ;;
        tar.zst)
            if command -v zstd &>/dev/null; then
                tar -cf - "${sources[@]}" | zstd -o "$dest"
                exit_code=$?
            else
                log_error "zstd not installed"
                return 1
            fi
            ;;
        tar)
            tar -cf "$dest" "${sources[@]}"
            exit_code=$?
            ;;
        zip)
            zip -r -q "$dest" "${sources[@]}"
            exit_code=$?
            ;;
        *)
            log_error "Unknown archive format: $format"
            return 1
            ;;
    esac

    if ((exit_code == 0)); then
        log_success "Created archive: $dest"

        if is_journal_enabled; then
            local sources_json
            sources_json="$(printf '%s\n' "${sources[@]}" | jq -R . | jq -s .)"
            journal_record "archive" "$dest" "" "{\"sources\":$sources_json,\"format\":\"$format\"}"
        fi
    else
        log_error "Failed to create archive: $dest"
    fi

    return $exit_code
}

# =============================================================================
# Batch Operations
# =============================================================================

# Compress multiple files
action_compress_batch() {
    local format="${1:-gzip}"
    shift
    local -a files=("$@")

    local success=0
    local failed=0
    local total_saved=0

    for file in "${files[@]}"; do
        local orig_size
        orig_size="$(get_file_size "$file")"

        if action_compress "$file" "$format"; then
            ((success++))

            local comp_size
            comp_size="$(get_file_size "${file}.${format}" 2>/dev/null || echo "$orig_size")"
            ((total_saved += orig_size - comp_size))
        else
            ((failed++))
        fi
    done

    print_action_summary "compress" "$success" "$failed" "$(format_bytes "$total_saved")"
}

# Archive old files
action_archive_old_files() {
    local source_dir="${1:-$PWD}"
    local age_days="${2:-365}"
    local archive_name="${3:-archive_$(date +%Y%m%d).tar.gz}"

    log_step "Archiving files older than $age_days days"

    local -a old_files=()

    while IFS= read -r file; do
        [[ -n "$file" ]] && old_files+=("$file")
    done < <(find "$source_dir" -type f -mtime +"$age_days" 2>/dev/null)

    if ((${#old_files[@]} == 0)); then
        log_info "No files older than $age_days days found"
        return 0
    fi

    log_info "Found ${#old_files[@]} old files"

    if is_interactive; then
        if ! confirm "Archive ${#old_files[@]} files?"; then
            return 0
        fi
    fi

    action_archive "$archive_name" "tar.gz" "${old_files[@]}"
}

# =============================================================================
# Decompress Operations
# =============================================================================

# Decompress file
action_decompress() {
    local source="$1"
    local dest="${2:-}"

    if [[ ! -f "$source" ]]; then
        log_error "Source not found: $source"
        return 1
    fi

    # Check dry run
    if is_dry_run; then
        dry_run_action "decompress" "$source"
        return 0
    fi

    local exit_code=0

    case "$source" in
        *.gz)
            dest="${dest:-${source%.gz}}"
            gunzip -c "$source" > "$dest"
            exit_code=$?
            ;;
        *.zst)
            dest="${dest:-${source%.zst}}"
            if command -v zstd &>/dev/null; then
                zstd -d -q "$source" -o "$dest"
                exit_code=$?
            else
                log_error "zstd not installed"
                return 1
            fi
            ;;
        *.xz)
            dest="${dest:-${source%.xz}}"
            xz -d -c "$source" > "$dest"
            exit_code=$?
            ;;
        *.bz2)
            dest="${dest:-${source%.bz2}}"
            bunzip2 -c "$source" > "$dest"
            exit_code=$?
            ;;
        *.zip)
            dest="${dest:-.}"
            unzip -q "$source" -d "$dest"
            exit_code=$?
            ;;
        *.tar.gz|*.tgz)
            dest="${dest:-.}"
            tar -xzf "$source" -C "$dest"
            exit_code=$?
            ;;
        *.tar.bz2|*.tbz2)
            dest="${dest:-.}"
            tar -xjf "$source" -C "$dest"
            exit_code=$?
            ;;
        *.tar.xz|*.txz)
            dest="${dest:-.}"
            tar -xJf "$source" -C "$dest"
            exit_code=$?
            ;;
        *.tar)
            dest="${dest:-.}"
            tar -xf "$source" -C "$dest"
            exit_code=$?
            ;;
        *)
            log_error "Unknown archive format: $source"
            return 1
            ;;
    esac

    if ((exit_code == 0)); then
        log_success "Decompressed: $source"
    else
        log_error "Failed to decompress: $source"
    fi

    return $exit_code
}

# =============================================================================
# Helper Functions
# =============================================================================

# Get compression ratio
get_compression_ratio() {
    local original="$1"
    local compressed="$2"

    local orig_size comp_size
    orig_size="$(get_file_size "$original")"
    comp_size="$(get_file_size "$compressed")"

    if ((orig_size > 0)); then
        echo $(( (orig_size - comp_size) * 100 / orig_size ))
    else
        echo 0
    fi
}

# Preview compression
preview_compress() {
    local format="$1"
    shift
    local -a files=("$@")

    print_section "Compression Preview"
    print_kv "Format" "$format"
    echo ""

    local total_size=0
    for file in "${files[@]}"; do
        local size
        size="$(get_file_size "$file")"
        ((total_size += size))
        echo "  $(format_bytes "$size")  $file"
    done

    print_divider
    print_kv "Total files" "${#files[@]}"
    print_kv "Total size" "$(format_bytes "$total_size")"
}
