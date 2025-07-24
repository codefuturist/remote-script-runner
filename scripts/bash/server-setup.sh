#!/bin/bash

# Server Setup Script
# Example: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/server-setup.sh)" -- -u admin -p production -i nginx docker

set -euo pipefail

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

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${BLUE}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "OK")    echo -e "${GREEN}[OK]${NC} $message" ;;
        *)       echo "[$level] $message" ;;
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
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -u|--username)
            USERNAME="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -i|--install)
            INSTALL_PACKAGES+=("$2")
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
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


# Validation
if [[ -z "$USERNAME" ]]; then
    log "ERROR" "Username is required. Use -u or --username"
    exit 1
fi

if [[ "$PROFILE" != "development" && "$PROFILE" != "production" ]]; then
    log "ERROR" "Profile must be 'development' or 'production'"
    exit 1
fi

if [[ ${#INSTALL_PACKAGES[@]} -eq 0 ]]; then
    log "ERROR" "At least one package must be specified"
    exit 1
fi

# Main execution
log "INFO" "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
[[ "$DRY_RUN" == true ]] && log "INFO" "DRY RUN MODE - No changes will be made"
[[ "$VERBOSE" == true ]] && log "INFO" "Verbose mode enabled"

log "INFO" "Configuration:"
log "INFO" "  Username: $USERNAME"
log "INFO" "  Profile: $PROFILE"
log "INFO" "  Packages: ${INSTALL_PACKAGES[*]}"

# Configure user
configure_user "$USERNAME"

# Apply profile
apply_profile "$PROFILE"

# Install packages
log "INFO" "Installing ${#INSTALL_PACKAGES[@]} packages..."
for package in "${INSTALL_PACKAGES[@]}"; do
    install_package "$package"
done

# Final summary
log "OK" "Server setup completed successfully!"
log "INFO" "Summary:"
log "INFO" "  User '$USERNAME' configured"
log "INFO" "  Profile '$PROFILE' applied" 
log "INFO" "  ${#INSTALL_PACKAGES[@]} packages installed: ${INSTALL_PACKAGES[*]}"

if [[ "$DRY_RUN" == true ]]; then
    log "INFO" "This was a dry run. Run without -d flag to apply changes."
fi
