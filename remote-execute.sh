#!/usr/bin/env bash

# Remote Execute Wrapper
# This script can be downloaded and executed via HTTPS
# Usage: curl -fsSL https://example.com/remote-execute.sh | bash -s -- [OPTIONS]

set -euo pipefail

# Configuration
SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/yourusername/remote-script-runner/main/remote-runner.sh}"
SCRIPT_VERSION="1.0.0"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to download and execute the main script
run_remote_script() {
    local temp_dir
    temp_dir=$(mktemp -d)
    local script_path="${temp_dir}/remote-runner.sh"
    
    print_color "${BLUE}" "Downloading remote-runner script..."
    
    # Download the script
    if command -v curl &> /dev/null; then
        curl -fsSL "${SCRIPT_URL}" -o "${script_path}"
    elif command -v wget &> /dev/null; then
        wget -qO "${script_path}" "${SCRIPT_URL}"
    else
        print_color "${RED}" "Error: Neither curl nor wget is available"
        exit 1
    fi
    
    # Make it executable
    chmod +x "${script_path}"
    
    # Execute with all passed arguments
    print_color "${GREEN}" "Executing remote-runner with provided arguments..."
    "${script_path}" "$@"
    
    # Cleanup
    rm -rf "${temp_dir}"
}

# Show usage if no arguments
if [ $# -eq 0 ]; then
    cat << EOF
Remote Execute Wrapper v${SCRIPT_VERSION}

This script downloads and executes the remote-runner.sh script.

USAGE:
    curl -fsSL https://example.com/remote-execute.sh | bash -s -- [REMOTE-RUNNER OPTIONS]

EXAMPLES:
    # Execute a command on remote host
    curl -fsSL https://example.com/remote-execute.sh | bash -s -- -h server.example.com -c "uptime"
    
    # Execute with SSH key and custom port
    curl -fsSL https://example.com/remote-execute.sh | bash -s -- -h localhost -p 2222 -c "hostname"
    
    # Execute a local script remotely
    curl -fsSL https://example.com/remote-execute.sh | bash -s -- -h server.example.com -f ./deploy.sh

ENVIRONMENT VARIABLES:
    SCRIPT_URL    URL to download remote-runner.sh from (optional)

EOF
    exit 0
fi

# Run the main function
run_remote_script "$@"
