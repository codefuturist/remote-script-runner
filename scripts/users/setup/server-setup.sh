#!/bin/bash
# =============================================================================
# @id           setup
# @name         server-setup
# @displayName  Server Setup
# @description  Initial server setup: users, SSH hardening, firewall, common tools
# @category     setup
# @version      1.0.0
# @author       codefuturist
# @tags         setup,server,users,ssh,firewall,tools,initialization
# @shells       bash
# =============================================================================

# Server Setup Script
# Example: /bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/server-setup.sh)" -- -u admin -p production -i nginx docker

set -eo pipefail

# =============================================================================
# Load RSR Library
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [ -n "${SCRIPT_SOURCE}" ] && [ "${SCRIPT_SOURCE}" != "bash" ] && [ "${SCRIPT_SOURCE}" != "sh" ] && [ "${SCRIPT_SOURCE}" != "-bash" ] && [ "${SCRIPT_SOURCE}" != "-sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" users validate
fi

# Script metadata
SCRIPT_NAME="Server Setup"
SCRIPT_VERSION="1.0.0"

# Default values
USERNAME=""
PASSWORD=""
PROFILE="development"
INSTALL_PACKAGES=()
DRY_RUN=false
VERBOSE=false
INTERACTIVE=auto
RSR_YES=0

# Color codes (from RSR library or fallback)
RED="${RSR_COLOR_RED:-\033[0;31m}"
GREEN="${RSR_COLOR_GREEN:-\033[0;32m}"
YELLOW="${RSR_COLOR_YELLOW:-\033[1;33m}"
BLUE="${RSR_COLOR_BLUE:-\033[0;34m}"
CYAN="${RSR_COLOR_CYAN:-\033[0;36m}"
DIM="${RSR_COLOR_DIM:-\033[2m}"
BOLD="${RSR_COLOR_BOLD:-\033[1m}"
NC="${RSR_COLOR_RESET:-\033[0m}"

# Available packages
AVAILABLE_PACKAGES=("nginx" "docker" "nodejs" "python3" "git" "curl" "vim" "htop" "fail2ban")

# Function to display usage
usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

Usage: $0 [OPTIONS] [PACKAGES...]

OPTIONS:
    -h, --help                Display this help message
    -u, --username USERNAME   Set username for configuration
    -p, --profile PROFILE     Environment profile (development|production) [default: development]
    -i, --install PACKAGES    Packages to install (can be used multiple times)
    --interactive             Run in interactive mode (default when no args)
    --no-interactive          Disable interactive mode
    -y, --yes                 Auto-confirm all prompts
    -d, --dry-run            Show what would be done without executing
    -v, --verbose            Enable verbose output

AVAILABLE PACKAGES:
    nginx       Web server
    docker      Container platform
    nodejs      JavaScript runtime
    python3     Python programming language
    git         Version control system
    curl        Command line HTTP client
    vim         Text editor
    htop        Process monitor
    fail2ban    Intrusion prevention

EXAMPLES:
    # Basic setup with nginx and docker
    $0 -u admin -p production -i nginx -i docker

    # Development setup with multiple packages
    $0 -u dev -p development nginx nodejs git vim htop

    # Dry run to see what would be installed
    $0 -d -u admin -p production -i nginx -i docker

EOF
}

# Function to log messages
log() {
    local level="$1"
    local message="$2"

    if type rsr_log_info &>/dev/null; then
        case "$level" in
            "INFO") rsr_log_info "$message" ;;
            "WARN") rsr_log_warn "$message" ;;
            "ERROR") rsr_log_error "$message" ;;
            "OK") rsr_log_ok "$message" ;;
            *) echo "[$level] $message" ;;
        esac
    else
        case "$level" in
            "INFO") echo -e "${BLUE}▸${NC} $message" ;;
            "WARN") echo -e "${YELLOW}⚠${NC} $message" ;;
            "ERROR") echo -e "${RED}✗${NC} $message" >&2 ;;
        "OK") echo -e "${GREEN}✓${NC} $message" ;;
        *) echo "[$level] $message" ;;
    esac
}

# Function to check if package is available
is_package_available() {
    local package="$1"
    for available in "${AVAILABLE_PACKAGES[@]}"; do
        if [[ "$available" == "$package" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to simulate package installation
install_package() {
    local package="$1"

    if ! is_package_available "$package"; then
        log "ERROR" "Package '$package' is not available"
        return 1
    fi

    log "INFO" "Installing $package..."

    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY RUN] Would install: $package"
        return 0
    fi

    # Simulate installation time
    sleep 1

    case "$package" in
        nginx)
            log "OK" "nginx installed successfully"
            [[ "$VERBOSE" == true ]] && log "INFO" "Service nginx would be started and enabled"
            ;;
        docker)
            log "OK" "docker installed successfully"
            [[ "$VERBOSE" == true ]] && log "INFO" "User $USERNAME would be added to docker group"
            ;;
        nodejs)
            log "OK" "nodejs installed successfully"
            [[ "$VERBOSE" == true ]] && log "INFO" "npm is included with nodejs"
            ;;
        python3)
            log "OK" "python3 installed successfully"
            [[ "$VERBOSE" == true ]] && log "INFO" "pip3 is included with python3"
            ;;
        *)
            log "OK" "$package installed successfully"
            ;;
    esac
}

# Function to configure user
configure_user() {
    local username="$1"

    log "INFO" "Configuring user: $username"

    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY RUN] Would configure user: $username"
        return 0
    fi

    # Simulate user configuration
    sleep 0.5
    log "OK" "User $username configured successfully"

    if [[ "$VERBOSE" == true ]]; then
        log "INFO" "Created ~/.bashrc configuration"
        log "INFO" "Set up SSH key authentication"
        log "INFO" "Added user to sudo group"
    fi
}

# Function to apply profile-specific configurations
apply_profile() {
    local profile="$1"

    log "INFO" "Applying $profile profile..."

    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY RUN] Would apply profile: $profile"
        return 0
    fi

    case "$profile" in
        development)
            log "OK" "Development profile applied"
            [[ "$VERBOSE" == true ]] && log "INFO" "Enabled debug logging and development tools"
            ;;
        production)
            log "OK" "Production profile applied"
            [[ "$VERBOSE" == true ]] && log "INFO" "Enabled security hardening and monitoring"
            ;;
        *)
            log "WARN" "Unknown profile: $profile. Using defaults."
            ;;
    esac
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h | --help)
                usage
                exit 0
                ;;
            -u | --username)
                USERNAME="$2"
                shift 2
                ;;
            -p | --profile)
                PROFILE="$2"
                shift 2
                ;;
            -i | --install)
                INSTALL_PACKAGES+=("$2")
                shift 2
                ;;
            --interactive)
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
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            -*)
                echo "Unknown option $1"
                exit 1
                ;;
            *)
                INSTALL_PACKAGES+=("$1")
                shift
                ;;
        esac
    done
}

# =============================================================================
# Interactive Mode
# =============================================================================

run_interactive() {
    print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"

    echo ""
    echo -e "${DIM}This wizard will guide you through initial server setup.${NC}"
    echo ""

    # Username configuration
    USERNAME=$(prompt_input "Enter admin username" "admin")

    echo ""

    # Profile selection
    local profile_choice
    profile_choice=$(prompt_select "Select environment profile:" \
        "Development (debug logging, dev tools)" \
        "Production (security hardening, monitoring)")

    case "$profile_choice" in
        "Development"*) PROFILE="development" ;;
        "Production"*) PROFILE="production" ;;
    esac

    echo ""

    # Package selection - using multiselect
    log "INFO" "Select packages to install:"
    echo ""

    local selected_packages
    selected_packages=$(prompt_multiselect "Available packages:" \
        "nginx - Web server" \
        "docker - Container platform" \
        "nodejs - JavaScript runtime" \
        "python3 - Python programming" \
        "git - Version control" \
        "curl - HTTP client" \
        "vim - Text editor" \
        "htop - Process monitor" \
        "fail2ban - Intrusion prevention")

    INSTALL_PACKAGES=()
    [[ "$selected_packages" == *"nginx"* ]] && INSTALL_PACKAGES+=("nginx")
    [[ "$selected_packages" == *"docker"* ]] && INSTALL_PACKAGES+=("docker")
    [[ "$selected_packages" == *"nodejs"* ]] && INSTALL_PACKAGES+=("nodejs")
    [[ "$selected_packages" == *"python3"* ]] && INSTALL_PACKAGES+=("python3")
    [[ "$selected_packages" == *"git"* ]] && INSTALL_PACKAGES+=("git")
    [[ "$selected_packages" == *"curl"* ]] && INSTALL_PACKAGES+=("curl")
    [[ "$selected_packages" == *"vim"* ]] && INSTALL_PACKAGES+=("vim")
    [[ "$selected_packages" == *"htop"* ]] && INSTALL_PACKAGES+=("htop")
    [[ "$selected_packages" == *"fail2ban"* ]] && INSTALL_PACKAGES+=("fail2ban")

    if [[ ${#INSTALL_PACKAGES[@]} -eq 0 ]]; then
        log "WARN" "No packages selected"
        echo ""
        if ! prompt_yes_no "Continue without installing packages?" "n"; then
            log "INFO" "Setup cancelled"
            exit 0
        fi
    fi

    echo ""

    # Additional options
    if prompt_yes_no "Enable verbose output?" "n"; then
        VERBOSE=true
    fi

    echo ""

    # Dry run option
    if prompt_yes_no "Perform a dry run first?" "y"; then
        DRY_RUN=true
    fi

    # Summary
    echo ""
    log "INFO" "Setup configuration:"
    echo -e "  ${CYAN}•${NC} Username: $USERNAME"
    echo -e "  ${CYAN}•${NC} Profile: $PROFILE"
    if [[ ${#INSTALL_PACKAGES[@]} -gt 0 ]]; then
        echo -e "  ${CYAN}•${NC} Packages: ${INSTALL_PACKAGES[*]}"
    else
        echo -e "  ${CYAN}•${NC} Packages: (none)"
    fi
    [[ "$DRY_RUN" == "true" ]] && echo -e "  ${CYAN}•${NC} Mode: Dry run"
    echo ""

    if confirm_destructive "This will configure the server"; then
        return 0
    else
        log "INFO" "Setup cancelled"
        exit 0
    fi
}

# Main function
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
    fi

    # Validation (only if not from interactive mode which already validated)
    if [[ -z "$USERNAME" ]]; then
        log "ERROR" "Username is required. Use -u or --username"
        exit 1
    fi

    if [[ "$PROFILE" != "development" && "$PROFILE" != "production" ]]; then
        log "ERROR" "Profile must be 'development' or 'production'"
        exit 1
    fi

    # Allow running without packages in interactive mode
    if [[ ${#INSTALL_PACKAGES[@]} -eq 0 && "$INTERACTIVE" != "true" ]]; then
        log "ERROR" "At least one package must be specified"
        exit 1
    fi

    # Main execution
    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo ""

    [[ "$DRY_RUN" == true ]] && log "INFO" "DRY RUN MODE - No changes will be made"
    [[ "$VERBOSE" == true ]] && log "INFO" "Verbose mode enabled"

    log "INFO" "Configuration:"
    echo -e "  ${CYAN}•${NC} Username: $USERNAME"
    echo -e "  ${CYAN}•${NC} Profile: $PROFILE"
    [[ ${#INSTALL_PACKAGES[@]} -gt 0 ]] && echo -e "  ${CYAN}•${NC} Packages: ${INSTALL_PACKAGES[*]}"
    echo ""

    # Configure user
    configure_user "$USERNAME"

    # Apply profile
    apply_profile "$PROFILE"

    # Install packages
    if [[ ${#INSTALL_PACKAGES[@]} -gt 0 ]]; then
        log "INFO" "Installing ${#INSTALL_PACKAGES[@]} packages..."
        for package in "${INSTALL_PACKAGES[@]}"; do
            install_package "$package"
        done
    fi

    # Final summary
    echo ""
    log "OK" "Server setup completed successfully!"
    log "INFO" "Summary:"
    echo -e "  ${CYAN}•${NC} User '$USERNAME' configured"
    echo -e "  ${CYAN}•${NC} Profile '$PROFILE' applied"
    [[ ${#INSTALL_PACKAGES[@]} -gt 0 ]] && echo -e "  ${CYAN}•${NC} ${#INSTALL_PACKAGES[@]} packages installed: ${INSTALL_PACKAGES[*]}"

    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        log "INFO" "This was a dry run. Run without -d flag to apply changes."
    fi
}

main "$@"
