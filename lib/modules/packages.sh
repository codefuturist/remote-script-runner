#!/bin/sh
# lib/modules/packages.sh - RSR Package Management Module
# Cross-platform package installation and dependency management
#
# Provides:
#   - Package manager abstraction (apt, dnf, pacman, brew, etc.)
#   - Dependency checking and installation
#   - Interactive prompts for missing dependencies
#   - YAML package list support
#   - Package groups and profiles

# =============================================================================
# Guard: Prevent double-sourcing
# =============================================================================

[ -n "${_RSR_MODULE_PACKAGES_LOADED:-}" ] && return 0
_RSR_MODULE_PACKAGES_LOADED=1
_RSR_PACKAGES_VERSION="1.0.0"

# =============================================================================
# Configuration
# =============================================================================

RSR_PKG_AUTO_INSTALL="${RSR_PKG_AUTO_INSTALL:-0}"
RSR_PKG_CONFIRM="${RSR_PKG_CONFIRM:-1}"
RSR_PKG_UPDATE_CACHE="${RSR_PKG_UPDATE_CACHE:-1}"
RSR_PKG_CACHE_MAX_AGE="${RSR_PKG_CACHE_MAX_AGE:-3600}"  # 1 hour

# Package lists directory
RSR_PKG_LISTS_DIR="${RSR_PKG_LISTS_DIR:-${RSR_LIB_DIR:-./lib}/../config/packages}"

# =============================================================================
# Package Manager Detection & Abstraction
# =============================================================================

# Get the system package manager
# Returns: apt, dnf, yum, pacman, zypper, apk, brew, choco, unknown
rsr_pkg_manager() {
    if [ -n "${_RSR_PKG_MANAGER:-}" ]; then
        echo "$_RSR_PKG_MANAGER"
        return 0
    fi

    _RSR_PKG_MANAGER="$(rsr_detect_package_manager)"
    echo "$_RSR_PKG_MANAGER"
}

# Get sudo command if needed
_rsr_pkg_sudo() {
    _mgr="$(rsr_pkg_manager)"
    case "$_mgr" in
        brew|choco) echo "" ;;  # User-space package managers
        *)
            if [ "$(id -u)" -ne 0 ]; then
                echo "sudo"
            fi
            ;;
    esac
}

# =============================================================================
# Cache Management
# =============================================================================

# Check if package cache needs update
# Returns: 0 if cache is fresh, 1 if needs update
rsr_pkg_cache_fresh() {
    _mgr="$(rsr_pkg_manager)"
    _cache_file=""

    case "$_mgr" in
        apt)
            _cache_file="/var/cache/apt/pkgcache.bin"
            ;;
        dnf|yum)
            _cache_file="/var/cache/dnf/packages.db"
            [ ! -f "$_cache_file" ] && _cache_file="/var/cache/yum"
            ;;
        pacman)
            _cache_file="/var/lib/pacman/sync"
            ;;
        brew)
            _cache_file="$(brew --cache 2>/dev/null)/api"
            ;;
        *)
            return 1  # Unknown, assume needs update
            ;;
    esac

    [ ! -e "$_cache_file" ] && return 1

    _cache_age=$(($(date +%s) - $(stat -c %Y "$_cache_file" 2>/dev/null || stat -f %m "$_cache_file" 2>/dev/null || echo 0)))
    [ "$_cache_age" -lt "$RSR_PKG_CACHE_MAX_AGE" ]
}

# Update package cache
# Usage: rsr_pkg_update_cache
rsr_pkg_update_cache() {
    [ "$RSR_PKG_UPDATE_CACHE" != "1" ] && return 0
    rsr_pkg_cache_fresh && return 0

    _mgr="$(rsr_pkg_manager)"
    _sudo="$(_rsr_pkg_sudo)"

    rsr_log_info "Updating package cache..."

    case "$_mgr" in
        apt)
            $_sudo apt-get update -qq
            ;;
        dnf)
            $_sudo dnf check-update -q || true
            ;;
        yum)
            $_sudo yum check-update -q || true
            ;;
        pacman)
            $_sudo pacman -Sy --noconfirm
            ;;
        zypper)
            $_sudo zypper refresh -q
            ;;
        apk)
            $_sudo apk update -q
            ;;
        brew)
            brew update --quiet
            ;;
        *)
            rsr_log_warn "Unknown package manager, skipping cache update"
            return 1
            ;;
    esac
}

# =============================================================================
# Package Installation
# =============================================================================

# Install a single package
# Usage: rsr_pkg_install "package_name"
rsr_pkg_install() {
    _pkg="$1"
    _mgr="$(rsr_pkg_manager)"
    _sudo="$(_rsr_pkg_sudo)"

    rsr_log_info "Installing $_pkg..."

    case "$_mgr" in
        apt)
            $_sudo apt-get install -y -qq "$_pkg"
            ;;
        dnf)
            $_sudo dnf install -y -q "$_pkg"
            ;;
        yum)
            $_sudo yum install -y -q "$_pkg"
            ;;
        pacman)
            $_sudo pacman -S --noconfirm --needed "$_pkg"
            ;;
        zypper)
            $_sudo zypper install -y -q "$_pkg"
            ;;
        apk)
            $_sudo apk add -q "$_pkg"
            ;;
        brew)
            brew install -q "$_pkg"
            ;;
        choco)
            choco install -y "$_pkg"
            ;;
        *)
            rsr_log_error "Unknown package manager: $_mgr"
            return 1
            ;;
    esac
}

# Install multiple packages
# Usage: rsr_pkg_install_many pkg1 pkg2 pkg3
rsr_pkg_install_many() {
    _mgr="$(rsr_pkg_manager)"
    _sudo="$(_rsr_pkg_sudo)"
    _pkgs="$*"

    [ -z "$_pkgs" ] && return 0

    rsr_log_info "Installing packages: $_pkgs"

    case "$_mgr" in
        apt)
            $_sudo apt-get install -y -qq $_pkgs
            ;;
        dnf)
            $_sudo dnf install -y -q $_pkgs
            ;;
        yum)
            $_sudo yum install -y -q $_pkgs
            ;;
        pacman)
            $_sudo pacman -S --noconfirm --needed $_pkgs
            ;;
        zypper)
            $_sudo zypper install -y -q $_pkgs
            ;;
        apk)
            $_sudo apk add -q $_pkgs
            ;;
        brew)
            brew install -q $_pkgs
            ;;
        choco)
            choco install -y $_pkgs
            ;;
        *)
            rsr_log_error "Unknown package manager: $_mgr"
            return 1
            ;;
    esac
}

# Remove a package
# Usage: rsr_pkg_remove "package_name"
rsr_pkg_remove() {
    _pkg="$1"
    _mgr="$(rsr_pkg_manager)"
    _sudo="$(_rsr_pkg_sudo)"

    rsr_log_info "Removing $_pkg..."

    case "$_mgr" in
        apt)
            $_sudo apt-get remove -y -qq "$_pkg"
            ;;
        dnf)
            $_sudo dnf remove -y -q "$_pkg"
            ;;
        yum)
            $_sudo yum remove -y -q "$_pkg"
            ;;
        pacman)
            $_sudo pacman -R --noconfirm "$_pkg"
            ;;
        zypper)
            $_sudo zypper remove -y -q "$_pkg"
            ;;
        apk)
            $_sudo apk del -q "$_pkg"
            ;;
        brew)
            brew uninstall -q "$_pkg"
            ;;
        choco)
            choco uninstall -y "$_pkg"
            ;;
        *)
            rsr_log_error "Unknown package manager: $_mgr"
            return 1
            ;;
    esac
}

# =============================================================================
# Package Status
# =============================================================================

# Check if a package is installed
# Usage: rsr_pkg_is_installed "git"
rsr_pkg_is_installed() {
    _pkg="$1"
    _mgr="$(rsr_pkg_manager)"

    case "$_mgr" in
        apt)
            dpkg -l "$_pkg" 2>/dev/null | grep -q "^ii"
            ;;
        dnf|yum)
            rpm -q "$_pkg" >/dev/null 2>&1
            ;;
        pacman)
            pacman -Qi "$_pkg" >/dev/null 2>&1
            ;;
        zypper)
            rpm -q "$_pkg" >/dev/null 2>&1
            ;;
        apk)
            apk info -e "$_pkg" >/dev/null 2>&1
            ;;
        brew)
            brew list "$_pkg" >/dev/null 2>&1
            ;;
        choco)
            choco list --local-only "$_pkg" 2>/dev/null | grep -qi "$_pkg"
            ;;
        *)
            # Fallback: check if command exists
            rsr_has_command "$_pkg"
            ;;
    esac
}

# Get installed version of a package
# Usage: version=$(rsr_pkg_version "git")
rsr_pkg_version() {
    _pkg="$1"
    _mgr="$(rsr_pkg_manager)"

    case "$_mgr" in
        apt)
            dpkg -l "$_pkg" 2>/dev/null | awk '/^ii/{print $3}'
            ;;
        dnf|yum)
            rpm -q --qf '%{VERSION}\n' "$_pkg" 2>/dev/null
            ;;
        pacman)
            pacman -Qi "$_pkg" 2>/dev/null | awk '/^Version/{print $3}'
            ;;
        apk)
            apk info "$_pkg" 2>/dev/null | head -1
            ;;
        brew)
            brew list --versions "$_pkg" 2>/dev/null | awk '{print $2}'
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# =============================================================================
# Dependency Management
# =============================================================================

# Check for missing dependencies and optionally install
# Usage: rsr_pkg_check_deps "git" "curl" "jq"
# Returns: 0 if all deps available, 1 if missing and not installed
rsr_pkg_check_deps() {
    _missing=""
    _count=0

    for _dep in "$@"; do
        if ! rsr_has_command "$_dep" && ! rsr_pkg_is_installed "$_dep"; then
            _missing="$_missing $_dep"
            _count=$((_count + 1))
        fi
    done

    # Remove leading space
    _missing="${_missing# }"

    # All dependencies present
    [ -z "$_missing" ] && return 0

    rsr_log_warn "Missing dependencies: $_missing"

    # Auto-install if enabled
    if [ "$RSR_PKG_AUTO_INSTALL" = "1" ]; then
        rsr_log_info "Auto-installing dependencies..."
        rsr_pkg_update_cache
        rsr_pkg_install_many $_missing
        return $?
    fi

    # Interactive prompt if enabled
    if [ "$RSR_PKG_CONFIRM" = "1" ] && [ -t 0 ]; then
        printf "${RSR_COLOR_YELLOW}?${RSR_COLOR_RESET} Install missing dependencies? [y/N] "
        read -r _answer
        case "$_answer" in
            [Yy]|[Yy][Ee][Ss])
                rsr_pkg_update_cache
                rsr_pkg_install_many $_missing
                return $?
                ;;
        esac
    fi

    return 1
}

# Require dependencies or die
# Usage: rsr_pkg_require_deps "git" "curl" "jq"
rsr_pkg_require_deps() {
    if ! rsr_pkg_check_deps "$@"; then
        rsr_die "Required dependencies not available" "$RSR_EXIT_DEPENDENCY"
    fi
}

# =============================================================================
# Package Name Mapping (cross-platform)
# =============================================================================

# Map generic package name to distro-specific name
# Usage: actual_pkg=$(rsr_pkg_map_name "httpd")
rsr_pkg_map_name() {
    _generic="$1"
    _mgr="$(rsr_pkg_manager)"

    # Common mappings
    case "$_generic" in
        # Web servers
        httpd|apache)
            case "$_mgr" in
                apt) echo "apache2" ;;
                brew) echo "httpd" ;;
                *) echo "httpd" ;;
            esac
            ;;
        # Development tools
        build-essential)
            case "$_mgr" in
                apt) echo "build-essential" ;;
                dnf|yum) echo "gcc gcc-c++ make" ;;
                pacman) echo "base-devel" ;;
                brew) echo "gcc make" ;;
                apk) echo "build-base" ;;
                *) echo "gcc make" ;;
            esac
            ;;
        # Python
        python)
            case "$_mgr" in
                apt) echo "python3" ;;
                brew) echo "python@3" ;;
                *) echo "python3" ;;
            esac
            ;;
        python-pip|pip)
            case "$_mgr" in
                apt) echo "python3-pip" ;;
                dnf|yum) echo "python3-pip" ;;
                *) echo "python3-pip" ;;
            esac
            ;;
        python-dev)
            case "$_mgr" in
                apt) echo "python3-dev" ;;
                dnf|yum) echo "python3-devel" ;;
                *) echo "python3-dev" ;;
            esac
            ;;
        # Node.js
        nodejs|node)
            case "$_mgr" in
                brew) echo "node" ;;
                *) echo "nodejs" ;;
            esac
            ;;
        # Network tools
        netcat)
            case "$_mgr" in
                apt) echo "netcat-openbsd" ;;
                dnf|yum) echo "nmap-ncat" ;;
                *) echo "netcat" ;;
            esac
            ;;
        # MySQL client
        mysql-client)
            case "$_mgr" in
                apt) echo "mysql-client" ;;
                dnf|yum) echo "mysql" ;;
                brew) echo "mysql-client" ;;
                *) echo "mysql" ;;
            esac
            ;;
        # PostgreSQL client
        postgresql-client)
            case "$_mgr" in
                apt) echo "postgresql-client" ;;
                dnf|yum) echo "postgresql" ;;
                brew) echo "libpq" ;;
                *) echo "postgresql" ;;
            esac
            ;;
        # Default: return as-is
        *)
            echo "$_generic"
            ;;
    esac
}

# =============================================================================
# YAML Package Lists
# =============================================================================

# Parse simple YAML package list (basic parser, no external deps)
# Usage: _rsr_parse_yaml_packages "file.yaml" "category"
_rsr_parse_yaml_packages() {
    _yaml_file="$1"
    _category="${2:-packages}"

    [ ! -f "$_yaml_file" ] && return 1

    # Simple YAML parsing (handles basic lists)
    _in_section=0
    while IFS= read -r _line || [ -n "$_line" ]; do
        # Skip comments and empty lines
        case "$_line" in
            \#*|"") continue ;;
        esac

        # Check for section header
        case "$_line" in
            "${_category}:"*)
                _in_section=1
                continue
                ;;
            [a-zA-Z_]*:*)
                # Different section
                [ "$_in_section" = "1" ] && _in_section=0
                continue
                ;;
        esac

        # Extract packages from list
        if [ "$_in_section" = "1" ]; then
            # Handle "  - package" format
            _pkg=$(echo "$_line" | sed -n 's/^[[:space:]]*-[[:space:]]*\([^#]*\).*/\1/p' | tr -d '"'"'" | xargs)
            [ -n "$_pkg" ] && echo "$_pkg"
        fi
    done < "$_yaml_file"
}

# Install packages from YAML file
# Usage: rsr_pkg_install_from_yaml "packages.yaml" [category]
rsr_pkg_install_from_yaml() {
    _yaml_file="$1"
    _category="${2:-packages}"

    if [ ! -f "$_yaml_file" ]; then
        rsr_log_error "Package list not found: $_yaml_file"
        return 1
    fi

    rsr_log_info "Loading packages from $_yaml_file ($_category)"

    _packages=$(_rsr_parse_yaml_packages "$_yaml_file" "$_category")

    if [ -z "$_packages" ]; then
        rsr_log_warn "No packages found in $_category section"
        return 0
    fi

    # Map package names and collect
    _to_install=""
    for _pkg in $_packages; do
        _mapped=$(rsr_pkg_map_name "$_pkg")
        _to_install="$_to_install $_mapped"
    done
    _to_install="${_to_install# }"

    rsr_log_info "Packages to install: $_to_install"

    if [ "$RSR_PKG_CONFIRM" = "1" ] && [ -t 0 ]; then
        printf "${RSR_COLOR_YELLOW}?${RSR_COLOR_RESET} Proceed with installation? [y/N] "
        read -r _answer
        case "$_answer" in
            [Yy]|[Yy][Ee][Ss]) ;;
            *) rsr_log_info "Installation cancelled"; return 0 ;;
        esac
    fi

    rsr_pkg_update_cache
    rsr_pkg_install_many $_to_install
}

# Install predefined package profile
# Usage: rsr_pkg_install_profile "development"
rsr_pkg_install_profile() {
    _profile="$1"
    _profile_file="${RSR_PKG_LISTS_DIR}/${_profile}.yaml"

    if [ ! -f "$_profile_file" ]; then
        # Try .yml extension
        _profile_file="${RSR_PKG_LISTS_DIR}/${_profile}.yml"
    fi

    if [ ! -f "$_profile_file" ]; then
        rsr_log_error "Profile not found: $_profile"
        rsr_log_info "Available profiles:"
        rsr_pkg_list_profiles
        return 1
    fi

    rsr_log_info "Installing profile: $_profile"
    rsr_pkg_install_from_yaml "$_profile_file"
}

# List available profiles
# Usage: rsr_pkg_list_profiles
rsr_pkg_list_profiles() {
    if [ ! -d "$RSR_PKG_LISTS_DIR" ]; then
        rsr_log_warn "Package lists directory not found: $RSR_PKG_LISTS_DIR"
        return 1
    fi

    for _f in "$RSR_PKG_LISTS_DIR"/*.yaml "$RSR_PKG_LISTS_DIR"/*.yml; do
        [ -f "$_f" ] || continue
        _name=$(basename "$_f" | sed 's/\.ya\?ml$//')
        _desc=$(grep -m1 '^description:' "$_f" 2>/dev/null | sed 's/^description:[[:space:]]*//' | tr -d '"'"'")
        if [ -n "$_desc" ]; then
            printf "  ${RSR_COLOR_CYAN}%-20s${RSR_COLOR_RESET} %s\n" "$_name" "$_desc"
        else
            printf "  ${RSR_COLOR_CYAN}%s${RSR_COLOR_RESET}\n" "$_name"
        fi
    done
}

# =============================================================================
# Cleanup
# =============================================================================

# Clean package manager cache
# Usage: rsr_pkg_clean
rsr_pkg_clean() {
    _mgr="$(rsr_pkg_manager)"
    _sudo="$(_rsr_pkg_sudo)"

    rsr_log_info "Cleaning package cache..."

    case "$_mgr" in
        apt)
            $_sudo apt-get clean
            $_sudo apt-get autoremove -y
            ;;
        dnf)
            $_sudo dnf clean all
            $_sudo dnf autoremove -y
            ;;
        yum)
            $_sudo yum clean all
            ;;
        pacman)
            $_sudo pacman -Sc --noconfirm
            ;;
        zypper)
            $_sudo zypper clean
            ;;
        apk)
            $_sudo apk cache clean
            ;;
        brew)
            brew cleanup
            ;;
        *)
            rsr_log_warn "Unknown package manager: $_mgr"
            ;;
    esac
}

# =============================================================================
# Info & Status
# =============================================================================

# Show package manager info
# Usage: rsr_pkg_info
rsr_pkg_info() {
    _mgr="$(rsr_pkg_manager)"
    _os="$(rsr_detect_os)"
    _distro="$(rsr_detect_distro)"

    printf "${RSR_COLOR_BOLD}Package Manager Info${RSR_COLOR_RESET}\n"
    printf "  OS:              %s\n" "$_os"
    printf "  Distribution:    %s\n" "$_distro"
    printf "  Package Manager: %s\n" "$_mgr"
    printf "  Auto Install:    %s\n" "$RSR_PKG_AUTO_INSTALL"
    printf "  Confirm:         %s\n" "$RSR_PKG_CONFIRM"
    printf "  Lists Dir:       %s\n" "$RSR_PKG_LISTS_DIR"
}

rsr_log_debug "RSR packages module loaded (v${_RSR_PACKAGES_VERSION})"

