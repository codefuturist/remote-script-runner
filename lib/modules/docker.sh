#!/bin/sh
# lib/modules/docker.sh - RSR Docker Management Module
# Cross-platform Docker operations
#
# Usage: . "${RSR_LIB_DIR:-./lib}/modules/docker.sh"
#
# Provides:
#   - Docker detection and status
#   - Container operations
#   - Image operations
#   - Volume operations
#   - Network operations
#   - Docker Compose operations

# =============================================================================
# Guard: Prevent double-sourcing
# =============================================================================

[ -n "${_RSR_MODULE_DOCKER_LOADED:-}" ] && return 0
_RSR_MODULE_DOCKER_LOADED=1

# Ensure core is loaded
if [ -z "${_RSR_CORE_INIT_LOADED:-}" ]; then
    _script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || _script_dir="."
    . "${_script_dir}/../core/init.sh" 2>/dev/null || . "./lib/core/init.sh" 2>/dev/null || {
        echo "ERROR: RSR core/init.sh must be sourced first" >&2
        return 1
    }
fi

# =============================================================================
# Module Metadata
# =============================================================================

_RSR_DOCKER_VERSION="2.0.0"

# =============================================================================
# Docker Detection
# =============================================================================

# Check if Docker CLI is installed
# Usage: if rsr_docker_is_installed; then ...
rsr_docker_is_installed() {
    rsr_has_command docker
}

# Check if Docker daemon is running
# Usage: if rsr_docker_is_running; then ...
rsr_docker_is_running() {
    docker info >/dev/null 2>&1
}

# Ensure Docker is available (installed and running)
# Usage: rsr_docker_ensure || exit 1
rsr_docker_ensure() {
    if ! rsr_docker_is_installed; then
        rsr_log_error "Docker is not installed"
        rsr_log_info "Install with: rsr docker install engine"
        return "$RSR_EXIT_DEPENDENCY"
    fi

    if ! rsr_docker_is_running; then
        rsr_log_error "Docker daemon is not running"
        case "$(rsr_detect_os)" in
            darwin)
                rsr_log_info "Start Docker Desktop or run: open -a Docker"
                ;;
            linux)
                rsr_log_info "Start with: sudo systemctl start docker"
                ;;
        esac
        return "$RSR_EXIT_ERROR"
    fi

    return 0
}

# Get Docker version
# Usage: version=$(rsr_docker_version)
rsr_docker_version() {
    if rsr_docker_is_installed; then
        docker --version 2>/dev/null | awk '{print $3}' | tr -d ','
    else
        echo "not_installed"
    fi
}

# Get Docker Compose version
# Usage: version=$(rsr_docker_compose_version)
rsr_docker_compose_version() {
    if docker compose version >/dev/null 2>&1; then
        docker compose version --short 2>/dev/null
    elif rsr_has_command docker-compose; then
        docker-compose --version 2>/dev/null | awk '{print $3}' | tr -d ','
    else
        echo "not_installed"
    fi
}

# Check if user has Docker permissions
# Usage: if rsr_docker_has_permissions; then ...
rsr_docker_has_permissions() {
    [ "$(id -u)" -eq 0 ] && return 0
    groups 2>/dev/null | grep -q docker
}

# =============================================================================
# Container Operations
# =============================================================================

# List containers
# Usage: rsr_docker_container_list [all]
rsr_docker_container_list() {
    _all="${1:-}"
    rsr_docker_ensure || return $?

    _flags=""
    [ "$_all" = "all" ] && _flags="-a"

    docker ps $_flags --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"
}

# Check if container exists
# Usage: if rsr_docker_container_exists "name"; then ...
rsr_docker_container_exists() {
    _name="$1"
    rsr_docker_ensure || return $?
    docker ps -a --format '{{.Names}}' | grep -q "^${_name}$"
}

# Check if container is running
# Usage: if rsr_docker_container_is_running "name"; then ...
rsr_docker_container_is_running() {
    _name="$1"
    rsr_docker_ensure || return $?
    docker ps --format '{{.Names}}' | grep -q "^${_name}$"
}

# Start container
# Usage: rsr_docker_container_start "name"
rsr_docker_container_start() {
    _name="$1"
    rsr_docker_ensure || return $?

    if ! rsr_docker_container_exists "$_name"; then
        rsr_log_error "Container '$_name' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    docker start "$_name"
}

# Stop container
# Usage: rsr_docker_container_stop "name" [timeout]
rsr_docker_container_stop() {
    _name="$1"
    _timeout="${2:-10}"
    rsr_docker_ensure || return $?

    if ! rsr_docker_container_is_running "$_name"; then
        rsr_log_warn "Container '$_name' is not running"
        return 0
    fi

    docker stop -t "$_timeout" "$_name"
}

# Restart container
# Usage: rsr_docker_container_restart "name"
rsr_docker_container_restart() {
    _name="$1"
    rsr_docker_ensure || return $?
    docker restart "$_name"
}

# Remove container
# Usage: rsr_docker_container_remove "name" [--force]
rsr_docker_container_remove() {
    _name="$1"
    shift
    _force=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --force|-f) _force="-f"; shift ;;
            *) shift ;;
        esac
    done

    rsr_docker_ensure || return $?

    if ! rsr_docker_container_exists "$_name"; then
        rsr_log_warn "Container '$_name' does not exist"
        return 0
    fi

    docker rm $_force "$_name"
}

# Get container logs
# Usage: rsr_docker_container_logs "name" [--tail N] [--follow]
rsr_docker_container_logs() {
    _name="$1"
    shift
    _tail="" _follow=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --tail) _tail="--tail $2"; shift 2 ;;
            --follow|-f) _follow="-f"; shift ;;
            *) shift ;;
        esac
    done

    rsr_docker_ensure || return $?
    docker logs $_tail $_follow "$_name"
}

# Execute command in container
# Usage: rsr_docker_container_exec "name" command [args...]
rsr_docker_container_exec() {
    _name="$1"
    shift
    rsr_docker_ensure || return $?

    if ! rsr_docker_container_is_running "$_name"; then
        rsr_log_error "Container '$_name' is not running"
        return "$RSR_EXIT_ERROR"
    fi

    docker exec -it "$_name" "$@"
}

# Get container stats
# Usage: rsr_docker_container_stats [name]
rsr_docker_container_stats() {
    _name="${1:-}"
    rsr_docker_ensure || return $?

    if [ -n "$_name" ]; then
        docker stats --no-stream "$_name"
    else
        docker stats --no-stream
    fi
}

# Inspect container
# Usage: rsr_docker_container_inspect "name" [format]
rsr_docker_container_inspect() {
    _name="$1"
    _format="${2:-}"
    rsr_docker_ensure || return $?

    if [ -n "$_format" ]; then
        docker inspect --format "$_format" "$_name"
    else
        docker inspect "$_name"
    fi
}

# =============================================================================
# Image Operations
# =============================================================================

# List images
# Usage: rsr_docker_image_list
rsr_docker_image_list() {
    rsr_docker_ensure || return $?
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}"
}

# Pull image
# Usage: rsr_docker_image_pull "image:tag"
rsr_docker_image_pull() {
    _image="$1"
    rsr_docker_ensure || return $?
    docker pull "$_image"
}

# Remove image
# Usage: rsr_docker_image_remove "image" [--force]
rsr_docker_image_remove() {
    _image="$1"
    shift
    _force=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --force|-f) _force="-f"; shift ;;
            *) shift ;;
        esac
    done

    rsr_docker_ensure || return $?
    docker rmi $_force "$_image"
}

# Build image
# Usage: rsr_docker_image_build "tag" [path] [--file Dockerfile]
rsr_docker_image_build() {
    _tag="$1"
    _path="${2:-.}"
    shift 2 || shift
    _file=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --file|-f) _file="-f $2"; shift 2 ;;
            *) shift ;;
        esac
    done

    rsr_docker_ensure || return $?
    docker build -t "$_tag" $_file "$_path"
}

# Prune unused images
# Usage: rsr_docker_image_prune [--all]
rsr_docker_image_prune() {
    _all=""
    [ "$1" = "--all" ] && _all="-a"

    rsr_docker_ensure || return $?
    docker image prune -f $_all
}

# =============================================================================
# Volume Operations
# =============================================================================

# List volumes
# Usage: rsr_docker_volume_list
rsr_docker_volume_list() {
    rsr_docker_ensure || return $?
    docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
}

# Create volume
# Usage: rsr_docker_volume_create "name"
rsr_docker_volume_create() {
    _name="$1"
    rsr_docker_ensure || return $?
    docker volume create "$_name"
}

# Remove volume
# Usage: rsr_docker_volume_remove "name" [--force]
rsr_docker_volume_remove() {
    _name="$1"
    shift
    _force=""
    [ "$1" = "--force" ] && _force="-f"

    rsr_docker_ensure || return $?
    docker volume rm $_force "$_name"
}

# Prune unused volumes
# Usage: rsr_docker_volume_prune
rsr_docker_volume_prune() {
    rsr_docker_ensure || return $?
    docker volume prune -f
}

# =============================================================================
# Network Operations
# =============================================================================

# List networks
# Usage: rsr_docker_network_list
rsr_docker_network_list() {
    rsr_docker_ensure || return $?
    docker network ls --format "table {{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}"
}

# Create network
# Usage: rsr_docker_network_create "name" [--driver DRIVER]
rsr_docker_network_create() {
    _name="$1"
    shift
    _driver=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --driver) _driver="-d $2"; shift 2 ;;
            *) shift ;;
        esac
    done

    rsr_docker_ensure || return $?
    docker network create $_driver "$_name"
}

# Remove network
# Usage: rsr_docker_network_remove "name"
rsr_docker_network_remove() {
    _name="$1"
    rsr_docker_ensure || return $?
    docker network rm "$_name"
}

# Connect container to network
# Usage: rsr_docker_network_connect "network" "container"
rsr_docker_network_connect() {
    _network="$1"
    _container="$2"
    rsr_docker_ensure || return $?
    docker network connect "$_network" "$_container"
}

# Disconnect container from network
# Usage: rsr_docker_network_disconnect "network" "container"
rsr_docker_network_disconnect() {
    _network="$1"
    _container="$2"
    rsr_docker_ensure || return $?
    docker network disconnect "$_network" "$_container"
}

# =============================================================================
# Docker Compose Operations
# =============================================================================

# Check if compose file exists
# Usage: rsr_docker_compose_exists [path]
rsr_docker_compose_exists() {
    _path="${1:-.}"
    [ -f "$_path/docker-compose.yml" ] || [ -f "$_path/docker-compose.yaml" ] || [ -f "$_path/compose.yml" ] || [ -f "$_path/compose.yaml" ]
}

# Docker Compose up
# Usage: rsr_docker_compose_up [path] [--detach] [--build]
rsr_docker_compose_up() {
    _path="."
    _flags=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --detach|-d) _flags="$_flags -d"; shift ;;
            --build) _flags="$_flags --build"; shift ;;
            -*) shift ;;
            *) _path="$1"; shift ;;
        esac
    done

    rsr_docker_ensure || return $?

    cd "$_path" || return $?
    docker compose up $_flags
}

# Docker Compose down
# Usage: rsr_docker_compose_down [path] [--volumes]
rsr_docker_compose_down() {
    _path="."
    _flags=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --volumes|-v) _flags="$_flags -v"; shift ;;
            -*) shift ;;
            *) _path="$1"; shift ;;
        esac
    done

    rsr_docker_ensure || return $?

    cd "$_path" || return $?
    docker compose down $_flags
}

# Docker Compose logs
# Usage: rsr_docker_compose_logs [path] [service] [--follow]
rsr_docker_compose_logs() {
    _path="."
    _service=""
    _follow=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --follow|-f) _follow="-f"; shift ;;
            -*) shift ;;
            *)
                if [ -d "$1" ]; then
                    _path="$1"
                else
                    _service="$1"
                fi
                shift
                ;;
        esac
    done

    rsr_docker_ensure || return $?

    cd "$_path" || return $?
    docker compose logs $_follow $_service
}

# Docker Compose ps
# Usage: rsr_docker_compose_ps [path]
rsr_docker_compose_ps() {
    _path="${1:-.}"
    rsr_docker_ensure || return $?

    cd "$_path" || return $?
    docker compose ps
}

# =============================================================================
# Cleanup Operations
# =============================================================================

# System prune (clean everything unused)
# Usage: rsr_docker_system_prune [--all] [--volumes]
rsr_docker_system_prune() {
    _flags="-f"

    while [ $# -gt 0 ]; do
        case "$1" in
            --all|-a) _flags="$_flags -a"; shift ;;
            --volumes) _flags="$_flags --volumes"; shift ;;
            *) shift ;;
        esac
    done

    rsr_docker_ensure || return $?
    docker system prune $_flags
}

# Get disk usage
# Usage: rsr_docker_disk_usage
rsr_docker_disk_usage() {
    rsr_docker_ensure || return $?
    docker system df
}

# =============================================================================
# Initialization Complete
# =============================================================================

rsr_log_debug "RSR Docker Module v${_RSR_DOCKER_VERSION} loaded"

