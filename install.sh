#!/bin/bash
# Remote Script Runner - One-Line Installer
# Usage: curl -fsSL https://codefuturist.github.io/remote-script-runner/install.sh | bash
# Or with arguments: curl -fsSL https://codefuturist.github.io/remote-script-runner/install.sh | bash -s -- [install|run] [options]

set -euo pipefail

# Configuration
REPO_BASE_URL="https://codefuturist.github.io/remote-script-runner"
INSTALL_DIR="${HOME}/.local/bin"
SCRIPT_NAME="remote-runner"

# Color codes
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    NC=''
fi

# Function to install the remote runner
install_runner() {
    echo -e "${BLUE}Installing Remote Script Runner...${NC}"
    
    # Create install directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"
    
    # Download the remote-runner script
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$REPO_BASE_URL/remote-runner.sh" -o "$INSTALL_DIR/$SCRIPT_NAME"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$INSTALL_DIR/$SCRIPT_NAME" "$REPO_BASE_URL/remote-runner.sh"
    else
        echo -e "${RED}Error: Neither curl nor wget is available${NC}"
        exit 1
    fi
    
    # Make it executable
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    
    echo -e "${GREEN}✓ Remote Script Runner installed to: $INSTALL_DIR/$SCRIPT_NAME${NC}"
    
    # Check if install directory is in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo -e "${YELLOW}Note: $INSTALL_DIR is not in your PATH${NC}"
        echo -e "${YELLOW}Add it to your PATH by adding this line to your shell config:${NC}"
        echo -e "${YELLOW}  export PATH=\"\$PATH:$INSTALL_DIR\"${NC}"
        echo
        echo -e "${GREEN}Or run directly with: $INSTALL_DIR/$SCRIPT_NAME${NC}"
    else
        echo -e "${GREEN}You can now use: $SCRIPT_NAME${NC}"
    fi
    
    echo
    echo -e "${GREEN}Examples:${NC}"
    echo "  $SCRIPT_NAME health -a              # Run all health checks"
    echo "  $SCRIPT_NAME setup -h               # Show server setup help"
    echo "  $SCRIPT_NAME health -s cpu memory   # Check CPU and memory"
}

# Function to run directly without installing
run_direct() {
    # Download and execute remote-runner with passed arguments
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$REPO_BASE_URL/remote-runner.sh" | bash -s -- "$@"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$REPO_BASE_URL/remote-runner.sh" | bash -s -- "$@"
    else
        echo -e "${RED}Error: Neither curl nor wget is available${NC}"
        exit 1
    fi
}

# Main logic
if [ $# -eq 0 ]; then
    # No arguments - default to install
    install_runner
else
    case "$1" in
        install)
            install_runner
            ;;
        run)
            shift
            run_direct "$@"
            ;;
        *)
            # Pass all arguments to remote-runner
            run_direct "$@"
            ;;
    esac
fi
