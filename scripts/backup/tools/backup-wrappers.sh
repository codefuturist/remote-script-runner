#!/usr/bin/env bash
# =============================================================================
# @name         backup-wrappers
# @description  Manage config-driven backup wrappers (autorestic, borgmatic, resticprofile)
# @version      1.0.0
# @author       RSR Team
# @license      MIT
# @requires     bash 4.0+
# =============================================================================
#
# Unified management for config-driven backup solutions:
#   - autorestic (restic wrapper)
#   - borgmatic (borg wrapper)
#   - resticprofile (restic profiles)
#   - kopia (native config)
#
# Usage:
#   backup-wrappers.sh status              # Show installed wrappers
#   backup-wrappers.sh install autorestic  # Install a wrapper
#   backup-wrappers.sh init autorestic     # Generate config template
#   backup-wrappers.sh run autorestic      # Run backup
#   backup-wrappers.sh check borgmatic     # Verify backup
#
# =============================================================================

set -eo pipefail

# =============================================================================
# RSR Library
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [ -n "${SCRIPT_SOURCE}" ] && [ "${SCRIPT_SOURCE}" != "bash" ] && [ "${SCRIPT_SOURCE}" != "sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2> /dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"
RSR_CONFIG_DIR="${SCRIPT_DIR}/../../../config"

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh"
else
    # Minimal fallback
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
fi

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_NAME="Backup Wrappers"
readonly SCRIPT_VERSION="1.0.0"

# Supported wrappers: backend:description
declare -A WRAPPERS=(
    [autorestic]="restic:Config-driven restic wrapper"
    [borgmatic]="borg:Config-driven borg wrapper"
    [resticprofile]="restic:Enterprise restic profiles"
    [kopia]="kopia:Native Kopia with config"
    [rustic]="rustic:Rust restic alternative with YAML"
)

# UI packages available for wrappers
declare -A WRAPPER_UI=(
    [autorestic]="restic-browser:Restic Browser - GUI for browsing repositories"
    [borgmatic]="vorta:Vorta - Desktop backup client for Borg"
    [resticprofile]=""
    [kopia]="kopia-ui:Kopia UI - Full-featured backup GUI"
    [rustic]=""
)

# Default config locations
declare -A CONFIG_PATHS=(
    [autorestic]="${HOME}/.autorestic.yml"
    [borgmatic]="${HOME}/.config/borgmatic/config.yaml"
    [resticprofile]="${HOME}/.config/resticprofile/profiles.yaml"
    [kopia]="${HOME}/.config/kopia/repository.config"
    [rustic]="${HOME}/.config/rustic/rustic.toml"
)

# Template locations
TEMPLATE_DIR="${RSR_CONFIG_DIR}/backup/templates"

# Options
VERBOSE=false
DRY_RUN=false
QUIET=false
WITH_UI=false
COMMAND=""
WRAPPER=""
PROFILE=""
LOCATION=""

# =============================================================================
# Logging
# =============================================================================

log_info() { [[ "$QUIET" != "true" ]] && echo -e "${BLUE:-}▸${NC:-} $1"; }
log_ok() { echo -e "${GREEN:-}✓${NC:-} $1"; }
log_warn() { echo -e "${YELLOW:-}⚠${NC:-} $1" >&2; }
log_error() { echo -e "${RED:-}✗${NC:-} $1" >&2; }
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "  $1"; }

print_header() {
    [[ "$QUIET" != "true" ]] && echo -e "\n${BOLD:-}${CYAN:-}═══ $1 ═══${NC:-}\n"
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    RSR Backup Wrappers Management                            ║
╚══════════════════════════════════════════════════════════════════════════════╝

Manage config-driven backup solutions with YAML/TOML configuration files.

USAGE:
    backup-wrappers.sh                      # Launch interactive mode (default)
    backup-wrappers.sh [COMMAND] [WRAPPER] [OPTIONS]

COMMANDS:
    (no command)        Launch interactive menu (default when no args)
    status              Show installed wrappers and their status
    install WRAPPER     Install a backup wrapper
    init WRAPPER        Generate config template for wrapper
    run WRAPPER         Run backup using wrapper
    check WRAPPER       Verify/check backup integrity
    list WRAPPER        List backups/snapshots
    restore WRAPPER     Restore from backup
    schedule WRAPPER    Set up scheduled backups
    config WRAPPER      Edit wrapper configuration
    docs WRAPPER        Show wrapper documentation

SUPPORTED WRAPPERS:
    autorestic          Config-driven restic wrapper (YAML)
                        https://autorestic.vercel.app

    borgmatic           Config-driven borg wrapper (YAML)
                        https://torsion.org/borgmatic

    resticprofile       Enterprise restic profiles (YAML)
                        https://creativeprojects.github.io/resticprofile

    kopia               Kopia with built-in config
                        https://kopia.io

    rustic              Rust restic alternative (TOML)
                        https://rustic.cli.rs

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress non-essential output
    -d, --dry-run       Show what would be done
    -p, --profile NAME  Specify profile/location name
    -a, --all           Run for all profiles/locations
    --with-ui           Install GUI package where available (vorta, kopia-ui, etc.)

AVAILABLE UI PACKAGES:
    borgmatic           vorta - Desktop backup client for Borg
    kopia               kopia-ui - Full-featured backup GUI with scheduling
    autorestic          restic-browser - GUI for browsing restic repositories

EXAMPLES:
    # Check what's installed
    backup-wrappers.sh status

    # Install autorestic
    backup-wrappers.sh install autorestic

    # Install borgmatic with Vorta GUI
    backup-wrappers.sh install borgmatic --with-ui

    # Install kopia with GUI
    backup-wrappers.sh install kopia --with-ui

    # Generate config template
    backup-wrappers.sh init autorestic

    # Run backup
    backup-wrappers.sh run autorestic
    backup-wrappers.sh run autorestic -p home
    backup-wrappers.sh run autorestic --all

    # Check backups
    backup-wrappers.sh check borgmatic

    # List snapshots
    backup-wrappers.sh list resticprofile -p default

    # Set up scheduling
    backup-wrappers.sh schedule autorestic

CONFIG FILE LOCATIONS:
    autorestic:     ~/.autorestic.yml
    borgmatic:      ~/.config/borgmatic/config.yaml
    resticprofile:  ~/.config/resticprofile/profiles.yaml
    kopia:          ~/.config/kopia/repository.config
    rustic:         ~/.config/rustic/rustic.toml

EOF
}

# =============================================================================
# Wrapper Detection
# =============================================================================

wrapper_installed() {
    local wrapper="$1"
    command -v "$wrapper" &> /dev/null
}

wrapper_backend_installed() {
    local wrapper="$1"
    local backend="${WRAPPERS[$wrapper]%%:*}"
    command -v "$backend" &> /dev/null
}

wrapper_config_exists() {
    local wrapper="$1"
    local config_path="${CONFIG_PATHS[$wrapper]}"
    [[ -f "$config_path" ]]
}

get_wrapper_version() {
    local wrapper="$1"
    case "$wrapper" in
        autorestic)
            autorestic --version 2> /dev/null | head -1 | awk '{print $NF}'
            ;;
        borgmatic)
            borgmatic --version 2> /dev/null | head -1
            ;;
        resticprofile)
            resticprofile version 2> /dev/null | head -1 | awk '{print $2}'
            ;;
        kopia)
            kopia --version 2> /dev/null | awk '{print $1}'
            ;;
        rustic)
            rustic --version 2> /dev/null | awk '{print $2}'
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# =============================================================================
# Command: status
# =============================================================================

cmd_status() {
    print_header "Backup Wrappers Status"

    printf "  %-15s %-12s %-10s %-8s %s\n" "WRAPPER" "VERSION" "BACKEND" "CONFIG" "DESCRIPTION"
    printf "  %-15s %-12s %-10s %-8s %s\n" "───────" "───────" "───────" "──────" "───────────"

    for wrapper in "${!WRAPPERS[@]}"; do
        local info="${WRAPPERS[$wrapper]}"
        local backend="${info%%:*}"
        local desc="${info#*:}"

        local version="-"
        local backend_status="${RED:-}✗${NC:-}"
        local config_status="${RED:-}✗${NC:-}"

        if wrapper_installed "$wrapper"; then
            version=$(get_wrapper_version "$wrapper")
        fi

        if wrapper_backend_installed "$wrapper"; then
            backend_status="${GREEN:-}✓${NC:-}"
        fi

        if wrapper_config_exists "$wrapper"; then
            config_status="${GREEN:-}✓${NC:-}"
        fi

        if wrapper_installed "$wrapper"; then
            printf "  ${GREEN:-}%-15s${NC:-} %-12s %b %-7s %b %-5s %s\n" \
                "$wrapper" "$version" "$backend_status" "$backend" "$config_status" "" "$desc"
        else
            printf "  ${YELLOW:-}%-15s${NC:-} %-12s %b %-7s %b %-5s %s\n" \
                "$wrapper" "(not installed)" "$backend_status" "$backend" "$config_status" "" "$desc"
        fi
    done

    echo ""

    # Recommendations
    if ! wrapper_installed "autorestic" && ! wrapper_installed "borgmatic" && ! wrapper_installed "resticprofile"; then
        log_warn "No config-driven backup wrappers installed"
        echo ""
        echo "Install one with:"
        echo "  backup-wrappers.sh install autorestic    # Simple, YAML-based"
        echo "  backup-wrappers.sh install borgmatic     # Feature-rich, YAML-based"
        echo "  backup-wrappers.sh install resticprofile # Enterprise, cross-platform"
    fi
}

# =============================================================================
# Command: install
# =============================================================================

cmd_install() {
    if [[ -z "$WRAPPER" ]]; then
        log_error "Wrapper name required"
        echo "Available: ${!WRAPPERS[*]}"
        exit 1
    fi

    if [[ -z "${WRAPPERS[$WRAPPER]:-}" ]]; then
        log_error "Unknown wrapper: $WRAPPER"
        echo "Available: ${!WRAPPERS[*]}"
        exit 1
    fi

    local backend="${WRAPPERS[$WRAPPER]%%:*}"

    print_header "Installing $WRAPPER"

    # Check if already installed
    if wrapper_installed "$WRAPPER"; then
        local version=$(get_wrapper_version "$WRAPPER")
        log_warn "$WRAPPER is already installed (version: $version)"
        return 0
    fi

    # Detect OS and package manager
    local os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run - would install $WRAPPER"
        return 0
    fi

    log_info "Installing $WRAPPER..."

    case "$WRAPPER" in
        autorestic)
            # Also need restic
            if ! command -v restic &> /dev/null; then
                log_info "Installing restic (required backend)..."
                install_package "restic"
            fi

            if [[ "$os" == "darwin" ]]; then
                brew install autorestic
            else
                curl -s https://raw.githubusercontent.com/cupcakearmy/autorestic/master/install.sh | bash
            fi
            ;;

        borgmatic)
            # Also need borg
            if ! command -v borg &> /dev/null; then
                log_info "Installing borgbackup (required backend)..."
                install_package "borgbackup"
            fi

            if [[ "$os" == "darwin" ]]; then
                brew install borgmatic
            elif command -v pip3 &> /dev/null; then
                pip3 install --user borgmatic
            else
                log_error "pip3 required to install borgmatic"
                exit 1
            fi
            ;;

        resticprofile)
            # Also need restic
            if ! command -v restic &> /dev/null; then
                log_info "Installing restic (required backend)..."
                install_package "restic"
            fi

            if [[ "$os" == "darwin" ]]; then
                brew install creativeprojects/tap/resticprofile
            else
                curl -sfL https://raw.githubusercontent.com/creativeprojects/resticprofile/master/install.sh | bash
            fi
            ;;

        kopia)
            if [[ "$os" == "darwin" ]]; then
                brew install kopia
            else
                curl -sL https://kopia.io/setup.sh | sudo bash
            fi
            ;;

        rustic)
            if [[ "$os" == "darwin" ]]; then
                brew install rustic-rs/rustic/rustic-rs
            elif command -v cargo &> /dev/null; then
                cargo install rustic-rs
            else
                curl -sL https://github.com/rustic-rs/rustic/releases/latest/download/rustic-linux-x86_64.tar.gz \
                    | sudo tar xz -C /usr/local/bin
            fi
            ;;
    esac

    if wrapper_installed "$WRAPPER"; then
        log_ok "$WRAPPER installed successfully"

        # Install UI package if requested
        if [[ "$WITH_UI" == "true" ]]; then
            install_ui_package "$WRAPPER"
        fi

        echo ""
        echo "Next steps:"
        echo "  backup-wrappers.sh init $WRAPPER    # Generate config template"
        echo "  backup-wrappers.sh run $WRAPPER     # Run backup"

        # Suggest UI if available but not installed
        if [[ "$WITH_UI" != "true" ]] && [[ -n "${WRAPPER_UI[$WRAPPER]:-}" ]]; then
            local ui_name="${WRAPPER_UI[$WRAPPER]%%:*}"
            local ui_desc="${WRAPPER_UI[$WRAPPER]#*:}"
            echo ""
            log_info "GUI available: $ui_name - $ui_desc"
            echo "  Install with: backup-wrappers.sh install $WRAPPER --with-ui"
        fi
    else
        log_error "Failed to install $WRAPPER"
        exit 1
    fi
}

# Install UI package for a wrapper
install_ui_package() {
    local wrapper="$1"
    local ui_info="${WRAPPER_UI[$wrapper]:-}"

    if [[ -z "$ui_info" ]]; then
        log_warn "No UI package available for $wrapper"
        return 0
    fi

    local ui_name="${ui_info%%:*}"
    local ui_desc="${ui_info#*:}"
    local os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    log_info "Installing UI package: $ui_name ($ui_desc)"

    case "$ui_name" in
        vorta)
            # Vorta - Desktop backup client for Borg
            if [[ "$os" == "darwin" ]]; then
                brew install --cask vorta
            elif command -v flatpak &> /dev/null; then
                flatpak install -y flathub com.borgbase.Vorta
            elif command -v pip3 &> /dev/null; then
                pip3 install --user vorta
            else
                log_warn "Install Vorta manually from: https://vorta.borgbase.com"
            fi
            ;;
        kopia-ui)
            # Kopia UI
            if [[ "$os" == "darwin" ]]; then
                brew install --cask kopiaui
            elif command -v flatpak &> /dev/null; then
                flatpak install -y flathub io.kopia.KopiaUI
            else
                log_warn "Install Kopia UI manually from: https://kopia.io/docs/installation/"
            fi
            ;;
        restic-browser)
            # Restic Browser - GUI for browsing restic repos
            if [[ "$os" == "darwin" ]]; then
                brew install --cask restic-browser 2> /dev/null \
                    || log_warn "Install Restic Browser from: https://github.com/emuell/restic-browser/releases"
            elif command -v flatpak &> /dev/null; then
                flatpak install -y flathub io.github.emuell.restic-browser 2> /dev/null \
                    || log_warn "Install Restic Browser from: https://github.com/emuell/restic-browser/releases"
            else
                log_warn "Install Restic Browser from: https://github.com/emuell/restic-browser/releases"
            fi
            ;;
        *)
            log_warn "Unknown UI package: $ui_name"
            ;;
    esac

    log_ok "UI package installation attempted: $ui_name"
}

install_package() {
    local pkg="$1"
    local os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    if [[ "$os" == "darwin" ]]; then
        brew install "$pkg"
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y "$pkg"
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y "$pkg"
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm "$pkg"
    else
        log_error "Unable to install $pkg - unknown package manager"
        return 1
    fi
}

# =============================================================================
# Command: init
# =============================================================================

cmd_init() {
    if [[ -z "$WRAPPER" ]]; then
        log_error "Wrapper name required"
        exit 1
    fi

    local config_path="${CONFIG_PATHS[$WRAPPER]}"
    local template_file=""

    case "$WRAPPER" in
        autorestic) template_file="$TEMPLATE_DIR/autorestic.yaml" ;;
        borgmatic) template_file="$TEMPLATE_DIR/borgmatic.yaml" ;;
        resticprofile) template_file="$TEMPLATE_DIR/resticprofile.yaml" ;;
        kopia) template_file="$TEMPLATE_DIR/kopia.config" ;;
        *)
            log_error "No template available for: $WRAPPER"
            exit 1
            ;;
    esac

    print_header "Initializing $WRAPPER Configuration"

    log_info "Config path: $config_path"
    log_info "Template: $template_file"

    if [[ -f "$config_path" ]]; then
        log_warn "Config already exists: $config_path"
        read -rp "Overwrite? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            log_info "Cancelled"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run - would create $config_path"
        return 0
    fi

    # Create directory
    mkdir -p "$(dirname "$config_path")"

    # Copy template
    if [[ -f "$template_file" ]]; then
        cp "$template_file" "$config_path"
        log_ok "Created config: $config_path"
    else
        # Generate basic config
        case "$WRAPPER" in
            autorestic)
                cat > "$config_path" << 'YAML'
version: 2

backends:
  local:
    type: local
    path: /backup/restic-repo
    key: ${RESTIC_PASSWORD}

locations:
  home:
    from: ${HOME}
    to:
      - local
    options:
      backup:
        exclude:
          - ".cache"
          - "node_modules"
          - ".venv"
YAML
                ;;
            borgmatic)
                borgmatic config generate 2> /dev/null || cat > "$config_path" << 'YAML'
source_directories:
  - ${HOME}

repositories:
  - path: /backup/borg-repo

exclude_patterns:
  - .cache
  - node_modules
  - .venv

keep_daily: 7
keep_weekly: 4
keep_monthly: 6
YAML
                ;;
            resticprofile)
                cat > "$config_path" << 'YAML'
version: "1"

default:
  repository: /backup/restic-repo
  password-file: ~/.config/resticprofile/.password

  retention:
    keep-daily: 7
    keep-weekly: 4
    keep-monthly: 6

  backup:
    source:
      - ${HOME}
    exclude:
      - .cache
      - node_modules
      - .venv
YAML
                # Generate password file
                local pw_file="${HOME}/.config/resticprofile/.password"
                if [[ ! -f "$pw_file" ]]; then
                    mkdir -p "$(dirname "$pw_file")"
                    head -c 32 /dev/urandom | base64 > "$pw_file"
                    chmod 600 "$pw_file"
                    log_ok "Generated password file: $pw_file"
                fi
                ;;
        esac
        log_ok "Created config: $config_path"
    fi

    echo ""
    echo "Next steps:"
    echo "  1. Edit the config: $config_path"
    echo "  2. Initialize repository:"
    case "$WRAPPER" in
        autorestic) echo "     autorestic check" ;;
        borgmatic) echo "     borgmatic init --encryption repokey-blake2" ;;
        resticprofile) echo "     resticprofile init" ;;
    esac
    echo "  3. Run first backup:"
    echo "     backup-wrappers.sh run $WRAPPER"
}

# =============================================================================
# Command: run
# =============================================================================

cmd_run() {
    if [[ -z "$WRAPPER" ]]; then
        # Auto-detect installed wrapper with config
        for w in autorestic resticprofile borgmatic kopia; do
            if wrapper_installed "$w" && wrapper_config_exists "$w"; then
                WRAPPER="$w"
                log_info "Auto-detected: $WRAPPER"
                break
            fi
        done
    fi

    if [[ -z "$WRAPPER" ]]; then
        log_error "No wrapper specified and none auto-detected"
        echo "Install one with: backup-wrappers.sh install autorestic"
        exit 1
    fi

    if ! wrapper_installed "$WRAPPER"; then
        log_error "$WRAPPER is not installed"
        echo "Install with: backup-wrappers.sh install $WRAPPER"
        exit 1
    fi

    print_header "Running Backup with $WRAPPER"

    local cmd_args=()

    if [[ "$VERBOSE" == "true" ]]; then
        cmd_args+=("-v")
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run mode"
    fi

    case "$WRAPPER" in
        autorestic)
            if [[ -n "$PROFILE" ]]; then
                cmd_args+=("-l" "$PROFILE")
            elif [[ -n "$LOCATION" ]]; then
                cmd_args+=("-l" "$LOCATION")
            else
                cmd_args+=("-a") # All locations
            fi

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "Would run: autorestic backup ${cmd_args[*]}"
            else
                autorestic backup "${cmd_args[@]}"
            fi
            ;;

        borgmatic)
            if [[ "$VERBOSE" == "true" ]]; then
                cmd_args+=("--verbosity" "1")
            fi

            if [[ "$DRY_RUN" == "true" ]]; then
                cmd_args+=("--dry-run")
            fi

            borgmatic "${cmd_args[@]}"
            ;;

        resticprofile)
            if [[ -n "$PROFILE" ]]; then
                cmd_args+=("-n" "$PROFILE")
            fi

            if [[ "$DRY_RUN" == "true" ]]; then
                cmd_args+=("--dry-run")
            fi

            resticprofile "${cmd_args[@]}" backup
            ;;

        kopia)
            local sources=("${HOME}")

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "Would run: kopia snapshot create ${sources[*]}"
            else
                kopia snapshot create "${sources[@]}"
            fi
            ;;

        rustic)
            if [[ "$DRY_RUN" == "true" ]]; then
                cmd_args+=("--dry-run")
            fi

            rustic backup "${cmd_args[@]}"
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        log_ok "Backup completed successfully"
    else
        log_error "Backup failed"
        exit 1
    fi
}

# =============================================================================
# Command: check
# =============================================================================

cmd_check() {
    if [[ -z "$WRAPPER" ]]; then
        log_error "Wrapper name required"
        exit 1
    fi

    if ! wrapper_installed "$WRAPPER"; then
        log_error "$WRAPPER is not installed"
        exit 1
    fi

    print_header "Checking Backup Integrity ($WRAPPER)"

    case "$WRAPPER" in
        autorestic)
            autorestic check
            ;;
        borgmatic)
            borgmatic check
            ;;
        resticprofile)
            local args=()
            [[ -n "$PROFILE" ]] && args+=("-n" "$PROFILE")
            resticprofile "${args[@]}" check
            ;;
        kopia)
            kopia snapshot verify
            ;;
        rustic)
            rustic check
            ;;
    esac
}

# =============================================================================
# Command: list
# =============================================================================

cmd_list() {
    if [[ -z "$WRAPPER" ]]; then
        log_error "Wrapper name required"
        exit 1
    fi

    if ! wrapper_installed "$WRAPPER"; then
        log_error "$WRAPPER is not installed"
        exit 1
    fi

    print_header "Listing Backups ($WRAPPER)"

    case "$WRAPPER" in
        autorestic)
            autorestic exec -a -- snapshots
            ;;
        borgmatic)
            borgmatic list
            ;;
        resticprofile)
            local args=()
            [[ -n "$PROFILE" ]] && args+=("-n" "$PROFILE")
            resticprofile "${args[@]}" snapshots
            ;;
        kopia)
            kopia snapshot list
            ;;
        rustic)
            rustic snapshots
            ;;
    esac
}

# =============================================================================
# Command: restore
# =============================================================================

cmd_restore() {
    if [[ -z "$WRAPPER" ]]; then
        log_error "Wrapper name required"
        exit 1
    fi

    if ! wrapper_installed "$WRAPPER"; then
        log_error "$WRAPPER is not installed"
        exit 1
    fi

    print_header "Restore from Backup ($WRAPPER)"

    # Get target path
    local target="${1:-/tmp/restore}"

    log_info "Restore target: $target"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "Dry run - would restore to $target"
        return 0
    fi

    case "$WRAPPER" in
        autorestic)
            local args=()
            [[ -n "$PROFILE" ]] && args+=("-l" "$PROFILE")
            autorestic restore "${args[@]}" --to "$target"
            ;;
        borgmatic)
            borgmatic extract --destination "$target"
            ;;
        resticprofile)
            local args=()
            [[ -n "$PROFILE" ]] && args+=("-n" "$PROFILE")
            resticprofile "${args[@]}" restore latest --target "$target"
            ;;
        kopia)
            read -rp "Snapshot ID: " snapshot_id
            kopia restore "$snapshot_id" "$target"
            ;;
        rustic)
            rustic restore latest "$target"
            ;;
    esac
}

# =============================================================================
# Command: schedule
# =============================================================================

cmd_schedule() {
    if [[ -z "$WRAPPER" ]]; then
        log_error "Wrapper name required"
        exit 1
    fi

    if ! wrapper_installed "$WRAPPER"; then
        log_error "$WRAPPER is not installed"
        exit 1
    fi

    print_header "Setting up Schedule ($WRAPPER)"

    case "$WRAPPER" in
        autorestic)
            log_info "Autorestic uses cron definitions in config"
            echo ""
            echo "Add 'cron' field to your locations in ~/.autorestic.yml:"
            echo "  locations:"
            echo "    home:"
            echo "      cron: \"0 2 * * *\"  # Daily at 2 AM"
            echo ""
            echo "Then run: autorestic cron"
            ;;
        borgmatic)
            log_info "Borgmatic uses systemd timer"
            echo ""
            if command -v systemctl &> /dev/null; then
                echo "Enable with:"
                echo "  sudo systemctl enable --now borgmatic.timer"
            else
                echo "Add to crontab:"
                echo "  0 2 * * * borgmatic --verbosity -1 --syslog-verbosity 1"
            fi
            ;;
        resticprofile)
            log_info "Installing resticprofile schedules..."
            if [[ "$DRY_RUN" == "true" ]]; then
                resticprofile schedule --all --dry-run
            else
                resticprofile schedule --all
            fi
            ;;
        kopia)
            log_info "Kopia uses server mode for scheduling"
            echo ""
            echo "Option 1 - Kopia Server (recommended):"
            echo "  kopia server start --insecure --address 0.0.0.0:51515"
            echo ""
            echo "Option 2 - Systemd timer:"
            echo "  Create /etc/systemd/system/kopia-backup.timer"
            ;;
    esac
}

# =============================================================================
# Command: config
# =============================================================================

cmd_config() {
    if [[ -z "$WRAPPER" ]]; then
        log_error "Wrapper name required"
        exit 1
    fi

    local config_path="${CONFIG_PATHS[$WRAPPER]}"

    if [[ ! -f "$config_path" ]]; then
        log_warn "Config not found: $config_path"
        read -rp "Create it? (Y/n): " confirm
        if [[ ! "$confirm" =~ ^[Nn] ]]; then
            cmd_init
        fi
        return
    fi

    local editor="${EDITOR:-${VISUAL:-nano}}"
    log_info "Opening: $config_path"
    "$editor" "$config_path"
}

# =============================================================================
# Command: docs
# =============================================================================

cmd_docs() {
    if [[ -z "$WRAPPER" ]]; then
        log_error "Wrapper name required"
        exit 1
    fi

    local url=""
    case "$WRAPPER" in
        autorestic) url="https://autorestic.vercel.app" ;;
        borgmatic) url="https://torsion.org/borgmatic/" ;;
        resticprofile) url="https://creativeprojects.github.io/resticprofile/" ;;
        kopia) url="https://kopia.io/docs/" ;;
        rustic) url="https://rustic.cli.rs/docs/" ;;
        *)
            log_error "Unknown wrapper: $WRAPPER"
            exit 1
            ;;
    esac

    log_info "Opening: $url"

    if command -v open &> /dev/null; then
        open "$url"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$url"
    else
        echo "Documentation: $url"
    fi
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_help
                exit 0
                ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            -q | --quiet)
                QUIET=true
                shift
                ;;
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            --with-ui | --ui | --gui)
                WITH_UI=true
                shift
                ;;
            -p | --profile)
                PROFILE="$2"
                shift 2
                ;;
            -l | --location)
                LOCATION="$2"
                shift 2
                ;;
            -a | --all)
                PROFILE=""
                LOCATION=""
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [[ -z "$COMMAND" ]]; then
                    COMMAND="$1"
                elif [[ -z "$WRAPPER" ]]; then
                    WRAPPER="$1"
                fi
                shift
                ;;
        esac
    done

    # Default to interactive mode when no command specified
    [[ -z "$COMMAND" ]] && COMMAND="interactive"
}

# =============================================================================
# Command: interactive
# =============================================================================

cmd_interactive() {
    while true; do
        clear
        echo ""
        echo -e "${BOLD:-}${CYAN:-}╔══════════════════════════════════════════════════════════════╗${NC:-}"
        echo -e "${BOLD:-}${CYAN:-}║           RSR Backup Wrappers - Interactive Mode             ║${NC:-}"
        echo -e "${BOLD:-}${CYAN:-}╚══════════════════════════════════════════════════════════════╝${NC:-}"
        echo ""
        echo -e "  ${BOLD:-}Manage config-driven backup solutions${NC:-}"
        echo ""
        echo "  [1] Show status           - View installed wrappers"
        echo "  [2] Install wrapper       - Install autorestic, borgmatic, etc."
        echo "  [3] Generate config       - Create config template"
        echo "  [4] Run backup            - Execute backup"
        echo "  [5] Check backup          - Verify backup integrity"
        echo "  [6] List snapshots        - Show available backups"
        echo "  [7] Restore backup        - Restore from backup"
        echo "  [8] Setup schedule        - Configure automated backups"
        echo "  [9] Edit config           - Open configuration file"
        echo "  [0] Documentation         - Open wrapper docs"
        echo ""
        echo "  [q] Quit"
        echo ""

        read -rp "  Select an option: " choice

        case "$choice" in
            1)
                cmd_status
                echo ""
                read -rp "  Press Enter to continue..."
                ;;
            2)
                interactive_install
                ;;
            3)
                interactive_init
                ;;
            4)
                interactive_run
                ;;
            5)
                interactive_check
                ;;
            6)
                interactive_list
                ;;
            7)
                interactive_restore
                ;;
            8)
                interactive_schedule
                ;;
            9)
                interactive_config
                ;;
            0)
                interactive_docs
                ;;
            q | Q)
                echo ""
                echo -e "  ${GREEN:-}Goodbye!${NC:-}"
                echo ""
                exit 0
                ;;
            *)
                log_warn "Invalid option: $choice"
                sleep 1
                ;;
        esac
    done
}

# Interactive helper: select a wrapper
interactive_select_wrapper() {
    local prompt="${1:-Select a wrapper}"
    echo ""
    echo "  Available wrappers:"
    echo ""

    local i=1
    local wrapper_list=()
    for wrapper in "${!WRAPPERS[@]}"; do
        local info="${WRAPPERS[$wrapper]}"
        local desc="${info#*:}"
        local installed=""
        if wrapper_installed "$wrapper"; then
            installed="${GREEN:-}[installed]${NC:-}"
        fi
        printf "    [%d] %-15s %s %b\n" "$i" "$wrapper" "$desc" "$installed"
        wrapper_list+=("$wrapper")
        ((i++))
    done

    echo ""
    read -rp "  $prompt (1-${#wrapper_list[@]}): " selection

    if [[ "$selection" =~ ^[0-9]+$ ]] && ((selection >= 1 && selection <= ${#wrapper_list[@]})); then
        WRAPPER="${wrapper_list[$((selection - 1))]}"
        return 0
    else
        log_warn "Invalid selection"
        return 1
    fi
}

# Interactive: Install wrapper
interactive_install() {
    print_header "Install Backup Wrapper"

    if ! interactive_select_wrapper "Select wrapper to install"; then
        read -rp "  Press Enter to continue..."
        return
    fi

    echo ""
    read -rp "  Install with GUI/UI package? (y/N): " ui_choice
    [[ "$ui_choice" =~ ^[Yy] ]] && WITH_UI=true

    echo ""
    cmd_install

    echo ""
    read -rp "  Press Enter to continue..."
}

# Interactive: Generate config
interactive_init() {
    print_header "Generate Configuration"

    if ! interactive_select_wrapper "Select wrapper to configure"; then
        read -rp "  Press Enter to continue..."
        return
    fi

    echo ""
    cmd_init

    echo ""
    read -rp "  Press Enter to continue..."
}

# Interactive: Run backup
interactive_run() {
    print_header "Run Backup"

    # Check for installed wrappers with config
    local available=()
    for wrapper in "${!WRAPPERS[@]}"; do
        if wrapper_installed "$wrapper" && wrapper_config_exists "$wrapper"; then
            available+=("$wrapper")
        fi
    done

    if [[ ${#available[@]} -eq 0 ]]; then
        log_warn "No configured wrappers found"
        echo ""
        echo "  Install and configure a wrapper first:"
        echo "    1. Install: backup-wrappers.sh install <wrapper>"
        echo "    2. Configure: backup-wrappers.sh init <wrapper>"
        echo ""
        read -rp "  Press Enter to continue..."
        return
    fi

    echo ""
    echo "  Available configured wrappers:"
    echo ""

    local i=1
    for wrapper in "${available[@]}"; do
        printf "    [%d] %s\n" "$i" "$wrapper"
        ((i++))
    done

    echo ""
    read -rp "  Select wrapper (1-${#available[@]}): " selection

    if [[ "$selection" =~ ^[0-9]+$ ]] && ((selection >= 1 && selection <= ${#available[@]})); then
        WRAPPER="${available[$((selection - 1))]}"
    else
        log_warn "Invalid selection"
        read -rp "  Press Enter to continue..."
        return
    fi

    echo ""
    read -rp "  Profile/location name (or Enter for all): " PROFILE

    echo ""
    read -rp "  Dry run first? (y/N): " dry_choice
    [[ "$dry_choice" =~ ^[Yy] ]] && DRY_RUN=true

    echo ""
    cmd_run

    DRY_RUN=false
    echo ""
    read -rp "  Press Enter to continue..."
}

# Interactive: Check backup
interactive_check() {
    print_header "Check Backup Integrity"

    if ! interactive_select_wrapper "Select wrapper to check"; then
        read -rp "  Press Enter to continue..."
        return
    fi

    echo ""
    cmd_check

    echo ""
    read -rp "  Press Enter to continue..."
}

# Interactive: List snapshots
interactive_list() {
    print_header "List Snapshots"

    if ! interactive_select_wrapper "Select wrapper"; then
        read -rp "  Press Enter to continue..."
        return
    fi

    echo ""
    cmd_list

    echo ""
    read -rp "  Press Enter to continue..."
}

# Interactive: Restore backup
interactive_restore() {
    print_header "Restore from Backup"

    if ! interactive_select_wrapper "Select wrapper"; then
        read -rp "  Press Enter to continue..."
        return
    fi

    echo ""
    read -rp "  Restore target path [/tmp/restore]: " target
    [[ -z "$target" ]] && target="/tmp/restore"

    echo ""
    cmd_restore "$target"

    echo ""
    read -rp "  Press Enter to continue..."
}

# Interactive: Setup schedule
interactive_schedule() {
    print_header "Setup Backup Schedule"

    if ! interactive_select_wrapper "Select wrapper"; then
        read -rp "  Press Enter to continue..."
        return
    fi

    echo ""
    cmd_schedule

    echo ""
    read -rp "  Press Enter to continue..."
}

# Interactive: Edit config
interactive_config() {
    print_header "Edit Configuration"

    if ! interactive_select_wrapper "Select wrapper"; then
        read -rp "  Press Enter to continue..."
        return
    fi

    echo ""
    cmd_config

    echo ""
    read -rp "  Press Enter to continue..."
}

# Interactive: Open documentation
interactive_docs() {
    print_header "Open Documentation"

    if ! interactive_select_wrapper "Select wrapper"; then
        read -rp "  Press Enter to continue..."
        return
    fi

    echo ""
    cmd_docs

    echo ""
    read -rp "  Press Enter to continue..."
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    case "$COMMAND" in
        interactive | menu)
            cmd_interactive
            ;;
        status)
            cmd_status
            ;;
        install)
            cmd_install
            ;;
        init | generate | template)
            cmd_init
            ;;
        run | backup)
            cmd_run
            ;;
        check | verify)
            cmd_check
            ;;
        list | snapshots)
            cmd_list
            ;;
        restore)
            cmd_restore "$@"
            ;;
        schedule)
            cmd_schedule
            ;;
        config | edit)
            cmd_config
            ;;
        docs | help | documentation)
            cmd_docs
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

main "$@"
