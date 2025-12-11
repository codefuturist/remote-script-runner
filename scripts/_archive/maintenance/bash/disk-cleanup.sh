#!/bin/bash
# =============================================================================
# @id           cleanup
# @name         disk-cleanup
# @displayName  Disk Cleanup
# @description  Clean temporary files, old logs, package cache, and old kernels
# @category     maintenance
# @version      1.0.0
# @author       codefuturist
# @tags         disk,cleanup,temp,logs,cache,kernels,maintenance,storage
# @shells       bash
# =============================================================================

set -euo pipefail

# =============================================================================
# Load RSR Library
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" validate
fi

# Script metadata
SCRIPT_NAME="Disk Cleanup"
SCRIPT_VERSION="1.0.0"

# Default values
DRY_RUN=true
VERBOSE=false
INTERACTIVE=auto
SECTIONS=()
KEEP_DAYS=7
KEEP_KERNELS=2
AGGRESSIVE=false

# Color codes (from RSR library or fallback)
RED="${RSR_COLOR_RED:-\033[0;31m}"
GREEN="${RSR_COLOR_GREEN:-\033[0;32m}"
YELLOW="${RSR_COLOR_YELLOW:-\033[1;33m}"
BLUE="${RSR_COLOR_BLUE:-\033[0;34m}"
DIM="${RSR_COLOR_DIM:-\033[2m}"
BOLD="${RSR_COLOR_BOLD:-\033[1m}"
NC="${RSR_COLOR_RESET:-\033[0m}"

# Counters
TOTAL_FILES=0
TOTAL_SIZE=0

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Clean temporary files, old logs, package cache, and old kernels to free disk space.

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${BOLD}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be deleted (default)
    -x, --execute           Actually perform deletions
    -i, --interactive       Run in interactive mode (default when no args)
    --no-interactive        Disable interactive mode
    -y, --yes               Auto-confirm all prompts
    -a, --all               Run all cleanup sections
    -s, --section SECTION   Run specific section (can repeat)
    --older-than DAYS       Only remove files older than N days (default: 7)
    --keep-kernels N        Keep N most recent kernels (default: 2)
    --aggressive            Include user caches and more aggressive cleaning

${BOLD}Sections:${NC}
    tmp         Temporary files (/tmp, /var/tmp)
    logs        Old and rotated log files
    cache       Package manager cache (apt/yum/dnf)
    kernels     Old kernel versions
    journal     Systemd journal logs
    thumbnails  Thumbnail caches
    crash       Core dumps and crash reports

${BOLD}Examples:${NC}
    ${DIM}# Preview what would be cleaned${NC}
    $0 -a

    ${DIM}# Clean temp files and logs older than 14 days${NC}
    $0 -x -s tmp -s logs --older-than 14

    ${DIM}# Full cleanup including user caches${NC}
    sudo $0 -x -a --aggressive

    ${DIM}# Clean old kernels keeping last 2${NC}
    sudo $0 -x -s kernels --keep-kernels 2

EOF
}

# Logging functions (use RSR if available)
if type rsr_log_info &>/dev/null; then
    log_info() { rsr_log_info "$1"; }
    log_ok() { rsr_log_ok "$1"; }
    log_warn() { rsr_log_warn "$1"; }
    log_error() { rsr_log_error "$1"; }
    log_debug() { [[ "$VERBOSE" == "true" ]] && rsr_log_debug "$1"; }
else
    log_info() { echo -e "${BLUE}▸${NC} $1"; }
    log_ok() { echo -e "${GREEN}✓${NC} $1"; }
    log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
    log_error() { echo -e "${RED}✗${NC} $1" >&2; }
    log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}  $1${NC}"; }
fi

human_size() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes} B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024)) KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576)) MB"
    else
        echo "$((bytes / 1073741824)) GB"
    fi
}

get_size() {
    local path="$1"
    if [[ -e "$path" ]]; then
        du -sb "$path" 2> /dev/null | cut -f1 || echo 0
    else
        echo 0
    fi
}

count_files() {
    local path="$1"
    find "$path" -type f 2> /dev/null | wc -l || echo 0
}

# Cleanup functions
cleanup_tmp() {
    log_info "Cleaning temporary files..."
    local size=0 count=0

    for dir in /tmp /var/tmp; do
        if [[ -d "$dir" ]]; then
            local found=$(find "$dir" -type f -atime +${KEEP_DAYS} 2> /dev/null || true)
            if [[ -n "$found" ]]; then
                local dir_count=$(echo "$found" | wc -l)
                local dir_size=$(echo "$found" | xargs -I{} stat -f%z {} 2> /dev/null | awk '{s+=$1}END{print s+0}' || echo 0)
                count=$((count + dir_count))
                size=$((size + dir_size))

                log_debug "Found $dir_count files in $dir ($(human_size $dir_size))"

                if [[ "$DRY_RUN" == "false" ]]; then
                    find "$dir" -type f -atime +${KEEP_DAYS} -delete 2> /dev/null || true
                fi
            fi
        fi
    done

    TOTAL_FILES=$((TOTAL_FILES + count))
    TOTAL_SIZE=$((TOTAL_SIZE + size))

    if [[ $count -gt 0 ]]; then
        log_ok "Temp files: $count files ($(human_size $size))"
    else
        log_ok "Temp files: nothing to clean"
    fi
}

cleanup_logs() {
    log_info "Cleaning old log files..."
    local size=0 count=0

    if [[ -d /var/log ]]; then
        # Compressed logs
        for pattern in "*.gz" "*.old" "*.[0-9]" "*.[0-9].gz"; do
            local found=$(find /var/log -name "$pattern" -type f 2> /dev/null || true)
            if [[ -n "$found" ]]; then
                local pat_count=$(echo "$found" | wc -l)
                count=$((count + pat_count))

                if [[ "$DRY_RUN" == "false" ]]; then
                    find /var/log -name "$pattern" -type f -delete 2> /dev/null || true
                fi
            fi
        done

        # Old log files by date
        local old_logs=$(find /var/log -type f -name "*.log" -mtime +${KEEP_DAYS} 2> /dev/null || true)
        if [[ -n "$old_logs" ]]; then
            count=$((count + $(echo "$old_logs" | wc -l)))
        fi
    fi

    TOTAL_FILES=$((TOTAL_FILES + count))

    if [[ $count -gt 0 ]]; then
        log_ok "Log files: $count files cleaned"
    else
        log_ok "Log files: nothing to clean"
    fi
}

cleanup_cache() {
    log_info "Cleaning package manager cache..."
    local cleaned=false

    # APT (Debian/Ubuntu)
    if command -v apt-get &> /dev/null; then
        local apt_cache="/var/cache/apt/archives"
        if [[ -d "$apt_cache" ]]; then
            local size=$(get_size "$apt_cache")
            log_debug "APT cache: $(human_size $size)"
            TOTAL_SIZE=$((TOTAL_SIZE + size))

            if [[ "$DRY_RUN" == "false" ]]; then
                apt-get clean -y 2> /dev/null || true
            fi
            cleaned=true
        fi
    fi

    # YUM (RHEL/CentOS 7)
    if command -v yum &> /dev/null && [[ ! -f /usr/bin/dnf ]]; then
        local yum_cache="/var/cache/yum"
        if [[ -d "$yum_cache" ]]; then
            local size=$(get_size "$yum_cache")
            log_debug "YUM cache: $(human_size $size)"
            TOTAL_SIZE=$((TOTAL_SIZE + size))

            if [[ "$DRY_RUN" == "false" ]]; then
                yum clean all 2> /dev/null || true
            fi
            cleaned=true
        fi
    fi

    # DNF (RHEL/CentOS 8+, Fedora)
    if command -v dnf &> /dev/null; then
        local dnf_cache="/var/cache/dnf"
        if [[ -d "$dnf_cache" ]]; then
            local size=$(get_size "$dnf_cache")
            log_debug "DNF cache: $(human_size $size)"
            TOTAL_SIZE=$((TOTAL_SIZE + size))

            if [[ "$DRY_RUN" == "false" ]]; then
                dnf clean all 2> /dev/null || true
            fi
            cleaned=true
        fi
    fi

    # Pacman (Arch)
    if command -v pacman &> /dev/null; then
        local pacman_cache="/var/cache/pacman/pkg"
        if [[ -d "$pacman_cache" ]]; then
            local size=$(get_size "$pacman_cache")
            log_debug "Pacman cache: $(human_size $size)"
            TOTAL_SIZE=$((TOTAL_SIZE + size))

            if [[ "$DRY_RUN" == "false" ]]; then
                pacman -Sc --noconfirm 2> /dev/null || true
            fi
            cleaned=true
        fi
    fi

    # Homebrew (macOS)
    if command -v brew &> /dev/null; then
        if [[ "$DRY_RUN" == "false" ]]; then
            brew cleanup --prune=${KEEP_DAYS} 2> /dev/null || true
        fi
        cleaned=true
    fi

    if [[ "$cleaned" == "true" ]]; then
        log_ok "Package cache: cleaned"
    else
        log_ok "Package cache: no supported package manager found"
    fi
}

cleanup_kernels() {
    log_info "Cleaning old kernels..."

    # Only on Linux
    if [[ "$(uname)" != "Linux" ]]; then
        log_warn "Kernel cleanup only available on Linux"
        return
    fi

    local current_kernel=$(uname -r)
    log_debug "Current kernel: $current_kernel"

    # Debian/Ubuntu
    if command -v dpkg &> /dev/null; then
        local old_kernels=$(dpkg -l 'linux-image-*' 2> /dev/null | grep ^ii | awk '{print $2}' | grep -v "$current_kernel" | head -n -${KEEP_KERNELS} || true)

        if [[ -n "$old_kernels" ]]; then
            local count=$(echo "$old_kernels" | wc -l)
            log_debug "Found $count old kernel(s) to remove"

            if [[ "$DRY_RUN" == "false" ]]; then
                echo "$old_kernels" | xargs apt-get remove -y 2> /dev/null || true
            else
                echo "$old_kernels" | while read -r kernel; do
                    log_debug "Would remove: $kernel"
                done
            fi
            log_ok "Kernels: $count old kernel(s)"
        else
            log_ok "Kernels: nothing to clean"
        fi
        return
    fi

    # RHEL/CentOS
    if command -v rpm &> /dev/null; then
        local old_kernels=$(rpm -q kernel 2> /dev/null | grep -v "$current_kernel" | head -n -${KEEP_KERNELS} || true)

        if [[ -n "$old_kernels" ]]; then
            local count=$(echo "$old_kernels" | wc -l)

            if [[ "$DRY_RUN" == "false" ]]; then
                if command -v dnf &> /dev/null; then
                    dnf remove $old_kernels -y 2> /dev/null || true
                elif command -v yum &> /dev/null; then
                    yum remove $old_kernels -y 2> /dev/null || true
                fi
            fi
            log_ok "Kernels: $count old kernel(s)"
        else
            log_ok "Kernels: nothing to clean"
        fi
    fi
}

cleanup_journal() {
    log_info "Cleaning systemd journal..."

    if ! command -v journalctl &> /dev/null; then
        log_debug "journalctl not available"
        return
    fi

    local usage=$(journalctl --disk-usage 2> /dev/null | grep -oP '\d+\.?\d*[KMGT]?' || echo "0")
    log_debug "Journal usage: $usage"

    if [[ "$DRY_RUN" == "false" ]]; then
        journalctl --vacuum-time=${KEEP_DAYS}d 2> /dev/null || true
    fi

    log_ok "Journal: cleaned (kept last ${KEEP_DAYS} days)"
}

cleanup_thumbnails() {
    log_info "Cleaning thumbnail caches..."
    local count=0

    # Common thumbnail locations
    for dir in ~/.cache/thumbnails ~/.thumbnails /tmp/thumbnails; do
        if [[ -d "$dir" ]]; then
            local dir_count=$(count_files "$dir")
            count=$((count + dir_count))

            if [[ "$DRY_RUN" == "false" && -n "$dir" ]]; then
                rm -rf "${dir:?}"/* 2> /dev/null || true
            fi
        fi
    done

    TOTAL_FILES=$((TOTAL_FILES + count))

    if [[ $count -gt 0 ]]; then
        log_ok "Thumbnails: $count files"
    else
        log_ok "Thumbnails: nothing to clean"
    fi
}

cleanup_crash() {
    log_info "Cleaning crash reports and core dumps..."
    local count=0

    # Core dumps
    for pattern in /var/crash/* /var/lib/systemd/coredump/* core core.* *.core; do
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                count=$((count + 1))
                log_debug "Found: $file"

                if [[ "$DRY_RUN" == "false" ]]; then
                    rm -f "$file" 2> /dev/null || true
                fi
            fi
        done
    done

    TOTAL_FILES=$((TOTAL_FILES + count))

    if [[ $count -gt 0 ]]; then
        log_ok "Crash reports: $count files"
    else
        log_ok "Crash reports: nothing to clean"
    fi
}

cleanup_aggressive() {
    log_info "Running aggressive cleanup..."

    # User caches
    if [[ -d ~/.cache ]]; then
        # pip cache
        if [[ -d ~/.cache/pip ]]; then
            local size=$(get_size ~/.cache/pip)
            log_debug "pip cache: $(human_size $size)"
            TOTAL_SIZE=$((TOTAL_SIZE + size))

            if [[ "$DRY_RUN" == "false" ]]; then
                rm -rf ~/.cache/pip 2> /dev/null || true
            fi
        fi

        # npm cache
        if [[ -d ~/.npm/_cacache ]]; then
            local size=$(get_size ~/.npm/_cacache)
            log_debug "npm cache: $(human_size $size)"
            TOTAL_SIZE=$((TOTAL_SIZE + size))

            if [[ "$DRY_RUN" == "false" ]]; then
                npm cache clean --force 2> /dev/null || true
            fi
        fi

        # yarn cache
        if command -v yarn &> /dev/null; then
            if [[ "$DRY_RUN" == "false" ]]; then
                yarn cache clean 2> /dev/null || true
            fi
        fi
    fi

    log_ok "Aggressive cleanup: completed"
}

show_disk_usage() {
    echo
    echo -e "${BOLD}Disk Usage:${NC}"
    df -h / 2> /dev/null | tail -1 | awk '{printf "  Root filesystem: %s used of %s (%s)\n", $3, $2, $5}'
}

# =============================================================================
# Interactive Mode
# =============================================================================

run_interactive() {
    print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"

    show_disk_usage
    echo ""

    # Section selection with multi-select
    local all_sections=("tmp - Temporary files (/tmp, /var/tmp)" \
        "logs - Old and rotated log files" \
        "cache - Package manager cache" \
        "kernels - Old kernel versions" \
        "journal - Systemd journal logs" \
        "thumbnails - Thumbnail caches" \
        "crash - Core dumps and crash reports")

    # Pre-select common sections
    PRESELECTED=(0 1 2 4)

    echo ""
    readarray -t selected_sections < <(prompt_multiselect "Select cleanup sections:" "${all_sections[@]}")

    if [[ ${#selected_sections[@]} -eq 0 ]]; then
        log_warn "No sections selected"
        return 0
    fi

    # Parse selected sections
    SECTIONS=()
    for section in "${selected_sections[@]}"; do
        SECTIONS+=("$(echo "$section" | cut -d' ' -f1)")
    done

    echo ""

    # Additional options
    local days
    days=$(prompt_input "Delete files older than how many days?" "7")
    KEEP_DAYS="$days"

    if [[ " ${SECTIONS[*]} " =~ " kernels " ]]; then
        local kernels
        kernels=$(prompt_input "Keep how many recent kernels?" "2")
        KEEP_KERNELS="$kernels"
    fi

    echo ""
    if prompt_yes_no "Include aggressive cleanup (pip, npm, yarn caches)?" "n"; then
        AGGRESSIVE=true
    fi

    echo ""

    # Preview mode
    log_info "Running preview scan..."
    echo ""
    DRY_RUN=true

    for section in "${SECTIONS[@]}"; do
        case "$section" in
            tmp) cleanup_tmp ;;
            logs) cleanup_logs ;;
            cache) cleanup_cache ;;
            kernels) cleanup_kernels ;;
            journal) cleanup_journal ;;
            thumbnails) cleanup_thumbnails ;;
            crash) cleanup_crash ;;
        esac
    done

    if [[ "$AGGRESSIVE" == "true" ]]; then
        cleanup_aggressive
    fi

    echo ""
    echo -e "${BOLD}Preview Summary:${NC}"
    echo -e "  Would clean: ${YELLOW}$TOTAL_FILES files${NC}"
    echo -e "  Estimated space: ${YELLOW}$(human_size $TOTAL_SIZE)${NC}"
    echo ""

    # Confirm before executing
    if confirm_destructive "This will permanently delete the files listed above"; then
        # Reset counters and execute
        TOTAL_FILES=0
        TOTAL_SIZE=0
        DRY_RUN=false

        echo ""
        log_info "Executing cleanup..."
        echo ""

        for section in "${SECTIONS[@]}"; do
            case "$section" in
                tmp) cleanup_tmp ;;
                logs) cleanup_logs ;;
                cache) cleanup_cache ;;
                kernels) cleanup_kernels ;;
                journal) cleanup_journal ;;
                thumbnails) cleanup_thumbnails ;;
                crash) cleanup_crash ;;
            esac
        done

        if [[ "$AGGRESSIVE" == "true" ]]; then
            cleanup_aggressive
        fi

        echo ""
        log_ok "Cleanup completed!"
        echo -e "  Cleaned: ${GREEN}$TOTAL_FILES files${NC}"
        show_disk_usage
    else
        log_info "Cleanup cancelled"
    fi
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            -x | --execute)
                DRY_RUN=false
                shift
                ;;
            -i | --interactive)
                INTERACTIVE=true
                shift
                ;;
            --no-interactive)
                INTERACTIVE=false
                shift
                ;;
            -y | --yes)
                RSR_YES=1
                INTERACTIVE=false
                shift
                ;;
            -a | --all)
                SECTIONS=(tmp logs cache kernels journal thumbnails crash)
                shift
                ;;
            -s | --section)
                SECTIONS+=("$2")
                shift 2
                ;;
            --older-than)
                KEEP_DAYS="$2"
                shift 2
                ;;
            --keep-kernels)
                KEEP_KERNELS="$2"
                shift 2
                ;;
            --aggressive)
                AGGRESSIVE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Default to all sections if none specified
    if [[ ${#SECTIONS[@]} -eq 0 ]]; then
        SECTIONS=(tmp logs cache journal)
    fi
}

main() {
    local original_args=("$@")
    parse_args "$@"

    # Determine if interactive mode should be enabled
    if [[ "$INTERACTIVE" == "auto" ]]; then
        if [[ ${#original_args[@]} -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
            INTERACTIVE=true
        else
            INTERACTIVE=false
        fi
    fi

    # Run interactive mode if enabled
    if [[ "$INTERACTIVE" == "true" ]] && type -t rsr_is_interactive &>/dev/null && rsr_is_interactive; then
        run_interactive
        exit 0
    fi

    echo
    echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║         Disk Cleanup v${SCRIPT_VERSION}            ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
    echo

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE${NC} - No files will be deleted"
        echo -e "Use ${BOLD}-x${NC} or ${BOLD}--execute${NC} to actually delete files"
        echo
    fi

    show_disk_usage
    echo

    # Run selected sections
    for section in "${SECTIONS[@]}"; do
        case "$section" in
            tmp) cleanup_tmp ;;
            logs) cleanup_logs ;;
            cache) cleanup_cache ;;
            kernels) cleanup_kernels ;;
            journal) cleanup_journal ;;
            thumbnails) cleanup_thumbnails ;;
            crash) cleanup_crash ;;
            *) log_warn "Unknown section: $section" ;;
        esac
    done

    # Aggressive cleanup if requested
    if [[ "$AGGRESSIVE" == "true" ]]; then
        cleanup_aggressive
    fi

    # Summary
    echo
    echo -e "${BOLD}Summary:${NC}"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  Would clean: ${GREEN}$TOTAL_FILES files${NC}"
        echo -e "  Estimated space: ${GREEN}$(human_size $TOTAL_SIZE)${NC}"
    else
        echo -e "  Cleaned: ${GREEN}$TOTAL_FILES files${NC}"
        show_disk_usage
    fi
    echo
}

main "$@"
