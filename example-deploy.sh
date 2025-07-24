#!/usr/bin/env bash

# Example deployment script for demonstrating remote execution
# This script simulates a typical deployment workflow

set -euo pipefail

# Script configuration
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_VERSION="1.0.0"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
APP_NAME="myapp"
ENVIRONMENT="development"
BRANCH="main"
VERBOSE=false
DRY_RUN=false

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to log messages
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case ${level} in
        ERROR)
            print_color "${RED}" "[${timestamp}] ERROR: ${message}" >&2
            ;;
        WARN)
            print_color "${YELLOW}" "[${timestamp}] WARN: ${message}" >&2
            ;;
        INFO)
            print_color "${GREEN}" "[${timestamp}] INFO: ${message}"
            ;;
        DEBUG)
            if [[ ${VERBOSE} == true ]]; then
                print_color "${BLUE}" "[${timestamp}] DEBUG: ${message}"
            fi
            ;;
    esac
}

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    log INFO "${description}"
    log DEBUG "Command: ${cmd}"
    
    if [[ ${DRY_RUN} == true ]]; then
        log INFO "DRY RUN: Would execute: ${cmd}"
        return 0
    fi
    
    if eval "${cmd}"; then
        log INFO "✓ ${description} completed successfully"
        return 0
    else
        log ERROR "✗ ${description} failed"
        return 1
    fi
}

# Function to display usage
usage() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - Example Deployment Script

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    -a, --app NAME           Application name (default: ${APP_NAME})
    -e, --environment ENV    Environment: development|staging|production (default: ${ENVIRONMENT})
    -b, --branch BRANCH      Git branch to deploy (default: ${BRANCH})
    -v, --verbose            Enable verbose output
    -n, --dry-run            Show what would be executed without running
    --version                Show version information
    --help                   Display this help message

EXAMPLES:
    # Basic deployment
    ${SCRIPT_NAME} -a myapp -e production -b release/v1.2.3

    # Dry run deployment
    ${SCRIPT_NAME} -n -a myapp -e production -b main

    # Verbose deployment
    ${SCRIPT_NAME} -v -a webapp -e staging

EOF
}

# Function to validate environment
validate_environment() {
    case ${ENVIRONMENT} in
        development|staging|production)
            log DEBUG "Environment '${ENVIRONMENT}' is valid"
            ;;
        *)
            log ERROR "Invalid environment: ${ENVIRONMENT}. Must be one of: development, staging, production"
            exit 1
            ;;
    esac
}

# Function to simulate pre-deployment checks
pre_deployment_checks() {
    log INFO "Running pre-deployment checks..."
    
    execute_cmd "whoami" "Checking current user"
    execute_cmd "pwd" "Checking current directory"
    execute_cmd "df -h | head -5" "Checking disk space"
    execute_cmd "free -h || vm_stat" "Checking memory usage"
    
    # Check if required tools are available
    local required_tools=("git" "curl" "tar")
    for tool in "${required_tools[@]}"; do
        if command -v "${tool}" &> /dev/null; then
            log INFO "✓ ${tool} is available"
        else
            log ERROR "✗ ${tool} is not available"
            exit 1
        fi
    done
}

# Function to simulate application backup
backup_application() {
    log INFO "Creating backup of current application..."
    
    local backup_dir="/tmp/backup-${APP_NAME}-$(date +%Y%m%d-%H%M%S)"
    
    execute_cmd "mkdir -p ${backup_dir}" "Creating backup directory"
    execute_cmd "echo 'Simulated application files' > ${backup_dir}/app.tar.gz" "Creating backup archive"
    
    log INFO "Backup created at: ${backup_dir}"
}

# Function to simulate code deployment
deploy_application() {
    log INFO "Deploying application '${APP_NAME}' from branch '${BRANCH}' to '${ENVIRONMENT}'..."
    
    local deploy_dir="/tmp/deploy-${APP_NAME}"
    
    execute_cmd "mkdir -p ${deploy_dir}" "Creating deployment directory"
    execute_cmd "cd ${deploy_dir}" "Changing to deployment directory"
    
    # Simulate git operations
    execute_cmd "echo 'Simulating: git clone...' && sleep 1" "Cloning repository"
    execute_cmd "echo 'Simulating: git checkout ${BRANCH}...' && sleep 1" "Checking out branch ${BRANCH}"
    
    # Simulate build process
    execute_cmd "echo 'Simulating: npm install...' && sleep 2" "Installing dependencies"
    execute_cmd "echo 'Simulating: npm run build...' && sleep 3" "Building application"
    
    # Simulate service restart
    execute_cmd "echo 'Simulating: systemctl restart ${APP_NAME}...' && sleep 1" "Restarting application service"
}

# Function to simulate post-deployment checks
post_deployment_checks() {
    log INFO "Running post-deployment checks..."
    
    execute_cmd "echo 'Simulating: curl -f http://localhost:8080/health' && sleep 1" "Checking application health"
    execute_cmd "echo 'Simulating: service status check...' && sleep 1" "Checking service status"
    
    log INFO "✓ Deployment completed successfully!"
}

# Function to simulate rollback
rollback_deployment() {
    log WARN "Rolling back deployment due to failure..."
    
    execute_cmd "echo 'Simulating: restoring from backup...' && sleep 2" "Restoring from backup"
    execute_cmd "echo 'Simulating: restarting services...' && sleep 1" "Restarting services"
    
    log WARN "Rollback completed"
}

# Main deployment function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--app)
                APP_NAME="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -b|--branch)
                BRANCH="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --version)
                echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
                exit 0
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Show deployment information
    log INFO "Starting deployment process..."
    log INFO "Application: ${APP_NAME}"
    log INFO "Environment: ${ENVIRONMENT}"
    log INFO "Branch: ${BRANCH}"
    log INFO "Verbose: ${VERBOSE}"
    log INFO "Dry Run: ${DRY_RUN}"
    echo
    
    # Validate inputs
    validate_environment
    
    # Execute deployment steps
    if pre_deployment_checks; then
        if backup_application; then
            if deploy_application; then
                post_deployment_checks
            else
                log ERROR "Deployment failed, initiating rollback..."
                rollback_deployment
                exit 1
            fi
        else
            log ERROR "Backup failed, aborting deployment"
            exit 1
        fi
    else
        log ERROR "Pre-deployment checks failed, aborting deployment"
        exit 1
    fi
    
    log INFO "🎉 Deployment workflow completed successfully!"
}

# Run main function
main "$@"
