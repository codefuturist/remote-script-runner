#!/bin/bash
# install-ansible-uv.sh — Install Ansible fully via uv (Python package manager)
#
# Installs ansible-core as the primary uv tool with the full ansible package
# (including 100+ bundled community collections). This is the community-recommended
# approach that properly exposes all CLI executables to ~/.local/bin/.
#
# Usage:
#   ./install-ansible-uv.sh                    # Install with defaults
#   ./install-ansible-uv.sh --with-lint        # Also install ansible-lint
#   ./install-ansible-uv.sh --with-molecule    # Also install molecule
#   ./install-ansible-uv.sh --with-dev         # Install lint + molecule
#   ./install-ansible-uv.sh --core-only        # Install ansible-core without collections
#   ./install-ansible-uv.sh --uninstall        # Remove ansible tools installed by this script
#   ./install-ansible-uv.sh --upgrade          # Upgrade all ansible uv tools
#
# Requirements:
#   - uv (https://docs.astral.sh/uv/)
#
# References:
#   - https://samedwardes.com/blog/2025-12-29-how-to-install-ansible-with-uv/
#   - https://docs.astral.sh/uv/concepts/tools/

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

VERSION="1.0.0"
UV_MIN_VERSION="0.8.5" # minimum for --with-executables-from support

# Defaults
WITH_LINT=false
WITH_MOLECULE=false
CORE_ONLY=false
UNINSTALL=false
UPGRADE=false
FORCE=false
QUIET=false
DRY_RUN=false

# ============================================================================
# Colors
# ============================================================================

if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN='' YELLOW='' RED='' BLUE='' BOLD='' NC=''
fi

# ============================================================================
# Helpers
# ============================================================================

log_info() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[→]${NC} $*"; }
log_header() { echo -e "\n${BOLD}$*${NC}"; }

run_cmd() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[dry-run]${NC} $*"
        return 0
    fi
    if $QUIET; then
        "$@" >/dev/null 2>&1
    else
        "$@"
    fi
}

# ============================================================================
# Version comparison
# ============================================================================

version_ge() {
    # Returns 0 if $1 >= $2 (semantic version comparison)
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# ============================================================================
# Preflight checks
# ============================================================================

check_uv() {
    if ! command -v uv &>/dev/null; then
        log_error "uv is not installed."
        echo
        echo "Install uv with:"
        echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
        echo
        echo "Or see: https://docs.astral.sh/uv/getting-started/installation/"
        exit 1
    fi

    local uv_version
    uv_version=$(uv --version | awk '{print $2}')
    if ! version_ge "$uv_version" "$UV_MIN_VERSION"; then
        log_error "uv version $uv_version is too old (need >= $UV_MIN_VERSION)"
        echo "Upgrade with: uv self update"
        exit 1
    fi
    log_info "uv $uv_version detected"
}

check_path() {
    local bin_dir="${HOME}/.local/bin"
    if [[ ":${PATH}:" != *":${bin_dir}:"* ]]; then
        log_warn "${bin_dir} is not in your PATH"
        echo "  Add to your shell config:"
        echo "    export PATH=\"\${HOME}/.local/bin:\${PATH}\""
        echo
    fi
}

check_existing_apt_ansible() {
    if dpkg -l ansible 2>/dev/null | grep -q '^ii'; then
        local apt_version
        apt_version=$(dpkg -l ansible 2>/dev/null | awk '/^ii/{print $3}')
        log_warn "Ansible $apt_version is installed via apt"
        echo "  The apt version will shadow the uv-managed version if /usr/bin is"
        echo "  earlier in PATH than ~/.local/bin."
        echo
        if $FORCE; then
            log_step "Removing apt ansible (--force)"
            sudo apt remove --purge -y ansible ansible-core >/dev/null 2>&1 || true
            sudo apt autoremove -y >/dev/null 2>&1 || true
            log_info "apt ansible removed"
        else
            echo "  Remove it with:  sudo apt remove --purge ansible ansible-core"
            echo "  Or re-run with:  $0 --force"
            echo
            read -rp "Continue anyway? [y/N] " response
            if [[ ! "$response" =~ ^[Yy] ]]; then
                exit 0
            fi
        fi
    fi
}

check_existing_uv_ansible() {
    # Check if ansible or ansible-core is already installed as a uv tool
    local existing=""
    if uv tool list 2>/dev/null | grep -q '^ansible-core '; then
        existing="ansible-core"
    elif uv tool list 2>/dev/null | grep -q '^ansible '; then
        existing="ansible"
    fi

    if [ -n "$existing" ]; then
        local current_version
        current_version=$(uv tool list 2>/dev/null | grep "^${existing} " | awk '{print $2}')
        if $FORCE || $UPGRADE; then
            log_step "Removing existing uv tool: $existing $current_version"
            run_cmd uv tool uninstall "$existing"
        else
            log_warn "Ansible already installed as uv tool: $existing $current_version"
            echo "  Re-run with --force to reinstall, or --upgrade to upgrade."
            exit 0
        fi
    fi
}

# ============================================================================
# Install functions
# ============================================================================

install_ansible() {
    log_header "Installing Ansible via uv"

    if $CORE_ONLY; then
        log_step "Installing ansible-core (without bundled collections)"
        run_cmd uv tool install ansible-core
    else
        log_step "Installing ansible-core --with ansible (includes collections)"
        run_cmd uv tool install ansible-core --with ansible
    fi

    log_info "Ansible installed"
}

install_lint() {
    log_header "Installing ansible-lint via uv"

    if uv tool list 2>/dev/null | grep -q '^ansible-lint '; then
        if $UPGRADE; then
            log_step "Upgrading ansible-lint"
            run_cmd uv tool upgrade ansible-lint
        else
            local lint_version
            lint_version=$(uv tool list 2>/dev/null | grep '^ansible-lint ' | awk '{print $2}')
            log_info "ansible-lint already installed: $lint_version (use --upgrade to update)"
        fi
    else
        log_step "Installing ansible-lint"
        run_cmd uv tool install ansible-lint
    fi
}

install_molecule() {
    log_header "Installing molecule via uv"

    if uv tool list 2>/dev/null | grep -q '^molecule '; then
        if $UPGRADE; then
            log_step "Upgrading molecule"
            run_cmd uv tool upgrade molecule
        else
            local mol_version
            mol_version=$(uv tool list 2>/dev/null | grep '^molecule ' | awk '{print $2}')
            log_info "molecule already installed: $mol_version (use --upgrade to update)"
        fi
    else
        log_step "Installing molecule"
        run_cmd uv tool install molecule
    fi
}

# ============================================================================
# Upgrade
# ============================================================================

do_upgrade() {
    log_header "Upgrading Ansible uv tools"

    local tools=()
    if uv tool list 2>/dev/null | grep -q '^ansible-core '; then
        tools+=("ansible-core")
    elif uv tool list 2>/dev/null | grep -q '^ansible '; then
        tools+=("ansible")
    fi

    if uv tool list 2>/dev/null | grep -q '^ansible-lint '; then
        tools+=("ansible-lint")
    fi
    if uv tool list 2>/dev/null | grep -q '^molecule '; then
        tools+=("molecule")
    fi

    if [ ${#tools[@]} -eq 0 ]; then
        log_warn "No Ansible uv tools found to upgrade"
        exit 0
    fi

    for tool in "${tools[@]}"; do
        log_step "Upgrading $tool"
        run_cmd uv tool upgrade "$tool"
        log_info "$tool upgraded"
    done
}

# ============================================================================
# Uninstall
# ============================================================================

do_uninstall() {
    log_header "Uninstalling Ansible uv tools"

    local found=false
    for tool in ansible-core ansible ansible-lint molecule; do
        if uv tool list 2>/dev/null | grep -q "^${tool} "; then
            log_step "Uninstalling $tool"
            run_cmd uv tool uninstall "$tool"
            log_info "$tool removed"
            found=true
        fi
    done

    if ! $found; then
        log_warn "No Ansible uv tools found"
    fi
}

# ============================================================================
# Verification
# ============================================================================

verify_install() {
    log_header "Verification"

    local errors=0

    # Check core executables
    for cmd in ansible ansible-playbook ansible-galaxy ansible-vault; do
        if command -v "$cmd" &>/dev/null; then
            local location version
            location=$(command -v "$cmd")
            version=$("$cmd" --version 2>/dev/null | head -1)
            log_info "$cmd → $location ($version)"
        else
            log_error "$cmd not found on PATH"
            ((errors++))
        fi
    done

    # Check collections (if full install)
    if ! $CORE_ONLY; then
        local collection_count
        collection_count=$(ansible-galaxy collection list 2>/dev/null | grep -c '^\S' || echo 0)
        if [ "$collection_count" -gt 0 ]; then
            log_info "$collection_count collections available"
        else
            log_warn "No collections detected"
        fi
    fi

    # Check optional tools
    if command -v ansible-lint &>/dev/null; then
        log_info "ansible-lint $(ansible-lint --version 2>/dev/null | head -1)"
    fi
    if command -v molecule &>/dev/null; then
        log_info "molecule $(molecule --version 2>/dev/null | head -1)"
    fi

    echo
    if [ "$errors" -eq 0 ]; then
        log_info "All checks passed ✓"
    else
        log_error "$errors check(s) failed"
        return 1
    fi
}

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat <<EOF
${BOLD}install-ansible-uv.sh${NC} v${VERSION} — Install Ansible fully via uv

${BOLD}USAGE${NC}
    $(basename "$0") [OPTIONS]

${BOLD}OPTIONS${NC}
    --with-lint        Also install ansible-lint as a separate uv tool
    --with-molecule    Also install molecule as a separate uv tool
    --with-dev         Install both ansible-lint and molecule
    --core-only        Install ansible-core only (no bundled collections)
    --upgrade          Upgrade all installed Ansible uv tools
    --uninstall        Remove all Ansible uv tools
    --force            Force reinstall; auto-remove apt ansible if present
    --dry-run          Show what would be done without executing
    --quiet            Suppress uv output
    -h, --help         Show this help message

${BOLD}EXAMPLES${NC}
    $(basename "$0")                    # Standard install (ansible-core + collections)
    $(basename "$0") --with-dev         # Full dev setup with lint + molecule
    $(basename "$0") --force            # Reinstall from scratch
    $(basename "$0") --upgrade          # Upgrade all ansible tools
    $(basename "$0") --uninstall        # Clean removal of all ansible tools

${BOLD}WHAT THIS INSTALLS${NC}
    The recommended pattern: ${BLUE}uv tool install ansible-core --with ansible${NC}

    This installs ansible-core as the primary tool, which properly exposes
    all 10+ CLI executables (ansible, ansible-playbook, ansible-galaxy, etc.)
    to ~/.local/bin/. The --with ansible flag includes the full ansible
    package with 100+ bundled community collections.

    ansible-lint and molecule are installed as separate uv tools since they
    have independent dependency trees.

${BOLD}UPGRADING${NC}
    uv tool upgrade ansible-core       # Upgrade ansible
    uv tool upgrade ansible-lint       # Upgrade linter
    uv tool upgrade molecule           # Upgrade molecule

${BOLD}REFERENCES${NC}
    https://samedwardes.com/blog/2025-12-29-how-to-install-ansible-with-uv/
    https://docs.astral.sh/uv/concepts/tools/
    https://docs.ansible.com/projects/ansible/latest/installation_guide/
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --with-lint) WITH_LINT=true ;;
            --with-molecule) WITH_MOLECULE=true ;;
            --with-dev)
                WITH_LINT=true
                WITH_MOLECULE=true
                ;;
            --core-only) CORE_ONLY=true ;;
            --uninstall) UNINSTALL=true ;;
            --upgrade) UPGRADE=true ;;
            --force) FORCE=true ;;
            --dry-run) DRY_RUN=true ;;
            --quiet) QUIET=true ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run with --help for usage."
                exit 1
                ;;
        esac
        shift
    done

    log_header "Ansible via uv — Installer v${VERSION}"

    # Preflight
    check_uv
    check_path

    # Handle uninstall/upgrade early
    if $UNINSTALL; then
        do_uninstall
        exit 0
    fi

    if $UPGRADE && ! $FORCE; then
        do_upgrade
        verify_install
        exit 0
    fi

    # Install flow
    check_existing_apt_ansible
    check_existing_uv_ansible
    install_ansible

    if $WITH_LINT; then
        install_lint
    fi
    if $WITH_MOLECULE; then
        install_molecule
    fi

    verify_install
}

main "$@"
