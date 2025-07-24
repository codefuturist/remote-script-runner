#!/usr/bin/env bash

# Remote Script Runner
# A robust script for executing commands on remote servers via SSH
# Supports various SSH configurations and best practices

set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
readonly DEFAULT_SSH_PORT=22
readonly DEFAULT_TIMEOUT=30
DEFAULT_RETRIES=3
DEFAULT_RETRY_DELAY=5

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# SSH options for security and stability
readonly SSH_OPTIONS=(
    -o "StrictHostKeyChecking=accept-new"
    -o "UserKnownHostsFile=~/.ssh/known_hosts"
    -o "PasswordAuthentication=no"
    -o "PreferredAuthentications=publickey"
    -o "ServerAliveInterval=60"
    -o "ServerAliveCountMax=3"
    -o "ConnectTimeout=${DEFAULT_TIMEOUT}"
    -o "BatchMode=yes"
    -o "LogLevel=ERROR"
)

# Global variables
VERBOSE=false
DRY_RUN=false
USE_JUMP_HOST=false
PARALLEL_EXECUTION=false
MAX_PARALLEL_JOBS=5

# Function to show header
show_header() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}     ${GREEN}Remote Script Runner${NC}          ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}        Version $SCRIPT_VERSION              ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo
}

# Function to display usage information
usage() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - Remote Script Runner

USAGE:
    ${SCRIPT_NAME} [OPTIONS] -h HOST [-c COMMAND | -f SCRIPT_FILE]

OPTIONS:
    -h, --host HOST           Target host (required)
    -u, --user USER           SSH user (default: current user)
    -p, --port PORT           SSH port (default: ${DEFAULT_SSH_PORT})
    -i, --identity FILE       SSH identity file (private key)
    -c, --command COMMAND     Command to execute remotely
    -f, --file SCRIPT_FILE    Local script file to execute remotely
    -j, --jump-host HOST      Jump host for SSH ProxyJump
    -t, --timeout SECONDS     Connection timeout (default: ${DEFAULT_TIMEOUT})
    -r, --retries COUNT       Number of retry attempts (default: ${DEFAULT_RETRIES})
    -d, --delay SECONDS       Delay between retries (default: ${DEFAULT_RETRY_DELAY})
    -v, --verbose             Enable verbose output
    -n, --dry-run             Show what would be executed without running
    --parallel                Enable parallel execution for multiple hosts
    --max-jobs COUNT          Maximum parallel jobs (default: ${MAX_PARALLEL_JOBS})
    --version                 Show version information
    --help                    Display this help message

EXAMPLES:
    # Execute a simple command
    ${SCRIPT_NAME} -h server.example.com -c "uptime"

    # Execute a local script on remote server
    ${SCRIPT_NAME} -h server.example.com -f ./deploy.sh

    # Use specific SSH key and user
    ${SCRIPT_NAME} -h server.example.com -u deploy -i ~/.ssh/deploy_key -c "systemctl status nginx"

    # Connect through jump host
    ${SCRIPT_NAME} -h internal.server -j bastion.example.com -c "df -h"

    # Execute on multiple hosts in parallel
    ${SCRIPT_NAME} -h "web1.example.com,web2.example.com,web3.example.com" --parallel -c "systemctl restart nginx"

EOF
}

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

# Function to validate prerequisites
check_prerequisites() {
    local required_commands=("ssh" "scp" "mktemp")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            log ERROR "Required command '${cmd}' not found"
            exit 1
        fi
    done
    
    log DEBUG "All prerequisites satisfied"
}

# Function to validate host format
validate_host() {
    local host=$1
    
    # Basic validation - check if host is not empty
    if [[ -z "${host}" ]]; then
        log ERROR "Host cannot be empty"
        return 1
    fi
    
    # Check for invalid characters
    if [[ ! "${host}" =~ ^[a-zA-Z0-9._,-]+$ ]]; then
        log ERROR "Invalid host format: ${host}"
        return 1
    fi
    
    return 0
}

# Function to build SSH command
build_ssh_command() {
    local host=$1
    local user=$2
    local port=$3
    local identity_file=$4
    local jump_host=$5
    
    local ssh_cmd=("ssh")
    
    # Add SSH options
    ssh_cmd+=("${SSH_OPTIONS[@]}")
    
    # Add port if not default
    if [[ ${port} -ne ${DEFAULT_SSH_PORT} ]]; then
        ssh_cmd+=("-p" "${port}")
    fi
    
    # Add identity file if specified
    if [[ -n "${identity_file}" ]]; then
        if [[ ! -f "${identity_file}" ]]; then
            log ERROR "Identity file not found: ${identity_file}"
            exit 1
        fi
        ssh_cmd+=("-i" "${identity_file}")
    fi
    
    # Add jump host if specified
    if [[ -n "${jump_host}" ]] && [[ ${USE_JUMP_HOST} == true ]]; then
        ssh_cmd+=("-J" "${jump_host}")
    fi
    
    # Add user@host
    if [[ -n "${user}" ]]; then
        ssh_cmd+=("${user}@${host}")
    else
        ssh_cmd+=("${host}")
    fi
    
    echo "${ssh_cmd[@]}"
}

# Function to execute command with retries
execute_with_retry() {
    local ssh_cmd=("$@")
    local attempt=1
    local exit_code=0
    
    while [[ ${attempt} -le ${DEFAULT_RETRIES} ]]; do
        log INFO "Attempt ${attempt}/${DEFAULT_RETRIES}: Executing remote command"
        
        if [[ ${DRY_RUN} == true ]]; then
            log INFO "DRY RUN: Would execute: ${ssh_cmd[*]}"
            return 0
        fi
        
        if "${ssh_cmd[@]}"; then
            log INFO "Command executed successfully"
            return 0
        else
            exit_code=$?
            log WARN "Command failed with exit code: ${exit_code}"
            
            if [[ ${attempt} -lt ${DEFAULT_RETRIES} ]]; then
                log INFO "Retrying in ${DEFAULT_RETRY_DELAY} seconds..."
                sleep "${DEFAULT_RETRY_DELAY}"
            fi
        fi
        
        ((attempt++))
    done
    
    log ERROR "Command failed after ${DEFAULT_RETRIES} attempts"
    return ${exit_code}
}

# Function to execute remote command
execute_remote_command() {
    local host=$1
    local command=$2
    local ssh_cmd_array=()
    
    # Build SSH command
    IFS=' ' read -ra ssh_cmd_array <<< "$(build_ssh_command "${host}" "${SSH_USER}" "${SSH_PORT}" "${SSH_IDENTITY}" "${JUMP_HOST}")"
    
    # Add command to execute
    ssh_cmd_array+=("${command}")
    
    # Execute with retry logic
    execute_with_retry "${ssh_cmd_array[@]}"
}

# Function to execute remote script file
execute_remote_script() {
    local host=$1
    local script_file=$2
    local remote_script
    
    # Validate script file
    if [[ ! -f "${script_file}" ]]; then
        log ERROR "Script file not found: ${script_file}"
        return 1
    fi
    
    # Create temporary remote script name
    remote_script="/tmp/remote_script_$$.sh"
    
    log INFO "Copying script to remote host: ${host}"
    
    # Build SCP command
    local scp_cmd=("scp")
    scp_cmd+=("${SSH_OPTIONS[@]}")
    
    if [[ ${SSH_PORT} -ne ${DEFAULT_SSH_PORT} ]]; then
        scp_cmd+=("-P" "${SSH_PORT}")
    fi
    
    if [[ -n "${SSH_IDENTITY}" ]]; then
        scp_cmd+=("-i" "${SSH_IDENTITY}")
    fi
    
    if [[ -n "${JUMP_HOST}" ]] && [[ ${USE_JUMP_HOST} == true ]]; then
        scp_cmd+=("-J" "${JUMP_HOST}")
    fi
    
    scp_cmd+=("${script_file}")
    
    if [[ -n "${SSH_USER}" ]]; then
        scp_cmd+=("${SSH_USER}@${host}:${remote_script}")
    else
        scp_cmd+=("${host}:${remote_script}")
    fi
    
    # Copy script
    if [[ ${DRY_RUN} == true ]]; then
        log INFO "DRY RUN: Would copy script with: ${scp_cmd[*]}"
    else
        if ! "${scp_cmd[@]}"; then
            log ERROR "Failed to copy script to remote host"
            return 1
        fi
    fi
    
    # Execute script and cleanup
    local exec_cmd="chmod +x ${remote_script} && ${remote_script}; rm -f ${remote_script}"
    execute_remote_command "${host}" "${exec_cmd}"
}

# Function to process single host
process_host() {
    local host=$1
    
    log INFO "Processing host: ${host}"
    
    if [[ -n "${COMMAND}" ]]; then
        execute_remote_command "${host}" "${COMMAND}"
    elif [[ -n "${SCRIPT_FILE}" ]]; then
        execute_remote_script "${host}" "${SCRIPT_FILE}"
    else
        log ERROR "No command or script file specified"
        return 1
    fi
}

# Function to process multiple hosts
process_multiple_hosts() {
    local hosts_array=()
    IFS=',' read -ra hosts_array <<< "${HOST}"
    
    if [[ ${PARALLEL_EXECUTION} == true ]]; then
        log INFO "Executing on ${#hosts_array[@]} hosts in parallel (max ${MAX_PARALLEL_JOBS} jobs)"
        
        # Use GNU parallel if available, otherwise fall back to background jobs
        if command -v parallel &> /dev/null; then
            printf '%s\n' "${hosts_array[@]}" | \
                parallel -j "${MAX_PARALLEL_JOBS}" "${SCRIPT_DIR}/${SCRIPT_NAME}" \
                    --host {} \
                    --user "${SSH_USER}" \
                    --port "${SSH_PORT}" \
                    ${SSH_IDENTITY:+--identity "${SSH_IDENTITY}"} \
                    ${JUMP_HOST:+--jump-host "${JUMP_HOST}"} \
                    ${COMMAND:+--command "${COMMAND}"} \
                    ${SCRIPT_FILE:+--file "${SCRIPT_FILE}"} \
                    ${VERBOSE:+--verbose} \
                    ${DRY_RUN:+--dry-run}
        else
            # Fallback to background jobs
            local job_count=0
            for host in "${hosts_array[@]}"; do
                if [[ ${job_count} -ge ${MAX_PARALLEL_JOBS} ]]; then
                    wait -n
                    ((job_count--))
                fi
                
                process_host "${host}" &
                ((job_count++))
            done
            wait
        fi
    else
        # Sequential execution
        for host in "${hosts_array[@]}"; do
            process_host "${host}"
        done
    fi
}

# Main function
main() {
    # Initialize variables
    HOST=""
    SSH_USER="${USER}"
    SSH_PORT="${DEFAULT_SSH_PORT}"
    SSH_IDENTITY=""
    COMMAND=""
    SCRIPT_FILE=""
    JUMP_HOST=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--host)
                HOST="$2"
                shift 2
                ;;
            -u|--user)
                SSH_USER="$2"
                shift 2
                ;;
            -p|--port)
                SSH_PORT="$2"
                shift 2
                ;;
            -i|--identity)
                SSH_IDENTITY="$2"
                shift 2
                ;;
            -c|--command)
                COMMAND="$2"
                shift 2
                ;;
            -f|--file)
                SCRIPT_FILE="$2"
                shift 2
                ;;
            -j|--jump-host)
                JUMP_HOST="$2"
                USE_JUMP_HOST=true
                shift 2
                ;;
            -t|--timeout)
                SSH_OPTIONS+=("-o" "ConnectTimeout=$2")
                shift 2
                ;;
            -r|--retries)
                DEFAULT_RETRIES="$2"
                shift 2
                ;;
            -d|--delay)
                DEFAULT_RETRY_DELAY="$2"
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
            --parallel)
                PARALLEL_EXECUTION=true
                shift
                ;;
            --max-jobs)
                MAX_PARALLEL_JOBS="$2"
                shift 2
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
    
    # Validate required arguments
    if [[ -z "${HOST}" ]]; then
        log ERROR "Host is required"
        usage
        exit 1
    fi
    
    # Validate host format
    if ! validate_host "${HOST}"; then
        exit 1
    fi
    
    # Check if either command or script file is provided
    if [[ -z "${COMMAND}" ]] && [[ -z "${SCRIPT_FILE}" ]]; then
        log ERROR "Either command (-c) or script file (-f) must be specified"
        usage
        exit 1
    fi
    
    # Check if both command and script file are provided
    if [[ -n "${COMMAND}" ]] && [[ -n "${SCRIPT_FILE}" ]]; then
        log ERROR "Cannot specify both command (-c) and script file (-f)"
        usage
        exit 1
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Process hosts
    if [[ "${HOST}" == *","* ]]; then
        # Multiple hosts
        process_multiple_hosts
    else
        # Single host
        process_host "${HOST}"
    fi
}

# Run main function
main "$@"
