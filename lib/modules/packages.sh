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
RSR_PKG_USE_FALLBACK_PARSER="${RSR_PKG_USE_FALLBACK_PARSER:-0}"  # Force pure-shell parser

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
        brew|choco|winget) echo "" ;;  # User-space package managers
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
        winget)
            # winget updates its source automatically
            winget source update --disable-interactivity >/dev/null 2>&1 || true
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
        winget)
            winget install --id "$_pkg" --silent --accept-source-agreements --accept-package-agreements
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
        winget)
            for _p in $_pkgs; do
                winget install --id "$_p" --silent --accept-source-agreements --accept-package-agreements
            done
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
        winget)
            winget uninstall --id "$_pkg" --silent
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
        winget)
            winget list --id "$_pkg" --exact >/dev/null 2>&1
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
        winget)
            winget list --id "$_pkg" --exact 2>/dev/null | awk 'NR==3 {print $3}'
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
# Bootstrap & Core Dependencies
# =============================================================================

# Core tools required for YAML parsing (POSIX standard, should always exist)
_RSR_YAML_CORE_TOOLS="sed grep awk"

# Check if core parsing tools are available
# Returns: 0 if all tools available, 1 if any missing
_rsr_yaml_parser_ready() {
    for _tool in $_RSR_YAML_CORE_TOOLS; do
        if ! command -v "$_tool" >/dev/null 2>&1; then
            return 1
        fi
    done
    return 0
}

# Get list of missing core tools
_rsr_yaml_missing_tools() {
    _missing=""
    for _tool in $_RSR_YAML_CORE_TOOLS; do
        if ! command -v "$_tool" >/dev/null 2>&1; then
            _missing="$_missing $_tool"
        fi
    done
    echo "${_missing# }"
}

# Bootstrap core tools needed for YAML parsing
# This is a minimal installer that works without the full parser
# Usage: _rsr_bootstrap_parser_deps
_rsr_bootstrap_parser_deps() {
    _missing="$(_rsr_yaml_missing_tools)"
    
    if [ -z "$_missing" ]; then
        rsr_log_debug "All YAML parser dependencies available"
        return 0
    fi
    
    rsr_log_warn "Missing core tools for YAML parsing: $_missing"
    rsr_log_info "Attempting to bootstrap core dependencies..."
    
    _mgr="$(rsr_pkg_manager)"
    _sudo="$(_rsr_pkg_sudo)"
    
    case "$_mgr" in
        apt)
            # On Debian/Ubuntu, these are in coreutils/base packages
            for _tool in $_missing; do
                case "$_tool" in
                    sed) $_sudo apt-get install -y -qq sed 2>/dev/null ;;
                    grep) $_sudo apt-get install -y -qq grep 2>/dev/null ;;
                    awk) $_sudo apt-get install -y -qq gawk 2>/dev/null || $_sudo apt-get install -y -qq mawk 2>/dev/null ;;
                esac
            done
            ;;
        dnf|yum)
            for _tool in $_missing; do
                case "$_tool" in
                    sed) $_sudo $_mgr install -y -q sed 2>/dev/null ;;
                    grep) $_sudo $_mgr install -y -q grep 2>/dev/null ;;
                    awk) $_sudo $_mgr install -y -q gawk 2>/dev/null ;;
                esac
            done
            ;;
        brew)
            # On macOS with Homebrew, install GNU versions
            for _tool in $_missing; do
                case "$_tool" in
                    sed) brew install -q gnu-sed 2>/dev/null ;;
                    grep) brew install -q grep 2>/dev/null ;;
                    awk) brew install -q gawk 2>/dev/null ;;
                esac
            done
            ;;
        apk)
            # Alpine Linux
            for _tool in $_missing; do
                $_sudo apk add -q "$_tool" 2>/dev/null
            done
            ;;
        pacman)
            for _tool in $_missing; do
                case "$_tool" in
                    awk) $_sudo pacman -S --noconfirm --needed gawk 2>/dev/null ;;
                    *) $_sudo pacman -S --noconfirm --needed "$_tool" 2>/dev/null ;;
                esac
            done
            ;;
        winget|choco)
            # Windows - these should be available via Git Bash or WSL
            rsr_log_warn "On Windows, ensure Git Bash or WSL is installed for POSIX tools"
            return 1
            ;;
        *)
            rsr_log_error "Cannot bootstrap tools: unknown package manager"
            return 1
            ;;
    esac
    
    # Verify bootstrap succeeded
    if _rsr_yaml_parser_ready; then
        rsr_log_success "Successfully bootstrapped parser dependencies"
        return 0
    else
        rsr_log_error "Failed to install core dependencies: $(_rsr_yaml_missing_tools)"
        return 1
    fi
}

# Ensure parser is ready, bootstrapping if necessary
# Usage: _rsr_ensure_parser_ready
_rsr_ensure_parser_ready() {
    if _rsr_yaml_parser_ready; then
        return 0
    fi
    
    _rsr_bootstrap_parser_deps
}

# =============================================================================
# Pure-Shell Fallback Parser (No External Dependencies)
# =============================================================================
# This parser uses ONLY POSIX shell builtins, no sed/grep/awk required.
# It's slower but works on truly minimal systems before tools are installed.

# Parse simple package list using pure shell builtins
# Usage: _rsr_parse_yaml_pure_shell "file.yaml" "section"
# Returns: one package per line
_rsr_parse_yaml_pure_shell() {
    _yaml_file="$1"
    _section="${2:-packages}"
    
    [ ! -f "$_yaml_file" ] && return 1
    
    _in_section=0
    _indent_level=0
    
    while IFS= read -r _line || [ -n "$_line" ]; do
        # Skip empty lines
        [ -z "$_line" ] && continue
        
        # Skip comments (check first non-space char)
        _first_char="${_line##*( )}"
        _first_char="${_first_char:0:1}"
        case "$_line" in
            *"#"*) 
                # Check if # is at start (after spaces)
                _trimmed="${_line#"${_line%%[![:space:]]*}"}"
                case "$_trimmed" in
                    "#"*) continue ;;
                esac
                ;;
        esac
        
        # Check for section header (e.g., "packages:")
        case "$_line" in
            "${_section}:"*|*" ${_section}:"*)
                _in_section=1
                continue
                ;;
        esac
        
        # Check for different section (ends current section)
        if [ $_in_section -eq 1 ]; then
            # If line starts with letter (no leading space), it's a new section
            _trimmed="${_line#"${_line%%[![:space:]]*}"}"
            case "$_trimmed" in
                [a-zA-Z_]*:*)
                    # Only exit section if it's a top-level key (minimal indentation)
                    _leading="${_line%%[![:space:]]*}"
                    if [ ${#_leading} -lt 2 ]; then
                        _in_section=0
                        continue
                    fi
                    ;;
            esac
        fi
        
        # Extract packages (lines starting with "  - ")
        if [ $_in_section -eq 1 ]; then
            case "$_line" in
                *"- "*)
                    # Extract package name after "- "
                    _pkg="${_line#*- }"
                    # Remove leading/trailing spaces
                    _pkg="${_pkg#"${_pkg%%[![:space:]]*}"}"
                    _pkg="${_pkg%"${_pkg##*[![:space:]]}"}"
                    # Remove quotes
                    _pkg="${_pkg#\"}"
                    _pkg="${_pkg%\"}"
                    _pkg="${_pkg#\'}"
                    _pkg="${_pkg%\'}"
                    # Skip if it's extended format (contains :)
                    case "$_pkg" in
                        *":"*) ;; # Skip extended format in pure-shell mode
                        *) [ -n "$_pkg" ] && printf '%s\n' "$_pkg" ;;
                    esac
                    ;;
            esac
        fi
    done < "$_yaml_file"
}

# =============================================================================
# Bootstrap Functions (Public API)
# =============================================================================

# Bootstrap the system with core tools needed for full functionality
# This uses the pure-shell parser and simple package format
# Usage: rsr_pkg_bootstrap
rsr_pkg_bootstrap() {
    rsr_log_info "Bootstrapping system with core tools..."
    
    # First, try to bootstrap parser dependencies directly
    if ! _rsr_yaml_parser_ready; then
        rsr_log_info "Installing YAML parser dependencies..."
        _rsr_bootstrap_parser_deps
    fi
    
    # Then install bootstrap profile using pure-shell parser if needed
    _bootstrap_file="${RSR_PKG_LISTS_DIR}/bootstrap.yaml"
    
    if [ -f "$_bootstrap_file" ]; then
        # Use pure-shell parser for bootstrap (no external deps required)
        rsr_log_info "Installing bootstrap packages..."
        _packages=$(_rsr_parse_yaml_pure_shell "$_bootstrap_file" "packages")
        
        if [ -n "$_packages" ]; then
            # Convert newlines to spaces for passing to function
            _pkg_list=$(echo "$_packages" | tr '\n' ' ')
            rsr_pkg_bootstrap_install $_pkg_list
        fi
    else
        # Fallback: install core tools directly
        rsr_log_warn "Bootstrap profile not found, installing core tools directly"
        rsr_pkg_bootstrap_install sed grep gawk curl
    fi
    
    # Verify parser is now ready
    if _rsr_yaml_parser_ready; then
        rsr_log_success "Bootstrap complete - full parser available"
        return 0
    else
        rsr_log_warn "Bootstrap complete but some tools still missing"
        return 1
    fi
}

# Check if system needs bootstrapping
# Returns: 0 if bootstrap needed, 1 if system is ready
rsr_pkg_needs_bootstrap() {
    ! _rsr_yaml_parser_ready
}

# Minimal package installation for bootstrapping (pure shell, no YAML parser needed)
# Installs packages from a simple list without YAML parsing
# Usage: rsr_pkg_bootstrap_install pkg1 pkg2 pkg3
rsr_pkg_bootstrap_install() {
    _mgr="$(rsr_pkg_manager)"
    _sudo="$(_rsr_pkg_sudo)"
    
    rsr_log_info "Bootstrap installing: $*"
    
    for _pkg in "$@"; do
        rsr_log_info "Installing $_pkg..."
        case "$_mgr" in
            apt)
                $_sudo apt-get update -qq 2>/dev/null
                $_sudo apt-get install -y -qq "$_pkg" 2>/dev/null
                ;;
            dnf)
                $_sudo dnf install -y -q "$_pkg" 2>/dev/null
                ;;
            yum)
                $_sudo yum install -y -q "$_pkg" 2>/dev/null
                ;;
            pacman)
                $_sudo pacman -Sy --noconfirm --needed "$_pkg" 2>/dev/null
                ;;
            apk)
                $_sudo apk update 2>/dev/null
                $_sudo apk add -q "$_pkg" 2>/dev/null
                ;;
            brew)
                brew install -q "$_pkg" 2>/dev/null
                ;;
            winget)
                winget install --id "$_pkg" --silent --accept-source-agreements --accept-package-agreements 2>/dev/null
                ;;
            choco)
                choco install -y "$_pkg" 2>/dev/null
                ;;
            *)
                rsr_log_warn "Unknown package manager, cannot install $_pkg"
                return 1
                ;;
        esac
    done
}

# =============================================================================
# Group Support (Hierarchical Package Organization)
# =============================================================================

# Parse groups from YAML file and list them
# Usage: _rsr_parse_yaml_group_list "file.yaml" [group_path]
# Returns: group names, one per line
_rsr_parse_yaml_group_list() {
    _yaml_file="$1"
    _group_path="${2:-}"
    
    [ ! -f "$_yaml_file" ] && return 1
    
    # If no group path, we're looking at top-level groups
    if [ -z "$_group_path" ]; then
        # Find all top-level group names under groups:
        grep -A 9999 '^groups:' "$_yaml_file" 2>/dev/null | \
            grep -E '^[[:space:]]{2}[a-zA-Z_][a-zA-Z0-9_-]*:' | \
            sed 's/^[[:space:]]*//' | \
            sed 's/:.*//' | \
            head -100
    else
        # Navigate to specific group path and list subgroups
        # This is a simplified version - handles one level of nesting
        _parent_group="${_group_path%%.*}"
        grep -A 9999 "^[[:space:]]*${_parent_group}:" "$_yaml_file" 2>/dev/null | \
            grep -E '^[[:space:]]{4}[a-zA-Z_][a-zA-Z0-9_-]*:' | \
            sed 's/^[[:space:]]*//' | \
            sed 's/:.*//' | \
            head -100
    fi
}

# Parse packages from a specific group
# Usage: _rsr_parse_yaml_group "file.yaml" "group.subgroup"
# Returns: package names suitable for _rsr_parse_yaml_packages format
_rsr_parse_yaml_group() {
    _yaml_file="$1"
    _group_path="$2"
    
    [ ! -f "$_yaml_file" ] && return 1
    [ -z "$_group_path" ] && return 1
    
    # Split group path (e.g., "languages.python" -> ["languages", "python"])
    _path_parts=""
    _remaining="$_group_path"
    while [ -n "$_remaining" ]; do
        _part="${_remaining%%.*}"
        _path_parts="$_path_parts $_part"
        if echo "$_remaining" | grep -q '\.'; then
            _remaining="${_remaining#*.}"
        else
            _remaining=""
        fi
    done
    
    # Navigate through the path to find the target group
    # For now, handle up to 3 levels: group.subgroup.subsubgroup
    _level=0
    _current_pattern="^groups:"
    _indent=2
    
    for _part in $_path_parts; do
        _level=$((_level + 1))
        # Look for the pattern at current indentation level
        _current_pattern="^[[:space:]]{$_indent}${_part}:"
        _indent=$((_indent + 2))
    done
    
    # Extract packages from the target group
    # Find the group header, then extract until next same-level key
    grep -A 200 "$_current_pattern" "$_yaml_file" 2>/dev/null | \
        sed -n '/packages:/,/^[[:space:]]*[a-zA-Z_]/p' | \
        grep '^[[:space:]]*-' | \
        sed 's/^[[:space:]]*-[[:space:]]*//' | \
        sed 's/#.*//' | \
        tr -d '"' | \
        tr -d "'" | \
        xargs -n1 | \
        grep -v '^$'
}

# Install a specific group from a profile
# Usage: rsr_pkg_install_group "profile" "group.subgroup"
rsr_pkg_install_group() {
    _profile="$1"
    _group_path="$2"
    
    _profile_file="${RSR_PKG_LISTS_DIR}/${_profile}.yaml"
    
    if [ ! -f "$_profile_file" ]; then
        rsr_log_error "Profile not found: $_profile"
        return 1
    fi
    
    rsr_log_info "Installing group: $_profile.$_group_path"
    
    # Parse packages from the group
    _packages=$(_rsr_parse_yaml_group "$_profile_file" "$_group_path")
    
    if [ -z "$_packages" ]; then
        rsr_log_warn "No packages found in group: $_group_path"
        return 0
    fi
    
    rsr_pkg_update_cache
    
    # Install each package
    _failed_packages=""
    _success_count=0
    
    for _pkg in $_packages; do
        _mapped=$(rsr_pkg_map_name "$_pkg")
        rsr_log_info "Installing $_pkg..."
        if rsr_pkg_install "$_mapped"; then
            _success_count=$((_success_count + 1))
        else
            _failed_packages="$_failed_packages $_pkg"
        fi
    done
    
    # Summary
    if [ $_success_count -gt 0 ]; then
        rsr_log_success "Successfully installed $_success_count package(s) from group"
    fi
    
    if [ -n "$_failed_packages" ]; then
        rsr_log_warn "Failed to install:$_failed_packages"
        return 1
    fi
    
    return 0
}

# List all groups in a profile
# Usage: rsr_pkg_list_groups "profile"
rsr_pkg_list_groups() {
    _profile="$1"
    _profile_file="${RSR_PKG_LISTS_DIR}/${_profile}.yaml"
    
    if [ ! -f "$_profile_file" ]; then
        rsr_log_error "Profile not found: $_profile"
        return 1
    fi
    
    rsr_log_info "Groups in $_profile:"
    
    _groups=$(_rsr_parse_yaml_group_list "$_profile_file")
    
    if [ -z "$_groups" ]; then
        rsr_log_info "  No groups defined (flat profile)"
        return 0
    fi
    
    for _group in $_groups; do
        # Get description if available
        _desc=$(grep -A 1 "^[[:space:]]*${_group}:" "$_profile_file" 2>/dev/null | \
                grep 'description:' | \
                sed 's/.*description:[[:space:]]*//' | \
                tr -d '"')
        
        if [ -n "$_desc" ]; then
            printf "  ${RSR_COLOR_CYAN}%-20s${RSR_COLOR_RESET} %s\n" "$_group" "$_desc"
        else
            printf "  ${RSR_COLOR_CYAN}%s${RSR_COLOR_RESET}\n" "$_group"
        fi
        
        # List subgroups (one level deep)
        _subgroups=$(_rsr_parse_yaml_group_list "$_profile_file" "$_group")
        for _subgroup in $_subgroups; do
            printf "    ${RSR_COLOR_DIM}├── %s${RSR_COLOR_RESET}\n" "$_subgroup"
        done
    done
}

# =============================================================================
# YAML Package Lists
# =============================================================================

# Parse simple YAML package list (basic parser, no external deps)
# Uses only POSIX shell builtins + sed/grep/awk (bootstrapped if missing)
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

    # Ensure YAML parser dependencies are available
    if ! _rsr_ensure_parser_ready; then
        rsr_log_error "Cannot parse YAML: missing core tools and bootstrap failed"
        rsr_log_info "Please manually install: sed, grep, awk"
        return 1
    fi

    rsr_log_info "Loading packages from $_yaml_file ($_category)"

    # Update cache once before installations
    rsr_pkg_update_cache

    # Parse packages with line numbers for extended format support
    _in_section=0
    _line_num=0
    _failed_packages=""
    _success_count=0
    
    while IFS= read -r _line || [ -n "$_line" ]; do
        _line_num=$((_line_num + 1))
        
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

        # Process packages in section
        if [ "$_in_section" = "1" ]; then
            # Check if line starts with dash (package entry)
            if echo "$_line" | grep -q '^[[:space:]]*-'; then
                # Check for extended format
                if echo "$_line" | grep -q 'name:\|brew:\|brew_cask:\|winget:\|apt:\|choco:'; then
                    # Extended format - extract package info
                    _pkg_info=$(_rsr_extract_package_methods "$_yaml_file" "$_line_num")
                    _pkg_name="${_pkg_info%%|*}"
                    _methods="${_pkg_info#*|}"
                    
                    if [ -n "$_pkg_name" ] && [ -n "$_methods" ]; then
                        rsr_log_info "Installing $_pkg_name (multi-method)..."
                        if rsr_pkg_try_methods "$_pkg_name" $_methods; then
                            _success_count=$((_success_count + 1))
                        else
                            _failed_packages="$_failed_packages $_pkg_name"
                        fi
                    fi
                else
                    # Simple format
                    _pkg=$(echo "$_line" | sed -n 's/^[[:space:]]*-[[:space:]]*\([^#]*\).*/\1/p' | tr -d '"'"'" | xargs)
                    if [ -n "$_pkg" ]; then
                        _mapped=$(rsr_pkg_map_name "$_pkg")
                        rsr_log_info "Installing $_pkg..."
                        if rsr_pkg_install "$_mapped"; then
                            _success_count=$((_success_count + 1))
                        else
                            _failed_packages="$_failed_packages $_pkg"
                        fi
                    fi
                fi
            fi
        fi
    done < "$_yaml_file"
    
    # Summary
    if [ $_success_count -gt 0 ]; then
        rsr_log_success "Successfully installed $_success_count package(s)"
    fi
    
    if [ -n "$_failed_packages" ]; then
        rsr_log_warn "Failed to install:$_failed_packages"
        return 1
    fi
    
    return 0
}

# Install predefined package profile or group
# Usage: rsr_pkg_install_profile "development" or "development.languages.python"
rsr_pkg_install_profile() {
    _input="$1"
    
    # Check if input contains dot (group notation)
    if echo "$_input" | grep -q '\.'; then
        # Extract profile name and group path
        _profile="${_input%%.*}"
        _group_path="${_input#*.}"
        
        # Install specific group
        rsr_pkg_install_group "$_profile" "$_group_path"
        return $?
    fi
    
    # Install entire profile (no group specified)
    _profile="$_input"
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
# Multi-Method Installation Support
# =============================================================================

# Get available installation methods for current system
# Returns: space-separated list of available methods
rsr_pkg_available_methods() {
    _methods=""
    
    # Check for package managers
    rsr_has_command apt-get && _methods="$_methods apt"
    rsr_has_command dnf && _methods="$_methods dnf"
    rsr_has_command yum && _methods="$_methods yum"
    rsr_has_command pacman && _methods="$_methods pacman"
    rsr_has_command zypper && _methods="$_methods zypper"
    rsr_has_command apk && _methods="$_methods apk"
    rsr_has_command brew && _methods="$_methods brew"
    rsr_has_command winget && _methods="$_methods winget"
    rsr_has_command choco && _methods="$_methods choco"
    
    # Script method always available
    _methods="$_methods script"
    
    echo "${_methods# }"
}

# Install package using specific method
# Usage: rsr_pkg_install_with_method "package_name" "method" [method_specific_name]
rsr_pkg_install_with_method() {
    _pkg="$1"
    _method="$2"
    _method_pkg="${3:-$_pkg}"
    
    rsr_log_debug "Attempting to install $_pkg using method: $_method"
    
    case "$_method" in
        apt)
            rsr_has_command apt-get || return 1
            _sudo="$(_rsr_pkg_sudo)"
            $_sudo apt-get install -y -qq "$_method_pkg" 2>/dev/null
            ;;
        dnf)
            rsr_has_command dnf || return 1
            _sudo="$(_rsr_pkg_sudo)"
            $_sudo dnf install -y -q "$_method_pkg" 2>/dev/null
            ;;
        yum)
            rsr_has_command yum || return 1
            _sudo="$(_rsr_pkg_sudo)"
            $_sudo yum install -y -q "$_method_pkg" 2>/dev/null
            ;;
        pacman)
            rsr_has_command pacman || return 1
            _sudo="$(_rsr_pkg_sudo)"
            $_sudo pacman -S --noconfirm --needed "$_method_pkg" 2>/dev/null
            ;;
        zypper)
            rsr_has_command zypper || return 1
            _sudo="$(_rsr_pkg_sudo)"
            $_sudo zypper install -y -q "$_method_pkg" 2>/dev/null
            ;;
        apk)
            rsr_has_command apk || return 1
            _sudo="$(_rsr_pkg_sudo)"
            $_sudo apk add -q "$_method_pkg" 2>/dev/null
            ;;
        brew)
            rsr_has_command brew || return 1
            brew install -q "$_method_pkg" 2>/dev/null
            ;;
        brew_cask)
            rsr_has_command brew || return 1
            brew install --cask -q "$_method_pkg" 2>/dev/null
            ;;
        winget)
            rsr_has_command winget || return 1
            winget install --id "$_method_pkg" --silent --accept-source-agreements --accept-package-agreements 2>/dev/null
            ;;
        choco)
            rsr_has_command choco || return 1
            choco install -y "$_method_pkg" 2>/dev/null
            ;;
        script)
            # Script method requires the script to be provided
            if [ -n "$_method_pkg" ]; then
                eval "$_method_pkg"
            else
                rsr_log_error "No installation script provided for $_pkg"
                return 1
            fi
            ;;
        *)
            rsr_log_error "Unknown installation method: $_method"
            return 1
            ;;
    esac
}

# Try multiple methods in order until one succeeds
# Usage: rsr_pkg_try_methods "package_name" "method1:pkg1" "method2:pkg2" ...
rsr_pkg_try_methods() {
    _pkg="$1"
    shift
    
    _methods_tried=""
    
    for _method_spec in "$@"; do
        # Parse method:package format
        _method="${_method_spec%%:*}"
        _method_pkg="${_method_spec#*:}"
        
        # If no colon, use package name as-is
        [ "$_method" = "$_method_pkg" ] && _method_pkg="$_pkg"
        
        _methods_tried="$_methods_tried $_method"
        
        rsr_log_debug "Trying method $_method for $_pkg"
        
        if rsr_pkg_install_with_method "$_pkg" "$_method" "$_method_pkg"; then
            rsr_log_success "Installed $_pkg using $_method"
            return 0
        fi
    done
    
    rsr_log_error "Failed to install $_pkg. Tried methods:$_methods_tried"
    return 1
}

# Parse extended package format from YAML line
# Returns: package_name or extended format JSON-like string
# Usage: _rsr_parse_package_line "  - name: kubectl"
_rsr_parse_package_line() {
    _line="$1"
    
    # Check if it's simple format (just "- package")
    if echo "$_line" | grep -q '^[[:space:]]*-[[:space:]]*[a-zA-Z0-9_-]*[[:space:]]*$'; then
        # Simple format
        echo "$_line" | sed -n 's/^[[:space:]]*-[[:space:]]*\([^#[:space:]]*\).*/\1/p'
        return 0
    fi
    
    # Check for extended format indicators
    if echo "$_line" | grep -q 'name:\|brew:\|brew_cask:\|winget:\|apt:\|choco:'; then
        # Extended format - return the line for further processing
        echo "EXTENDED:$_line"
        return 0
    fi
    
    # Default: treat as simple format
    echo "$_line" | sed -n 's/^[[:space:]]*-[[:space:]]*\([^#]*\).*/\1/p' | tr -d '"'"'" | xargs
}

# Extract methods from extended package definition
# Usage: _rsr_extract_package_methods "yaml_file" "start_line"
# Reads multi-line package definition and extracts method:package pairs
_rsr_extract_package_methods() {
    _yaml_file="$1"
    _start_line="$2"
    _pkg_name=""
    _methods=""
    
    # Read lines starting from _start_line until we hit another package or section
    _line_num=0
    _in_package=0
    
    while IFS= read -r _line || [ -n "$_line" ]; do
        _line_num=$((_line_num + 1))
        
        # Skip until we reach start line
        [ $_line_num -lt $_start_line ] && continue
        
        # Stop if we hit another package or section
        if [ $_in_package -eq 1 ]; then
            # Check if line starts a new package or section
            if echo "$_line" | grep -q '^[[:space:]]*-' || echo "$_line" | grep -q '^[a-zA-Z]'; then
                break
            fi
        fi
        
        # Parse the line
        case "$_line" in
            *name:*)
                _in_package=1
                _pkg_name=$(echo "$_line" | sed 's/.*name:[[:space:]]*\([^[:space:]#]*\).*/\1/' | tr -d '"'"'")
                ;;
            *brew:*)
                _method_pkg=$(echo "$_line" | sed 's/.*brew:[[:space:]]*\([^[:space:]#]*\).*/\1/' | tr -d '"'"'")
                _methods="$_methods brew:$_method_pkg"
                ;;
            *brew_cask:*)
                _method_pkg=$(echo "$_line" | sed 's/.*brew_cask:[[:space:]]*\([^[:space:]#]*\).*/\1/' | tr -d '"'"'")
                _methods="$_methods brew_cask:$_method_pkg"
                ;;
            *winget:*)
                _method_pkg=$(echo "$_line" | sed 's/.*winget:[[:space:]]*\([^[:space:]#]*\).*/\1/' | tr -d '"'"'")
                _methods="$_methods winget:$_method_pkg"
                ;;
            *apt:*)
                _method_pkg=$(echo "$_line" | sed 's/.*apt:[[:space:]]*\([^[:space:]#]*\).*/\1/' | tr -d '"'"'")
                _methods="$_methods apt:$_method_pkg"
                ;;
            *dnf:*)
                _method_pkg=$(echo "$_line" | sed 's/.*dnf:[[:space:]]*\([^[:space:]#]*\).*/\1/' | tr -d '"'"'")
                _methods="$_methods dnf:$_method_pkg"
                ;;
            *choco:*)
                _method_pkg=$(echo "$_line" | sed 's/.*choco:[[:space:]]*\([^[:space:]#]*\).*/\1/' | tr -d '"'"'")
                _methods="$_methods choco:$_method_pkg"
                ;;
        esac
        
        # Stop if line is empty and we're in a package (end of package definition)
        [ $_in_package -eq 1 ] && [ -z "$_line" ] && break
    done < "$_yaml_file"
    
    # Return format: package_name|method1:pkg1 method2:pkg2 ...
    echo "${_pkg_name}|${_methods# }"
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
        winget)
            # winget doesn't have a traditional cache cleanup
            rsr_log_info "winget manages cache automatically"
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

