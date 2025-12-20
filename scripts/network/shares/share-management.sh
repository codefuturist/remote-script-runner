#!/usr/bin/env bash
# =============================================================================
# @id           share-management
# @name         share-management
# @displayName  Network Share Management
# @description  Manage network shares: mount, unmount, discover, configure (NFS, SMB, SSHFS, WebDAV)
# @category     network
# @subcategory  shares
# @version      1.0.0
# @author       codefuturist
# @tags         network,shares,mount,nfs,smb,cifs,sshfs,webdav,storage
# @shells       bash
# @requires     bash 4.0+
# @os           linux,macos
# @sudo         optional
# =============================================================================
#
# A comprehensive tool for managing network file shares across different
# protocols. Supports NFS, SMB/CIFS, SSHFS, and WebDAV with features for:
#
# - Auto-detection of share protocol from path
# - Credential management via environment variables or encrypted storage
# - Network discovery for available shares
# - Persistent mount configuration (fstab, systemd, autofs)
# - Interactive and scriptable modes
#
# Usage:
#   share-management.sh <command> [options]
#
# Examples:
#   share-management.sh mount //server/share /mnt/share
#   share-management.sh discover server.local
#   share-management.sh add --name myshare --source //server/share --target /mnt/share
#   share-management.sh list
#
# =============================================================================

set -eo pipefail

# =============================================================================
# Windows Detection - Redirect to PowerShell script
# =============================================================================

case "$(uname -s 2>/dev/null)" in
    CYGWIN*|MINGW*|MSYS*)
        echo "Windows detected. Please use the PowerShell script instead:" >&2
        echo "  .\\share-management.ps1 $*" >&2
        echo "" >&2
        echo "Or run from PowerShell:" >&2
        echo "  powershell -ExecutionPolicy Bypass -File share-management.ps1 $*" >&2
        exit 1
        ;;
esac

# =============================================================================
# RSR Library
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [[ -n "${SCRIPT_SOURCE}" && "${SCRIPT_SOURCE}" != "bash" && "${SCRIPT_SOURCE}" != "sh" && "${SCRIPT_SOURCE}" != "-bash" && "${SCRIPT_SOURCE}" != "-sh" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

# Load RSR library with required modules
if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    # shellcheck source=../../../lib/rsr-lib.sh
    source "$RSR_LIB_DIR/rsr-lib.sh" validate interactive shares
else
    echo "ERROR: RSR library not found at $RSR_LIB_DIR/rsr-lib.sh" >&2
    echo "       Run this script from the repository root or set RSR_LIB_DIR" >&2
    exit 1
fi

# =============================================================================
# Script Configuration
# =============================================================================

readonly SCRIPT_NAME="Network Share Management"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_COMMAND="shares"

# Default options
VERBOSE=false
DRY_RUN=false
INTERACTIVE=auto
RSR_YES=0
SUBCOMMAND=""

# Share options
SHARE_NAME=""
SHARE_SOURCE=""
SHARE_TARGET=""
SHARE_TYPE=""
SHARE_OPTIONS=""
SHARE_USERNAME=""
SHARE_PASSWORD=""
SHARE_DOMAIN=""
SHARE_AUTOMOUNT=false
SHARE_FORCE=false
USE_FINDER=false

# Discovery options
DISCOVER_HOST=""
DISCOVER_SUBNET=""

# Automount options
AUTOMOUNT_METHOD=""  # fstab, systemd, autofs

# Output format
OUTPUT_FORMAT="table"  # table, json, simple

# =============================================================================
# Logging Aliases
# =============================================================================

log_info() { rsr_log_info "$*"; }
log_ok() { rsr_log_ok "$*"; }
log_warn() { rsr_log_warn "$*"; }
log_error() { rsr_log_error "$*"; }
log_debug() { [[ "$VERBOSE" == "true" ]] && rsr_log_debug "$*" || true; }

# Colors from RSR library
BLUE="$RSR_COLOR_BLUE"
GREEN="$RSR_COLOR_GREEN"
YELLOW="$RSR_COLOR_YELLOW"
RED="$RSR_COLOR_RED"
CYAN="$RSR_COLOR_CYAN"
DIM="$RSR_COLOR_DIM"
BOLD="$RSR_COLOR_BOLD"
NC="$RSR_COLOR_RESET"

# =============================================================================
# Help & Usage
# =============================================================================

show_help() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Manage network file shares across different protocols (NFS, SMB/CIFS, SSHFS, WebDAV).

${YELLOW}Usage:${NC}
    $0 <command> [OPTIONS]

${BOLD}Commands:${NC}

  ${CYAN}Mount Operations:${NC}
    mount               Mount a network share
    unmount, umount     Unmount a network share
    remount             Remount a share (unmount + mount)

  ${CYAN}Share Configuration:${NC}
    add                 Add and save a share configuration
    remove              Remove a saved share configuration
    edit                Edit a saved share configuration
    show                Show details of a saved share

  ${CYAN}Discovery:${NC}
    list                List mounted and/or saved shares
    discover            Discover shares on a server
    scan                Scan network for file servers
    test                Test connectivity to a share

  ${CYAN}Credentials:${NC}
    creds set           Store credentials for a share
    creds get           Show stored credential (username only)
    creds delete        Delete stored credentials
    creds list          List all stored credentials

  ${CYAN}Automount:${NC}
    automount enable    Enable automount for a share
    automount disable   Disable automount for a share
    automount generate  Generate automount config (fstab/systemd/autofs)
    automount status    Show automount status

  ${CYAN}Status:${NC}
    status              Show status of all shares
    health              Health check for mounted shares

${BOLD}Global Options:${NC}
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -d, --dry-run       Show what would be done without executing
    -y, --yes           Auto-confirm all prompts
    -i, --interactive   Force interactive mode
    --no-interactive    Disable interactive mode
    --json              Output in JSON format
    --version           Show version information

${BOLD}Mount Options:${NC}
    -n, --name NAME     Share name (for saving/reference)
    -s, --source PATH   Share source (e.g., //server/share, server:/path)
    -t, --target PATH   Local mount point
    -T, --type TYPE     Share type: nfs, smb, sshfs, webdav (auto-detected)
    -o, --options OPTS  Mount options (comma-separated)
    -u, --user USER     Username for authentication
    -p, --pass PASS     Password (prefer env vars or prompts)
    -D, --domain DOMAIN Windows domain for SMB
    -f, --force         Force operation (e.g., force unmount)
    --save              Save share configuration after mounting
    --finder, --open    Open share in Finder (macOS only, native mount experience)

${BOLD}Examples:${NC}

    ${DIM}# Mount an SMB share (auto-detected)${NC}
    $0 mount //fileserver/documents /mnt/docs

    ${DIM}# Mount like Finder would (macOS) - opens native dialog${NC}
    $0 mount //fileserver/documents --finder

    ${DIM}# Mount NFS share with options${NC}
    $0 mount server:/export/data /mnt/data -o rw,soft,timeo=30

    ${DIM}# Mount with credentials from environment${NC}
    SMB_USER=john SMB_PASS=secret $0 mount //server/share /mnt/share

    ${DIM}# Interactive mount (will prompt for details and locations)${NC}
    $0 mount -i

    ${DIM}# Add a saved share with automount${NC}
    $0 add -n work-files -s //work.local/files -t /mnt/work --automount

    ${DIM}# Discover shares on a server${NC}
    $0 discover fileserver.local

    ${DIM}# Scan local network for SMB servers${NC}
    $0 scan

    ${DIM}# List all mounted network shares${NC}
    $0 list --mounted

    ${DIM}# Generate systemd mount unit${NC}
    $0 automount generate work-files --method systemd

    ${DIM}# Test share connectivity${NC}
    $0 test //server/share

${BOLD}Environment Variables:${NC}
    SMB_USER, CIFS_USER     Default username for SMB shares
    SMB_PASS, CIFS_PASS     Default password for SMB shares
    RSR_SHARE_CONFIG_DIR    Config directory (default: ~/.config/rsr/shares)

EOF
}

show_version() {
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
}

show_command_help() {
    local cmd="$1"

    case "$cmd" in
        mount)
            cat << EOF
${BOLD}Mount Command${NC}

Mount a network share to a local directory.

${YELLOW}Usage:${NC}
    $0 mount [OPTIONS] [SOURCE] [TARGET]

${BOLD}Options:${NC}
    -s, --source PATH   Share source path
    -t, --target PATH   Local mount point
    -T, --type TYPE     Share type (auto-detected if not specified)
    -o, --options OPTS  Mount options
    -u, --user USER     Username
    -p, --pass PASS     Password
    -n, --name NAME     Save as named share
    --save              Save configuration after mounting

${BOLD}Supported Protocols:${NC}
    SMB/CIFS    //server/share, smb://server/share
    NFS         server:/export/path
    SSHFS       user@server:/path, sftp://server/path
    WebDAV      https://server/webdav, dav://server/path

${BOLD}Examples:${NC}
    $0 mount //server/share /mnt/share
    $0 mount -s server:/export -t /mnt/nfs -o rw,soft
    $0 mount -u admin -p secret //nas/backup /backup
EOF
            ;;
        add)
            cat << EOF
${BOLD}Add Command${NC}

Save a share configuration for later use.

${YELLOW}Usage:${NC}
    $0 add [OPTIONS]

${BOLD}Options:${NC}
    -n, --name NAME     Share name (required)
    -s, --source PATH   Share source (required)
    -t, --target PATH   Local mount point (required)
    -T, --type TYPE     Share type (auto-detected)
    -o, --options OPTS  Mount options
    -u, --user USER     Store username
    -p, --pass PASS     Store password (encrypted)
    --automount         Enable automount

${BOLD}Examples:${NC}
    $0 add -n work -s //server/share -t /mnt/work
    $0 add -n home-nas -s //nas/media -t /media/nas -u admin --automount
EOF
            ;;
        discover)
            cat << EOF
${BOLD}Discover Command${NC}

Discover available shares on a server.

${YELLOW}Usage:${NC}
    $0 discover [OPTIONS] <SERVER>

${BOLD}Options:${NC}
    -T, --type TYPE     Protocol to discover: smb, nfs, all (default: all)
    -u, --user USER     Username for authenticated discovery

${BOLD}Examples:${NC}
    $0 discover fileserver.local
    $0 discover -T nfs 192.168.1.100
    $0 discover -u admin nas.local
EOF
            ;;
        *)
            show_help
            ;;
    esac
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    # Get subcommand first
    if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
        SUBCOMMAND="$1"
        shift
    fi

    # Collect positional arguments
    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                if [[ -n "$SUBCOMMAND" ]]; then
                    show_command_help "$SUBCOMMAND"
                else
                    show_help
                fi
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                RSR_YES=1
                INTERACTIVE=false
                shift
                ;;
            -i|--interactive)
                INTERACTIVE=true
                shift
                ;;
            --no-interactive)
                INTERACTIVE=false
                shift
                ;;
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            -n|--name)
                SHARE_NAME="$2"
                shift 2
                ;;
            -s|--source)
                SHARE_SOURCE="$2"
                shift 2
                ;;
            -t|--target)
                SHARE_TARGET="$2"
                shift 2
                ;;
            -T|--type)
                SHARE_TYPE="$2"
                shift 2
                ;;
            -o|--options)
                SHARE_OPTIONS="$2"
                shift 2
                ;;
            -u|--user|--username)
                SHARE_USERNAME="$2"
                shift 2
                ;;
            -p|--pass|--password)
                SHARE_PASSWORD="$2"
                shift 2
                ;;
            -D|--domain)
                SHARE_DOMAIN="$2"
                shift 2
                ;;
            -f|--force)
                SHARE_FORCE=true
                shift
                ;;
            --save)
                [[ -z "$SHARE_NAME" ]] && SHARE_NAME="saved_$(date +%s)"
                shift
                ;;
            --automount)
                SHARE_AUTOMOUNT=true
                shift
                ;;
            --finder|--open)
                USE_FINDER=true
                shift
                ;;
            --method)
                AUTOMOUNT_METHOD="$2"
                shift 2
                ;;
            --mounted)
                LIST_MOUNTED=true
                shift
                ;;
            --saved)
                LIST_SAVED=true
                shift
                ;;
            --all)
                LIST_ALL=true
                shift
                ;;
            --)
                shift
                positional+=("$@")
                break
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    # Handle positional arguments based on subcommand
    case "$SUBCOMMAND" in
        mount|test)
            [[ ${#positional[@]} -ge 1 && -z "$SHARE_SOURCE" ]] && SHARE_SOURCE="${positional[0]}" || true
            [[ ${#positional[@]} -ge 2 && -z "$SHARE_TARGET" ]] && SHARE_TARGET="${positional[1]}" || true
            ;;
        unmount|umount)
            [[ ${#positional[@]} -ge 1 && -z "$SHARE_TARGET" ]] && SHARE_TARGET="${positional[0]}" || true
            ;;
        discover)
            [[ ${#positional[@]} -ge 1 ]] && DISCOVER_HOST="${positional[0]}" || true
            ;;
        scan)
            [[ ${#positional[@]} -ge 1 ]] && DISCOVER_SUBNET="${positional[0]}" || true
            ;;
        show|remove|edit)
            [[ ${#positional[@]} -ge 1 && -z "$SHARE_NAME" ]] && SHARE_NAME="${positional[0]}" || true
            ;;
        automount)
            # Handle sub-subcommand
            [[ ${#positional[@]} -ge 1 ]] && AUTOMOUNT_SUBCMD="${positional[0]}" || true
            [[ ${#positional[@]} -ge 2 && -z "$SHARE_NAME" ]] && SHARE_NAME="${positional[1]}" || true
            ;;
        creds)
            # Handle sub-subcommand
            [[ ${#positional[@]} -ge 1 ]] && CREDS_SUBCMD="${positional[0]}" || true
            [[ ${#positional[@]} -ge 2 && -z "$SHARE_NAME" ]] && SHARE_NAME="${positional[1]}" || true
            ;;
    esac
}

# =============================================================================
# Interactive Mode Functions
# =============================================================================

interactive_mount() {
    rsr_print_header "Mount Network Share"

    # Share type selection
    echo ""
    log_info "Select share type:"
    local types=("SMB/CIFS (Windows/Samba)" "NFS (Unix/Linux)" "SSHFS (SSH)" "WebDAV (HTTP)")
    local type_values=("smb" "nfs" "sshfs" "webdav")

    if rsr_has_fancy_terminal; then
        local selected
        selected=$(rsr_prompt_select "Share type" "${types[@]}")
        for i in "${!types[@]}"; do
            [[ "${types[$i]}" == "$selected" ]] && SHARE_TYPE="${type_values[$i]}"
        done
    else
        echo "  1) SMB/CIFS (Windows/Samba shares)"
        echo "  2) NFS (Unix/Linux exports)"
        echo "  3) SSHFS (SSH filesystem)"
        echo "  4) WebDAV (HTTP-based)"
        echo ""
        read -rp "Select type [1-4]: " choice
        case "$choice" in
            1) SHARE_TYPE="smb" ;;
            2) SHARE_TYPE="nfs" ;;
            3) SHARE_TYPE="sshfs" ;;
            4) SHARE_TYPE="webdav" ;;
            *) log_error "Invalid selection"; exit 1 ;;
        esac
    fi

    echo ""

    # Get share source based on type
    case "$SHARE_TYPE" in
        smb)
            log_info "Enter SMB share path (e.g., //server/share):"
            read -rp "Share path: " SHARE_SOURCE

            if rsr_prompt_confirm "Authenticate with username/password?" "y"; then
                read -rp "Username: " SHARE_USERNAME
                read -rsp "Password: " SHARE_PASSWORD
                echo ""
                read -rp "Domain (optional): " SHARE_DOMAIN
            fi
            ;;
        nfs)
            log_info "Enter NFS export path (e.g., server:/export):"
            read -rp "Export path: " SHARE_SOURCE
            ;;
        sshfs)
            log_info "Enter SSHFS path (e.g., user@server:/path):"
            read -rp "SSH path: " SHARE_SOURCE
            ;;
        webdav)
            log_info "Enter WebDAV URL (e.g., https://server/dav):"
            read -rp "WebDAV URL: " SHARE_SOURCE
            ;;
    esac

    echo ""

    # Get mount point - offer common locations
    log_info "Select or enter mount point location:"

    # Extract share name for suggestions
    local suggested_name
    suggested_name=$(basename "$SHARE_SOURCE" | tr -d '\\')

    # Define common mount locations based on OS
    local mount_locations=()
    if [[ "$(rsr_detect_os)" == "darwin" ]]; then
        mount_locations=(
            "/Volumes/$suggested_name (like Finder)"
            "$HOME/Mounts/$suggested_name"
            "/tmp/$suggested_name (temporary)"
            "$HOME/Desktop/$suggested_name"
            "Open in Finder instead..."
            "Custom path..."
        )
    else
        mount_locations=(
            "/mnt/$suggested_name"
            "/media/$USER/$suggested_name"
            "$HOME/mnt/$suggested_name"
            "/tmp/$suggested_name (temporary)"
            "Custom path..."
        )
    fi

    local selected_option=""
    if rsr_has_fancy_terminal; then
        selected_option=$(rsr_prompt_select "Mount location" "${mount_locations[@]}")
    else
        echo ""
        for i in "${!mount_locations[@]}"; do
            echo "  $((i+1))) ${mount_locations[$i]}"
        done
        echo ""
        read -rp "Select location [1-${#mount_locations[@]}] or enter custom path: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#mount_locations[@]}" ]]; then
            selected_option="${mount_locations[$((choice-1))]}"
        else
            # Treat as custom path
            SHARE_TARGET="$choice"
            selected_option=""
        fi
    fi

    # Handle the selection
    if [[ -n "$selected_option" ]]; then
        case "$selected_option" in
            "Open in Finder instead...")
                # Use macOS native mount via Finder
                log_info "Opening share in Finder..."
                local finder_url
                if [[ -n "$SHARE_USERNAME" ]]; then
                    finder_url="smb://${SHARE_USERNAME}@$(echo "$SHARE_SOURCE" | sed 's#^//##')"
                else
                    finder_url="smb://$(echo "$SHARE_SOURCE" | sed 's#^//##')"
                fi
                open "$finder_url"
                log_ok "Share opened in Finder. Mount point will be in /Volumes/"
                exit 0
                ;;
            "Custom path...")
                read -rp "Enter custom mount path: " SHARE_TARGET
                ;;
            *)
                # Extract the path (remove description in parentheses)
                SHARE_TARGET=$(echo "$selected_option" | sed 's/ (.*)//')
                ;;
        esac
    fi

    # Expand ~ to home directory
    SHARE_TARGET="${SHARE_TARGET/#\~/$HOME}"

    echo ""

    # Optional: mount options
    if rsr_prompt_confirm "Specify mount options?" "n"; then
        log_info "Enter mount options (comma-separated):"
        read -rp "Options: " SHARE_OPTIONS
    fi

    echo ""

    # Optional: save configuration
    if rsr_prompt_confirm "Save this share configuration for future use?" "y"; then
        log_info "Enter a name for this share:"
        read -rp "Share name: " SHARE_NAME

        if rsr_prompt_confirm "Enable automount on boot?" "n"; then
            SHARE_AUTOMOUNT=true
        fi
    fi

    echo ""
    log_info "Configuration:"
    echo "  Type:       $SHARE_TYPE"
    echo "  Source:     $SHARE_SOURCE"
    echo "  Target:     $SHARE_TARGET"
    [[ -n "$SHARE_OPTIONS" ]] && echo "  Options:    $SHARE_OPTIONS"
    [[ -n "$SHARE_USERNAME" ]] && echo "  Username:   $SHARE_USERNAME"
    [[ -n "$SHARE_NAME" ]] && echo "  Save as:    $SHARE_NAME"
    echo ""

    if ! rsr_prompt_confirm "Proceed with mount?" "y"; then
        log_warn "Cancelled"
        exit 0
    fi
}

interactive_add() {
    rsr_print_header "Add Network Share"

    echo ""
    log_info "This wizard will help you save a share configuration."
    echo ""

    # Share name
    read -rp "Share name (for reference): " SHARE_NAME

    # Use mount wizard for the rest
    interactive_mount

    # Override - we're just saving, not mounting
    SUBCOMMAND="add"
}

interactive_discover() {
    rsr_print_header "Discover Network Shares"

    echo ""
    read -rp "Enter server hostname or IP: " DISCOVER_HOST

    echo ""
    log_info "Select protocols to discover:"
    local protos=("SMB (Windows shares)" "NFS (Unix exports)" "All")

    if rsr_has_fancy_terminal; then
        local selected
        selected=$(rsr_prompt_select "Protocol" "${protos[@]}")
        case "$selected" in
            "SMB"*) SHARE_TYPE="smb" ;;
            "NFS"*) SHARE_TYPE="nfs" ;;
            *) SHARE_TYPE="all" ;;
        esac
    else
        echo "  1) SMB (Windows shares)"
        echo "  2) NFS (Unix exports)"
        echo "  3) All"
        read -rp "Select [1-3]: " choice
        case "$choice" in
            1) SHARE_TYPE="smb" ;;
            2) SHARE_TYPE="nfs" ;;
            *) SHARE_TYPE="all" ;;
        esac
    fi
}

# =============================================================================
# Mount Commands
# =============================================================================

cmd_mount() {
    # If share name provided but no source, try to load saved share
    if [[ -n "$SHARE_NAME" && -z "$SHARE_SOURCE" ]]; then
        if rsr_share_load "$SHARE_NAME"; then
            SHARE_SOURCE="$RSR_LOADED_SHARE_SOURCE"
            SHARE_TARGET="$RSR_LOADED_SHARE_TARGET"
            SHARE_TYPE="$RSR_LOADED_SHARE_TYPE"
            [[ -z "$SHARE_OPTIONS" ]] && SHARE_OPTIONS="$RSR_LOADED_SHARE_OPTIONS"
            log_debug "Loaded saved share: $SHARE_NAME"
        else
            log_error "Saved share not found: $SHARE_NAME"
            exit "$RSR_EXIT_NOT_FOUND"
        fi
    fi

    # Interactive mode if no source provided
    if [[ -z "$SHARE_SOURCE" && "$INTERACTIVE" != "false" ]]; then
        interactive_mount
    fi

    # Validate required parameters
    if [[ -z "$SHARE_SOURCE" ]]; then
        log_error "Share source is required"
        echo "Usage: $0 mount <source> <target>"
        exit "$RSR_EXIT_USAGE"
    fi

    # Handle --finder/--open option (macOS only)
    if [[ "$USE_FINDER" == "true" ]]; then
        if [[ "$(rsr_detect_os)" != "darwin" ]]; then
            log_error "--finder option is only available on macOS"
            exit "$RSR_EXIT_USAGE"
        fi

        log_info "Opening share in Finder..."
        local finder_url
        if [[ -n "$SHARE_USERNAME" ]]; then
            finder_url="smb://${SHARE_USERNAME}@$(echo "$SHARE_SOURCE" | sed 's#^//##')"
        else
            finder_url="smb://$(echo "$SHARE_SOURCE" | sed 's#^//##')"
        fi
        open "$finder_url"
        log_ok "Share opened in Finder. Mount will appear in /Volumes/"
        log_info "Tip: Finder will prompt for password if needed"
        exit 0
    fi

    # Auto-generate target if not provided
    if [[ -z "$SHARE_TARGET" ]]; then
        # Extract share name from path for default mount point
        local share_basename
        share_basename=$(basename "$SHARE_SOURCE" | tr -d '\\')

        # Use /Volumes on macOS (like Finder), /mnt on Linux
        if [[ "$(rsr_detect_os)" == "darwin" ]]; then
            SHARE_TARGET="/Volumes/$share_basename"
        else
            SHARE_TARGET="/mnt/$share_basename"
        fi
        log_info "Using default mount point: $SHARE_TARGET"
    fi

    # Detect share type if not specified
    if [[ -z "$SHARE_TYPE" ]]; then
        SHARE_TYPE=$(rsr_share_detect_type "$SHARE_SOURCE") || {
            log_error "Cannot detect share type from: $SHARE_SOURCE"
            log_info "Specify type with -T/--type (smb, nfs, sshfs, webdav)"
            exit "$RSR_EXIT_USAGE"
        }
        log_debug "Detected share type: $SHARE_TYPE"
    fi

    # Validate share path format
    if ! rsr_share_validate_path "$SHARE_SOURCE" "$SHARE_TYPE"; then
        log_error "Invalid share path format for type '$SHARE_TYPE': $SHARE_SOURCE"
        exit "$RSR_EXIT_USAGE"
    fi

    # Check dependencies
    local missing
    missing=$(rsr_share_check_deps "$SHARE_TYPE")
    if [[ $? -ne 0 ]]; then
        log_error "Missing dependency: $missing"
        local install_cmd
        install_cmd=$(rsr_share_get_install_cmd "$missing")
        log_info "Install with: $install_cmd"
        exit "$RSR_EXIT_DEPENDENCY"
    fi

    # Handle credentials
    if [[ "$SHARE_TYPE" == "smb" || "$SHARE_TYPE" == "cifs" ]]; then
        # Try to load saved credentials
        if [[ -n "$SHARE_NAME" ]]; then
            rsr_share_load_credentials "$SHARE_NAME" && {
                [[ -z "$SHARE_USERNAME" ]] && SHARE_USERNAME="$RSR_SHARE_USERNAME"
                [[ -z "$SHARE_PASSWORD" ]] && SHARE_PASSWORD="$RSR_SHARE_PASSWORD"
            }
        fi

        # Try environment variables
        rsr_share_get_credentials "${SHARE_NAME:-default}"
        [[ -z "$SHARE_USERNAME" ]] && SHARE_USERNAME="$RSR_SHARE_USERNAME"
        [[ -z "$SHARE_PASSWORD" ]] && SHARE_PASSWORD="$RSR_SHARE_PASSWORD"

        # Export for mount function
        export RSR_SHARE_USERNAME="$SHARE_USERNAME"
        export RSR_SHARE_PASSWORD="$SHARE_PASSWORD"
        export RSR_SHARE_DOMAIN="$SHARE_DOMAIN"
    fi

    # Check if already mounted
    if rsr_share_is_mounted "$SHARE_TARGET"; then
        log_warn "Already mounted: $SHARE_TARGET"
        local current_mount
        current_mount=$(rsr_share_mount_info "$SHARE_TARGET")
        log_info "Current: $current_mount"

        if [[ "$SHARE_FORCE" == "true" ]] || rsr_prompt_confirm "Remount?" "n"; then
            cmd_unmount
        else
            exit 0
        fi
    fi

    # Dry run
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would mount:"
        echo "  Source: $SHARE_SOURCE"
        echo "  Target: $SHARE_TARGET"
        echo "  Type:   $SHARE_TYPE"
        [[ -n "$SHARE_OPTIONS" ]] && echo "  Options: $SHARE_OPTIONS"
        exit 0
    fi

    # Create mount point - check parent directory first
    if [[ ! -d "$SHARE_TARGET" ]]; then
        local parent_dir
        parent_dir=$(dirname "$SHARE_TARGET")
        local mount_dir
        mount_dir=$(basename "$SHARE_TARGET")

        # Check if parent directory exists
        if [[ ! -d "$parent_dir" ]]; then
            log_warn "Parent directory does not exist: $parent_dir"

            if [[ "$INTERACTIVE" != "false" ]]; then
                if rsr_prompt_confirm "Create parent directory '$parent_dir'?" "y"; then
                    log_info "Creating parent directory: $parent_dir"
                    if [[ -w "$(dirname "$parent_dir")" ]]; then
                        mkdir -p "$parent_dir" || {
                            log_info "Trying with sudo..."
                            sudo mkdir -p "$parent_dir" || {
                                log_error "Failed to create parent directory"
                                exit 1
                            }
                        }
                    else
                        sudo mkdir -p "$parent_dir" || {
                            log_error "Failed to create parent directory"
                            exit 1
                        }
                    fi
                else
                    log_error "Cannot mount without valid parent directory"
                    exit 1
                fi
            else
                # Non-interactive: auto-create with sudo
                log_info "Creating parent directory: $parent_dir"
                sudo mkdir -p "$parent_dir" || {
                    log_error "Failed to create parent directory"
                    exit 1
                }
            fi
        fi

        # Create the mount point directory itself (always auto-create)
        log_info "Creating mount point: $SHARE_TARGET"
        if [[ -w "$parent_dir" ]]; then
            mkdir -p "$SHARE_TARGET" || {
                log_info "Trying with sudo..."
                sudo mkdir -p "$SHARE_TARGET" && sudo chown "$USER" "$SHARE_TARGET" || {
                    log_error "Failed to create mount point"
                    exit 1
                }
            }
        else
            sudo mkdir -p "$SHARE_TARGET" && sudo chown "$USER" "$SHARE_TARGET" || {
                log_error "Failed to create mount point"
                exit 1
            }
        fi
    fi

    # Perform mount
    log_info "Mounting $SHARE_TYPE share..."
    log_debug "Source: $SHARE_SOURCE"
    log_debug "Target: $SHARE_TARGET"

    if rsr_share_mount "$SHARE_SOURCE" "$SHARE_TARGET" "$SHARE_OPTIONS" "$SHARE_TYPE"; then
        log_ok "Successfully mounted: $SHARE_TARGET"

        # Verify mount
        if rsr_share_is_mounted "$SHARE_TARGET"; then
            local mount_info
            mount_info=$(rsr_share_mount_info "$SHARE_TARGET")
            log_debug "Mount info: $mount_info"
        fi

        # Save configuration if requested
        if [[ -n "$SHARE_NAME" ]]; then
            rsr_share_save "$SHARE_NAME" "$SHARE_SOURCE" "$SHARE_TARGET" "$SHARE_TYPE" "$SHARE_OPTIONS" "$SHARE_AUTOMOUNT"

            # Store credentials if provided
            if [[ -n "$SHARE_USERNAME" && -n "$SHARE_PASSWORD" ]]; then
                if rsr_prompt_confirm "Save credentials for future use?" "y"; then
                    rsr_share_store_credentials "$SHARE_NAME" "$SHARE_USERNAME" "$SHARE_PASSWORD" "$SHARE_DOMAIN"
                fi
            fi
        fi
    else
        log_error "Failed to mount share"
        exit 1
    fi
}

cmd_unmount() {
    # If name provided instead of path, look up the target
    if [[ -z "$SHARE_TARGET" && -n "$SHARE_NAME" ]]; then
        if rsr_share_load "$SHARE_NAME"; then
            SHARE_TARGET="$RSR_LOADED_SHARE_TARGET"
        else
            log_error "Share not found: $SHARE_NAME"
            exit "$RSR_EXIT_NOT_FOUND"
        fi
    fi

    if [[ -z "$SHARE_TARGET" ]]; then
        log_error "Mount point or share name required"
        exit "$RSR_EXIT_USAGE"
    fi

    # Check if mounted
    if ! rsr_share_is_mounted "$SHARE_TARGET"; then
        log_warn "Not mounted: $SHARE_TARGET"
        exit 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would unmount: $SHARE_TARGET"
        exit 0
    fi

    log_info "Unmounting: $SHARE_TARGET"

    if rsr_share_unmount "$SHARE_TARGET" "$SHARE_FORCE"; then
        log_ok "Successfully unmounted: $SHARE_TARGET"
    else
        log_error "Failed to unmount. Try with --force"
        exit 1
    fi
}

cmd_remount() {
    cmd_unmount
    cmd_mount
}

# =============================================================================
# Configuration Commands
# =============================================================================

cmd_add() {
    # Interactive mode
    if [[ -z "$SHARE_NAME" && "$INTERACTIVE" != "false" ]]; then
        interactive_add
    fi

    # Validate required parameters
    if [[ -z "$SHARE_NAME" ]]; then
        log_error "Share name is required (-n/--name)"
        exit "$RSR_EXIT_USAGE"
    fi

    if [[ -z "$SHARE_SOURCE" ]]; then
        log_error "Share source is required (-s/--source)"
        exit "$RSR_EXIT_USAGE"
    fi

    if [[ -z "$SHARE_TARGET" ]]; then
        log_error "Mount target is required (-t/--target)"
        exit "$RSR_EXIT_USAGE"
    fi

    # Expand paths
    SHARE_TARGET="${SHARE_TARGET/#\~/$HOME}"

    # Auto-detect type
    if [[ -z "$SHARE_TYPE" ]]; then
        SHARE_TYPE=$(rsr_share_detect_type "$SHARE_SOURCE") || {
            log_error "Cannot detect share type"
            exit "$RSR_EXIT_USAGE"
        }
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would save share:"
        echo "  Name:     $SHARE_NAME"
        echo "  Source:   $SHARE_SOURCE"
        echo "  Target:   $SHARE_TARGET"
        echo "  Type:     $SHARE_TYPE"
        exit 0
    fi

    # Save share
    rsr_share_save "$SHARE_NAME" "$SHARE_SOURCE" "$SHARE_TARGET" "$SHARE_TYPE" "$SHARE_OPTIONS" "$SHARE_AUTOMOUNT"

    # Store credentials if provided
    if [[ -n "$SHARE_USERNAME" ]]; then
        if [[ -z "$SHARE_PASSWORD" ]]; then
            read -rsp "Password for $SHARE_USERNAME: " SHARE_PASSWORD
            echo ""
        fi
        rsr_share_store_credentials "$SHARE_NAME" "$SHARE_USERNAME" "$SHARE_PASSWORD" "$SHARE_DOMAIN"
    fi

    # Enable automount if requested
    if [[ "$SHARE_AUTOMOUNT" == "true" ]]; then
        log_info "Generating automount configuration..."
        cmd_automount_generate
    fi

    log_ok "Share '$SHARE_NAME' added successfully"
}

cmd_remove() {
    if [[ -z "$SHARE_NAME" ]]; then
        log_error "Share name is required"
        exit "$RSR_EXIT_USAGE"
    fi

    # Check if share exists
    if ! rsr_share_load "$SHARE_NAME"; then
        log_error "Share not found: $SHARE_NAME"
        exit "$RSR_EXIT_NOT_FOUND"
    fi

    # Confirm deletion
    if [[ "$RSR_YES" != "1" ]]; then
        echo "Share: $SHARE_NAME"
        echo "  Source: $RSR_LOADED_SHARE_SOURCE"
        echo "  Target: $RSR_LOADED_SHARE_TARGET"
        echo ""
        if ! rsr_prompt_confirm "Remove this share configuration?" "n"; then
            log_warn "Cancelled"
            exit 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would remove: $SHARE_NAME"
        exit 0
    fi

    # Unmount if currently mounted
    if rsr_share_is_mounted "$RSR_LOADED_SHARE_TARGET"; then
        if rsr_prompt_confirm "Share is mounted. Unmount first?" "y"; then
            SHARE_TARGET="$RSR_LOADED_SHARE_TARGET"
            cmd_unmount
        fi
    fi

    # Remove saved share
    rsr_share_delete "$SHARE_NAME"
}

cmd_show() {
    if [[ -z "$SHARE_NAME" ]]; then
        log_error "Share name is required"
        exit "$RSR_EXIT_USAGE"
    fi

    if ! rsr_share_load "$SHARE_NAME"; then
        log_error "Share not found: $SHARE_NAME"
        exit "$RSR_EXIT_NOT_FOUND"
    fi

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        if rsr_command_exists jq; then
            jq --arg name "$SHARE_NAME" '.shares[] | select(.name == $name)' "$RSR_SHARE_SAVED_FILE"
        fi
    else
        rsr_print_header "Share: $SHARE_NAME"
        echo ""
        echo "  Source:     $RSR_LOADED_SHARE_SOURCE"
        echo "  Target:     $RSR_LOADED_SHARE_TARGET"
        echo "  Type:       $RSR_LOADED_SHARE_TYPE"
        echo "  Options:    ${RSR_LOADED_SHARE_OPTIONS:-<none>}"
        echo "  Automount:  $RSR_LOADED_SHARE_AUTOMOUNT"

        # Check if credentials are stored
        if rsr_share_load_credentials "$SHARE_NAME" 2>/dev/null; then
            echo "  Credentials: stored (user: $RSR_SHARE_USERNAME)"
        else
            echo "  Credentials: not stored"
        fi

        # Check mount status
        if rsr_share_is_mounted "$RSR_LOADED_SHARE_TARGET"; then
            echo ""
            echo "  ${GREEN}● Mounted${NC}"
        else
            echo ""
            echo "  ${DIM}○ Not mounted${NC}"
        fi
    fi
}

# =============================================================================
# List Command
# =============================================================================

cmd_list() {
    local show_mounted="${LIST_MOUNTED:-false}"
    local show_saved="${LIST_SAVED:-false}"
    local show_all="${LIST_ALL:-true}"

    if [[ "$show_all" == "true" ]]; then
        show_mounted=true
        show_saved=true
    fi

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        cmd_list_json
        return
    fi

    # Show mounted shares
    if [[ "$show_mounted" == "true" ]]; then
        rsr_print_header "Mounted Network Shares"
        echo ""

        local mounted
        mounted=$(rsr_share_list_mounted)

        if [[ -n "$mounted" ]]; then
            printf "  ${BOLD}%-40s %-30s %s${NC}\n" "SOURCE" "TARGET" "TYPE"
            echo "  ────────────────────────────────────── ────────────────────────────── ──────"

            echo "$mounted" | while IFS= read -r line; do
                local source target fstype
                source=$(echo "$line" | awk '{print $1}')
                target=$(echo "$line" | awk '{print $3}')
                fstype=$(echo "$line" | awk '{print $5}' | tr -d '()')
                printf "  %-40s %-30s %s\n" "$source" "$target" "$fstype"
            done
        else
            echo "  ${DIM}No network shares currently mounted${NC}"
        fi
        echo ""
    fi

    # Show saved shares
    if [[ "$show_saved" == "true" ]]; then
        rsr_print_header "Saved Share Configurations"
        echo ""

        local saved
        saved=$(rsr_share_list_saved)

        if [[ -n "$saved" ]]; then
            printf "  ${BOLD}%-15s %-35s %-25s %-8s %s${NC}\n" "NAME" "SOURCE" "TARGET" "TYPE" "STATUS"
            echo "  ─────────────── ─────────────────────────────────── ───────────────────────── ──────── ──────"

            echo "$saved" | while IFS=$'\t' read -r name source target stype; do
                local status="${DIM}○${NC}"
                if rsr_share_is_mounted "$target" 2>/dev/null; then
                    status="${GREEN}●${NC}"
                fi
                printf "  %-15s %-35s %-25s %-8s %b\n" "$name" "$source" "$target" "$stype" "$status"
            done
        else
            echo "  ${DIM}No saved shares. Use 'add' to save a share configuration.${NC}"
        fi
        echo ""
    fi
}

cmd_list_json() {
    local result='{"mounted":[],"saved":[]}'

    if rsr_command_exists jq; then
        # Get mounted shares
        local mounted_json='[]'
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local source target fstype
            source=$(echo "$line" | awk '{print $1}')
            target=$(echo "$line" | awk '{print $3}')
            fstype=$(echo "$line" | awk '{print $5}' | tr -d '()')
            mounted_json=$(echo "$mounted_json" | jq --arg s "$source" --arg t "$target" --arg f "$fstype" \
                '. += [{"source":$s,"target":$t,"type":$f}]')
        done <<< "$(rsr_share_list_mounted)"

        # Get saved shares
        local saved_json
        saved_json=$(jq '.shares' "$RSR_SHARE_SAVED_FILE" 2>/dev/null || echo '[]')

        # Combine
        echo "{\"mounted\":$mounted_json,\"saved\":$saved_json}" | jq .
    fi
}

# =============================================================================
# Discovery Commands
# =============================================================================

cmd_discover() {
    if [[ -z "$DISCOVER_HOST" && "$INTERACTIVE" != "false" ]]; then
        interactive_discover
    fi

    if [[ -z "$DISCOVER_HOST" ]]; then
        log_error "Server hostname or IP is required"
        exit "$RSR_EXIT_USAGE"
    fi

    rsr_print_header "Discovering shares on: $DISCOVER_HOST"
    echo ""

    local discover_type="${SHARE_TYPE:-all}"

    # Discover SMB shares
    if [[ "$discover_type" == "all" || "$discover_type" == "smb" ]]; then
        log_info "SMB/CIFS Shares:"

        local smb_shares
        smb_shares=$(rsr_share_discover_smb "$DISCOVER_HOST" "$SHARE_USERNAME" 2>/dev/null)

        if [[ -n "$smb_shares" ]]; then
            echo "$smb_shares" | while IFS= read -r share; do
                echo "  //${DISCOVER_HOST}/${share}"
            done
        else
            echo "  ${DIM}No SMB shares found (or access denied)${NC}"
        fi
        echo ""
    fi

    # Discover NFS exports
    if [[ "$discover_type" == "all" || "$discover_type" == "nfs" ]]; then
        log_info "NFS Exports:"

        local nfs_exports
        nfs_exports=$(rsr_share_discover_nfs "$DISCOVER_HOST" 2>/dev/null)

        if [[ -n "$nfs_exports" ]]; then
            echo "$nfs_exports" | while IFS= read -r export; do
                echo "  ${DISCOVER_HOST}:${export}"
            done
        else
            echo "  ${DIM}No NFS exports found (or access denied)${NC}"
        fi
        echo ""
    fi
}

cmd_scan() {
    rsr_print_header "Scanning Network for File Servers"
    echo ""

    log_info "Scanning for SMB/CIFS servers..."

    local servers
    servers=$(rsr_share_scan_network "$DISCOVER_SUBNET" 2>/dev/null)

    if [[ -n "$servers" ]]; then
        log_ok "Found servers:"
        echo "$servers" | while IFS= read -r server; do
            echo "  $server"
        done

        echo ""
        log_info "Use '$0 discover <server>' to list available shares"
    else
        echo "  ${DIM}No file servers found${NC}"
    fi
}

cmd_test() {
    if [[ -z "$SHARE_SOURCE" ]]; then
        log_error "Share path is required"
        exit "$RSR_EXIT_USAGE"
    fi

    rsr_print_header "Testing Share: $SHARE_SOURCE"
    echo ""

    # Detect type
    local share_type
    share_type=$(rsr_share_detect_type "$SHARE_SOURCE") || {
        log_error "Cannot detect share type"
        exit 1
    }
    log_info "Detected type: $share_type"

    # Test connectivity
    log_info "Testing connectivity..."
    if rsr_share_test "$SHARE_SOURCE"; then
        log_ok "Server is reachable"
    else
        log_error "Server is not reachable"
        exit 1
    fi

    # Check dependencies
    log_info "Checking dependencies..."
    local missing
    local dep_result
    missing=$(rsr_share_check_deps "$share_type") && dep_result=0 || dep_result=$?
    if [[ $dep_result -eq 0 ]]; then
        log_ok "All dependencies installed"
    else
        log_warn "Missing: $missing"
        log_info "Install with: $(rsr_share_get_install_cmd "$missing")"
    fi

    echo ""
    log_ok "Share is accessible"
}

# =============================================================================
# Credential Commands
# =============================================================================

cmd_creds() {
    local subcmd="${CREDS_SUBCMD:-}"

    case "$subcmd" in
        set|add|store)
            cmd_creds_set
            ;;
        get|show)
            cmd_creds_get
            ;;
        delete|remove|rm)
            cmd_creds_delete
            ;;
        list|ls)
            cmd_creds_list
            ;;
        *)
            log_error "Unknown creds command: $subcmd"
            echo "Available: set, get, delete, list"
            exit "$RSR_EXIT_USAGE"
            ;;
    esac
}

cmd_creds_set() {
    if [[ -z "$SHARE_NAME" ]]; then
        read -rp "Share name: " SHARE_NAME
    fi

    if [[ -z "$SHARE_USERNAME" ]]; then
        read -rp "Username: " SHARE_USERNAME
    fi

    if [[ -z "$SHARE_PASSWORD" ]]; then
        read -rsp "Password: " SHARE_PASSWORD
        echo ""
    fi

    rsr_share_store_credentials "$SHARE_NAME" "$SHARE_USERNAME" "$SHARE_PASSWORD" "$SHARE_DOMAIN"
}

cmd_creds_get() {
    if [[ -z "$SHARE_NAME" ]]; then
        log_error "Share name is required"
        exit "$RSR_EXIT_USAGE"
    fi

    if rsr_share_load_credentials "$SHARE_NAME"; then
        echo "Username: $RSR_SHARE_USERNAME"
        [[ -n "$RSR_SHARE_DOMAIN" ]] && echo "Domain: $RSR_SHARE_DOMAIN"
        echo "Password: ********"
    else
        log_error "No credentials stored for: $SHARE_NAME"
        exit "$RSR_EXIT_NOT_FOUND"
    fi
}

cmd_creds_delete() {
    if [[ -z "$SHARE_NAME" ]]; then
        log_error "Share name is required"
        exit "$RSR_EXIT_USAGE"
    fi

    rsr_share_delete_credentials "$SHARE_NAME"
}

cmd_creds_list() {
    rsr_print_header "Stored Credentials"
    echo ""

    local creds
    creds=$(rsr_share_list_credentials)

    if [[ -n "$creds" ]]; then
        echo "$creds" | while IFS= read -r name; do
            if rsr_share_load_credentials "$name"; then
                printf "  %-20s user: %s\n" "$name" "$RSR_SHARE_USERNAME"
            fi
        done
    else
        echo "  ${DIM}No credentials stored${NC}"
    fi
}

# =============================================================================
# Automount Commands
# =============================================================================

cmd_automount() {
    local subcmd="${AUTOMOUNT_SUBCMD:-}"

    case "$subcmd" in
        enable)
            cmd_automount_enable
            ;;
        disable)
            cmd_automount_disable
            ;;
        generate|gen)
            cmd_automount_generate
            ;;
        status)
            cmd_automount_status
            ;;
        *)
            log_error "Unknown automount command: $subcmd"
            echo "Available: enable, disable, generate, status"
            exit "$RSR_EXIT_USAGE"
            ;;
    esac
}

cmd_automount_generate() {
    if [[ -z "$SHARE_NAME" ]]; then
        log_error "Share name is required"
        exit "$RSR_EXIT_USAGE"
    fi

    if ! rsr_share_load "$SHARE_NAME"; then
        log_error "Share not found: $SHARE_NAME"
        exit "$RSR_EXIT_NOT_FOUND"
    fi

    # Determine method
    local method="${AUTOMOUNT_METHOD:-}"

    if [[ -z "$method" ]]; then
        if [[ "$INTERACTIVE" != "false" ]]; then
            rsr_print_header "Select Automount Method"
            echo ""

            local methods=()
            local method_names=()

            # Detect available methods
            if [[ -f /etc/fstab ]]; then
                methods+=("fstab")
                method_names+=("fstab - Traditional mount table")
            fi

            if rsr_command_exists systemctl; then
                methods+=("systemd")
                method_names+=("systemd - Modern mount unit (recommended)")
            fi

            if [[ -f /etc/auto.master ]] || rsr_command_exists automount; then
                methods+=("autofs")
                method_names+=("autofs - On-demand mounting")
            fi

            if [[ ${#methods[@]} -eq 0 ]]; then
                log_error "No automount methods available"
                exit 1
            fi

            if rsr_has_fancy_terminal && [[ ${#methods[@]} -gt 1 ]]; then
                local selected
                selected=$(rsr_prompt_select "Method" "${method_names[@]}")
                method=$(echo "$selected" | cut -d' ' -f1)
            else
                echo "Available methods:"
                for i in "${!method_names[@]}"; do
                    echo "  $((i+1))) ${method_names[$i]}"
                done
                read -rp "Select method [1-${#methods[@]}]: " choice
                method="${methods[$((choice-1))]}"
            fi
        else
            # Default to fstab
            method="fstab"
        fi
    fi

    echo ""

    case "$method" in
        fstab)
            rsr_print_header "fstab Entry"
            echo ""
            echo "Add to /etc/fstab:"
            echo ""
            rsr_share_generate_fstab "$SHARE_NAME"
            echo ""
            log_info "To apply: sudo mount -a"
            ;;
        systemd)
            rsr_print_header "systemd Mount Unit"
            echo ""
            local unit_name
            unit_name=$(echo "$RSR_LOADED_SHARE_TARGET" | sed 's#^/##; s#/#-#g')
            echo "Save to: /etc/systemd/system/${unit_name}.mount"
            echo ""
            rsr_share_generate_systemd "$SHARE_NAME"
            echo ""
            log_info "To enable: sudo systemctl enable --now ${unit_name}.mount"
            ;;
        autofs)
            rsr_print_header "autofs Configuration"
            echo ""
            rsr_share_generate_autofs "$SHARE_NAME"
            echo ""
            log_info "To apply: sudo systemctl restart autofs"
            ;;
    esac
}

cmd_automount_enable() {
    if [[ -z "$SHARE_NAME" ]]; then
        log_error "Share name is required"
        exit "$RSR_EXIT_USAGE"
    fi

    # Update share to enable automount
    if rsr_share_load "$SHARE_NAME"; then
        SHARE_SOURCE="$RSR_LOADED_SHARE_SOURCE"
        SHARE_TARGET="$RSR_LOADED_SHARE_TARGET"
        SHARE_TYPE="$RSR_LOADED_SHARE_TYPE"
        SHARE_OPTIONS="$RSR_LOADED_SHARE_OPTIONS"
        SHARE_AUTOMOUNT=true

        rsr_share_save "$SHARE_NAME" "$SHARE_SOURCE" "$SHARE_TARGET" "$SHARE_TYPE" "$SHARE_OPTIONS" "$SHARE_AUTOMOUNT"
        log_ok "Automount enabled for: $SHARE_NAME"

        # Generate config
        cmd_automount_generate
    else
        log_error "Share not found: $SHARE_NAME"
        exit "$RSR_EXIT_NOT_FOUND"
    fi
}

cmd_automount_disable() {
    if [[ -z "$SHARE_NAME" ]]; then
        log_error "Share name is required"
        exit "$RSR_EXIT_USAGE"
    fi

    if rsr_share_load "$SHARE_NAME"; then
        SHARE_SOURCE="$RSR_LOADED_SHARE_SOURCE"
        SHARE_TARGET="$RSR_LOADED_SHARE_TARGET"
        SHARE_TYPE="$RSR_LOADED_SHARE_TYPE"
        SHARE_OPTIONS="$RSR_LOADED_SHARE_OPTIONS"
        SHARE_AUTOMOUNT=false

        rsr_share_save "$SHARE_NAME" "$SHARE_SOURCE" "$SHARE_TARGET" "$SHARE_TYPE" "$SHARE_OPTIONS" "$SHARE_AUTOMOUNT"
        log_ok "Automount disabled for: $SHARE_NAME"
        log_info "Remember to remove entries from fstab/systemd/autofs manually"
    else
        log_error "Share not found: $SHARE_NAME"
        exit "$RSR_EXIT_NOT_FOUND"
    fi
}

cmd_automount_status() {
    rsr_print_header "Automount Status"
    echo ""

    local shares
    shares=$(rsr_share_list_saved)

    if [[ -z "$shares" ]]; then
        echo "  ${DIM}No saved shares${NC}"
        return
    fi

    printf "  ${BOLD}%-15s %-10s %-10s %s${NC}\n" "SHARE" "AUTOMOUNT" "MOUNTED" "TARGET"
    echo "  ─────────────── ────────── ────────── ──────────────────────"

    echo "$shares" | while IFS=$'\t' read -r name source target stype; do
        if rsr_share_load "$name"; then
            local automount_status="disabled"
            local mount_status="no"

            [[ "$RSR_LOADED_SHARE_AUTOMOUNT" == "true" ]] && automount_status="enabled"
            rsr_share_is_mounted "$target" 2>/dev/null && mount_status="yes"

            printf "  %-15s %-10s %-10s %s\n" "$name" "$automount_status" "$mount_status" "$target"
        fi
    done
}

# =============================================================================
# Status Commands
# =============================================================================

cmd_status() {
    rsr_print_header "Network Share Status"

    cmd_list
}

cmd_health() {
    rsr_print_header "Share Health Check"
    echo ""

    local shares
    shares=$(rsr_share_list_saved)

    if [[ -z "$shares" ]]; then
        echo "  ${DIM}No saved shares to check${NC}"
        return
    fi

    echo "$shares" | while IFS=$'\t' read -r name source target stype; do
        printf "  Checking %-15s " "$name"

        # Check if mounted
        if rsr_share_is_mounted "$target" 2>/dev/null; then
            # Check if accessible
            if [[ -d "$target" ]] && ls "$target" >/dev/null 2>&1; then
                echo "${GREEN}● Healthy${NC}"
            else
                echo "${YELLOW}⚠ Mounted but not accessible${NC}"
            fi
        else
            # Check if server is reachable
            if rsr_share_test "$source" 2>/dev/null; then
                echo "${DIM}○ Not mounted (server reachable)${NC}"
            else
                echo "${RED}✗ Not mounted (server unreachable)${NC}"
            fi
        fi
    done
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    # Initialize shares module
    rsr_shares_init

    parse_args "$@"

    # Default to list if no subcommand
    [[ -z "$SUBCOMMAND" ]] && SUBCOMMAND="list"

    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Command: $SUBCOMMAND"
        log_debug "Share: $SHARE_NAME"
        log_debug "Source: $SHARE_SOURCE"
        log_debug "Target: $SHARE_TARGET"
    fi

    case "$SUBCOMMAND" in
        mount)
            cmd_mount
            ;;
        unmount|umount)
            cmd_unmount
            ;;
        remount)
            cmd_remount
            ;;
        add)
            cmd_add
            ;;
        remove|rm|delete)
            cmd_remove
            ;;
        show|info)
            cmd_show
            ;;
        list|ls)
            cmd_list
            ;;
        discover)
            cmd_discover
            ;;
        scan)
            cmd_scan
            ;;
        test|check)
            cmd_test
            ;;
        creds|credentials)
            cmd_creds
            ;;
        automount|auto)
            cmd_automount
            ;;
        status)
            cmd_status
            ;;
        health)
            cmd_health
            ;;
        help)
            show_help
            ;;
        *)
            log_error "Unknown command: $SUBCOMMAND"
            echo "Use --help for usage information."
            exit "$RSR_EXIT_USAGE"
            ;;
    esac
}

# Run main
main "$@"

