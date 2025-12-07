#!/bin/bash
# DEPRECATED: Use 'rsr' instead. This file will be removed in v2.0.0
# User-friendly script runner for remote-script-runner project
# Provides both CLI and interactive menu interfaces
#
# Migration: Replace './run-script.sh' with './rsr'

echo "⚠️  DEPRECATED: 'run-script.sh' is deprecated. Use 'rsr' instead." >&2
echo "   Example: ./rsr health -a" >&2
echo "" >&2

set -euo pipefail

# Script information
SCRIPT_NAME="Remote Script Runner CLI"
SCRIPT_VERSION="1.0.0"

# Color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to show header
show_header() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}     ${GREEN}$SCRIPT_NAME${NC}      ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}          Version $SCRIPT_VERSION            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo
}

# Function to show usage
show_help() {
    show_header
    cat << EOF
${YELLOW}Usage:${NC} $(basename "$0") [COMMAND] [OPTIONS]

${GREEN}Commands:${NC}
  health-check    Run system health checks
  server-setup    Perform server setup
  menu            Show interactive menu (default if no args)

${GREEN}Options:${NC}
  -h, --help      Show this help message
  [SCRIPT OPTIONS] Options specific to the chosen command

${GREEN}Examples:${NC}
  # Run health check with specific checks
  $(basename "$0") health-check -v -s cpu -s memory -s disk
  
  # Run all health checks
  $(basename "$0") health-check -a
  
  # Dry run server setup
  $(basename "$0") server-setup -d -u admin -p production -i nginx
  
  # Interactive menu
  $(basename "$0") menu
  
${GREEN}Quick Commands:${NC}
  # Check system health (all checks)
  $(basename "$0") health-check -a
  
  # Quick CPU and memory check
  $(basename "$0") health-check -s cpu -s memory
  
  # Server setup help
  $(basename "$0") server-setup -h
EOF
}

# Function to show interactive menu
show_menu() {
    show_header
    echo -e "${GREEN}Select an option:${NC}"
    echo
    echo "  1) System Health Check - All checks"
    echo "  2) System Health Check - Custom selection"
    echo "  3) Server Setup - Interactive configuration"
    echo "  4) Server Setup - Dry run example"
    echo "  5) Show script help"
    echo "  6) Exit"
    echo
    read -p "Enter your choice [1-6]: " choice
    
    case $choice in
        1)
            echo -e "\n${BLUE}Running all system health checks...${NC}\n"
            ./system-health-check.sh -a
            ;;
        2)
            echo -e "\n${YELLOW}Available checks:${NC} cpu, memory, disk, network, services, uptime"
            read -p "Enter checks to run (space-separated): " checks
            echo -e "\n${BLUE}Running selected health checks...${NC}\n"
            # Convert space-separated checks to -s arguments
            check_args=""
            for check in $checks; do
                check_args="$check_args -s $check"
            done
            ./system-health-check.sh -v $check_args
            ;;
        3)
            echo -e "\n${GREEN}Server Setup Configuration${NC}"
            read -p "Enter username: " username
            echo "Select profile:"
            echo "  1) development"
            echo "  2) production"
            read -p "Enter choice [1-2]: " profile_choice
            profile=$([ "$profile_choice" = "2" ] && echo "production" || echo "development")
            
            echo -e "\n${YELLOW}Available packages:${NC} nginx docker nodejs python3 git curl vim htop fail2ban"
            read -p "Enter packages to install (space-separated): " packages
            
            read -p "Run in dry-run mode? [Y/n]: " dry_run
            dry_run_flag=$([ "${dry_run,,}" != "n" ] && echo "-d" || echo "")
            
            echo -e "\n${BLUE}Running server setup...${NC}\n"
            ./server-setup.sh $dry_run_flag -v -u "$username" -p "$profile" $packages
            ;;
        4)
            echo -e "\n${BLUE}Running server setup dry-run example...${NC}\n"
            ./server-setup.sh -d -v -u demo -p development nginx git vim
            ;;
        5)
            ./system-health-check.sh -h
            echo
            echo -e "${YELLOW}Press Enter to see server-setup help...${NC}"
            read
            ./server-setup.sh -h
            ;;
        6)
            echo -e "\n${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}Invalid option. Please try again.${NC}"
            sleep 2
            show_menu
            ;;
    esac
    
    echo
    echo -e "${YELLOW}Press Enter to return to menu or Ctrl+C to exit...${NC}"
    read
    show_menu
}

# Main script logic
if [[ $# -eq 0 ]]; then
    # No arguments, show interactive menu
    show_menu
else
    # Process command line arguments
    COMMAND="$1"
    shift
    
    case "$COMMAND" in
        health-check)
            ./system-health-check.sh "$@"
            ;;
        server-setup)
            ./server-setup.sh "$@"
            ;;
        menu)
            show_menu
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $COMMAND${NC}"
            echo
            show_help
            exit 1
            ;;
    esac
fi

