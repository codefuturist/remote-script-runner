#!/bin/bash
# Standalone Remote Script Runner
# Can be downloaded and run without cloning the repository
# Usage: curl -fsSL https://scripts.pandia.io/remote-runner.sh | bash -s -- [COMMAND] [OPTIONS]

set -euo pipefail

# Configuration
REPO_BASE_URL="https://scripts.pandia.io"
SCRIPT_VERSION="1.0.0"

# Color codes
if [ -t 1 ]; then
    BLUE='\033[0;34m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m' # No Color
else
    BLUE=''
    GREEN=''
    YELLOW=''
    RED=''
    NC=''
fi

# Function to show header
show_header() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}     ${GREEN}Remote Script Runner${NC}          ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}        Version $SCRIPT_VERSION              ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo
}

# Function to show help
show_help() {
    show_header
    cat << EOF
${YELLOW}Usage:${NC} $(basename "$0") [COMMAND] [OPTIONS]

${GREEN}Commands:${NC}
  health       Run system health checks
  setup        Perform server setup
  health-help  Show health check script help
  setup-help   Show server setup script help

${GREEN}Examples:${NC}
  # Run all health checks
  $(basename "$0") health -a
  
  # Run specific health checks
  $(basename "$0") health -v -s cpu -s memory -s disk
  
  # Dry run server setup
  $(basename "$0") setup -d -u admin -p production nginx docker
  
  # Show help for health check
  $(basename "$0") health-help

${GREEN}Remote Usage (without downloading):${NC}
  # Run directly via curl
  curl -fsSL $REPO_BASE_URL/remote-runner.sh | bash -s -- health -a
  
  # Server setup via curl
  curl -fsSL $REPO_BASE_URL/remote-runner.sh | bash -s -- setup -d -u admin -p production nginx

${GREEN}Download and Run:${NC}
  # Download once and reuse
  curl -fsSL $REPO_BASE_URL/remote-runner.sh -o remote-runner.sh
  chmod +x remote-runner.sh
  ./remote-runner.sh health -a
EOF
}

# Function to run remote script
run_remote_script() {
    local script_url="$1"
    shift
    
    echo -e "${BLUE}Downloading and executing script...${NC}"
    
    # Download and execute in one step
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$script_url" | bash -s -- "$@"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$script_url" | bash -s -- "$@"
    else
        echo -e "${RED}Error: Neither curl nor wget is available${NC}"
        exit 1
    fi
}

# Main logic
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

COMMAND="$1"
shift

case "$COMMAND" in
    health)
        run_remote_script "$REPO_BASE_URL/system-health-check.sh" "$@"
        ;;
    setup)
        run_remote_script "$REPO_BASE_URL/server-setup.sh" "$@"
        ;;
    health-help)
        run_remote_script "$REPO_BASE_URL/system-health-check.sh" "-h"
        ;;
    setup-help)
        run_remote_script "$REPO_BASE_URL/server-setup.sh" "-h"
        ;;
    -h|--help|help)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        echo
        show_help
        exit 1
        ;;
esac
