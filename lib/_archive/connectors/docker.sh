#!/bin/sh
# lib/docker.sh - Shared Docker utilities for RSR scripts
# POSIX-compatible
#
# Source this in Docker-related scripts:
#   . "${0%/*}/../lib/docker.sh"

# =============================================================================
# Docker Detection
# =============================================================================

# Check if Docker CLI is installed
docker_is_installed() {
    command -v docker >/dev/null 2>&1
}

# Check if Docker daemon is running
docker_is_running() {
    docker info >/dev/null 2>&1
}

# Get Docker version
docker_get_version() {
    if docker_is_installed; then
        docker --version 2>/dev/null | awk '{print $3}' | tr -d ','
    else
        echo "not_installed"
    fi
}

# Get Docker Compose version
docker_compose_version() {
    if docker compose version >/dev/null 2>&1; then
        docker compose version --short 2>/dev/null
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose --version 2>/dev/null | awk '{print $3}' | tr -d ','
    else
        echo "not_installed"
    fi
}

# Check if user is in docker group
docker_has_permissions() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    
    groups 2>/dev/null | grep -q docker
}

# =============================================================================
# Docker Operations
# =============================================================================

# Ensure Docker is installed
docker_ensure_installed() {
    if ! docker_is_installed; then
        log_error "Docker is not installed"
        log_info "Install with: rsr docker install engine"
        return 1
    fi
}

# Ensure Docker daemon is running
docker_ensure_running() {
    if ! docker_is_running; then
        log_error "Docker daemon is not running"
        log_info "Start with: sudo systemctl start docker"
        return 1
    fi
}

# Ensure Docker permissions
docker_ensure_permissions() {
    if ! docker_has_permissions; then
        log_warn "Current user not in docker group"
        log_info "Add with: sudo usermod -aG docker \$USER"
        log_info "Then log out and back in"
        return 1
    fi
}

# =============================================================================
# Container Operations
# =============================================================================

# List containers (format: id name status)
docker_list_containers() {
    local show_all="${1:-}"
    local flags=""
    
    [ "$show_all" = "all" ] && flags="-a"
    
    docker_ensure_installed || return 1
    docker_ensure_running || return 1
    
    docker ps $flags --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}"
}

# Check if container exists
docker_container_exists() {
    local container="$1"
    docker_ensure_installed || return 1
    docker ps -a --format '{{.Names}}' | grep -q "^${container}$"
}

# Check if container is running
docker_container_is_running() {
    local container="$1"
    docker_ensure_installed || return 1
    docker ps --format '{{.Names}}' | grep -q "^${container}$"
}

# Get container status
docker_container_status() {
    local container="$1"
    docker_ensure_installed || return 1
    docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null
}

# =============================================================================
# Image Operations
# =============================================================================

# List images
docker_list_images() {
    docker_ensure_installed || return 1
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"
}

# Check if image exists
docker_image_exists() {
    local image="$1"
    docker_ensure_installed || return 1
    docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image}$"
}

# Get image size
docker_image_size() {
    local image="$1"
    docker_ensure_installed || return 1
    docker images --format '{{.Size}}' "$image" 2>/dev/null
}

# =============================================================================
# Volume Operations
# =============================================================================

# List volumes
docker_list_volumes() {
    docker_ensure_installed || return 1
    docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}"
}

# Check if volume exists
docker_volume_exists() {
    local volume="$1"
    docker_ensure_installed || return 1
    docker volume ls --format '{{.Name}}' | grep -q "^${volume}$"
}

# Get volume mountpoint
docker_volume_mountpoint() {
    local volume="$1"
    docker_ensure_installed || return 1
    docker volume inspect --format='{{.Mountpoint}}' "$volume" 2>/dev/null
}

# =============================================================================
# Network Operations
# =============================================================================

# List networks
docker_list_networks() {
    docker_ensure_installed || return 1
    docker network ls --format "table {{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}"
}

# Check if network exists
docker_network_exists() {
    local network="$1"
    docker_ensure_installed || return 1
    docker network ls --format '{{.Name}}' | grep -q "^${network}$"
}

# =============================================================================
# System Operations
# =============================================================================

# Get disk usage
docker_disk_usage() {
    docker_ensure_installed || return 1
    docker system df
}

# Get detailed disk usage
docker_disk_usage_verbose() {
    docker_ensure_installed || return 1
    docker system df -v
}

# Get Docker info
docker_system_info() {
    docker_ensure_installed || return 1
    docker_ensure_running || return 1
    docker info
}

# Count resources
docker_count_containers() {
    docker_ensure_installed || return 1
    docker ps -q | wc -l | tr -d ' '
}

docker_count_images() {
    docker_ensure_installed || return 1
    docker images -q | wc -l | tr -d ' '
}

docker_count_volumes() {
    docker_ensure_installed || return 1
    docker volume ls -q | wc -l | tr -d ' '
}

docker_count_networks() {
    docker_ensure_installed || return 1
    docker network ls -q | wc -l | tr -d ' '
}

# =============================================================================
# Cleanup Operations
# =============================================================================

# Remove stopped containers
docker_prune_containers() {
    docker_ensure_installed || return 1
    docker container prune -f
}

# Remove dangling images
docker_prune_images() {
    docker_ensure_installed || return 1
    docker image prune -f
}

# Remove unused volumes
docker_prune_volumes() {
    docker_ensure_installed || return 1
    docker volume prune -f
}

# Remove unused networks
docker_prune_networks() {
    docker_ensure_installed || return 1
    docker network prune -f
}

# Remove all unused resources
docker_prune_system() {
    docker_ensure_installed || return 1
    docker system prune -f
}

# Remove all unused resources including volumes
docker_prune_system_all() {
    docker_ensure_installed || return 1
    docker system prune -a --volumes -f
}

# =============================================================================
# Platform Detection for Docker
# =============================================================================

# Detect if running in Docker container
docker_in_container() {
    [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null
}

# Get Docker storage driver
docker_storage_driver() {
    docker_ensure_installed || return 1
    docker info 2>/dev/null | grep "Storage Driver" | awk '{print $3}'
}

# Get Docker root directory
docker_root_dir() {
    docker_ensure_installed || return 1
    docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $4}'
}

# =============================================================================
# Docker Compose Helpers
# =============================================================================

# Check if docker-compose.yml exists
docker_compose_file_exists() {
    [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "compose.yml" ] || [ -f "compose.yaml" ]
}

# Find docker-compose file
docker_compose_find_file() {
    if [ -f "compose.yml" ]; then
        echo "compose.yml"
    elif [ -f "compose.yaml" ]; then
        echo "compose.yaml"
    elif [ -f "docker-compose.yml" ]; then
        echo "docker-compose.yml"
    elif [ -f "docker-compose.yaml" ]; then
        echo "docker-compose.yaml"
    else
        return 1
    fi
}

# Get compose command (docker compose vs docker-compose)
docker_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        return 1
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Format bytes to human readable
docker_format_size() {
    local bytes="$1"
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# Parse docker ps output
docker_parse_container_info() {
    local container="$1"
    docker inspect --format='{{json .}}' "$container" 2>/dev/null
}

# Get container IP
docker_container_ip() {
    local container="$1"
    docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container" 2>/dev/null
}

# Get container ports
docker_container_ports() {
    local container="$1"
    docker port "$container" 2>/dev/null
}

# =============================================================================
# Health Checks
# =============================================================================

# Docker healthcheck
docker_health_check() {
    local status=0
    
    log_info "Docker Health Check"
    echo
    
    # Check installation
    if docker_is_installed; then
        log_ok "Docker CLI installed: $(docker_get_version)"
    else
        log_error "Docker CLI not installed"
        status=1
    fi
    
    # Check daemon
    if docker_is_running; then
        log_ok "Docker daemon is running"
    else
        log_error "Docker daemon is not running"
        status=1
    fi
    
    # Check permissions
    if docker_has_permissions; then
        log_ok "User has Docker permissions"
    else
        log_warn "User not in docker group"
    fi
    
    # Resource counts
    if [ $status -eq 0 ]; then
        echo
        echo "Resources:"
        echo "  Containers: $(docker_count_containers)"
        echo "  Images: $(docker_count_images)"
        echo "  Volumes: $(docker_count_volumes)"
        echo "  Networks: $(docker_count_networks)"
    fi
    
    return $status
}

# Export functions for scripts that source this library
# (Note: In POSIX sh, functions are automatically available after sourcing)
