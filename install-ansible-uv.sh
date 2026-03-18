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
#   ./install-ansible-uv.sh --check            # Audit for conflicts, then exit
#   ./install-ansible-uv.sh --uninstall        # Remove ansible uv tools (keeps ~/.ansible/)
#   ./install-ansible-uv.sh --uninstall --purge  # Also remove ~/.ansible/ data directory
#   ./install-ansible-uv.sh --uninstall --yes  # Non-interactive (no confirmation prompt)
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

VERSION="1.1.0"
UV_MIN_VERSION="0.8.5" # minimum for --with-executables-from support

# Defaults
WITH_LINT=false
WITH_MOLECULE=false
CORE_ONLY=false
UNINSTALL=false
UPGRADE=false
CHECK_ONLY=false # run conflict check only, then exit
FORCE=false
QUIET=false
DRY_RUN=false
YES=false   # skip confirmation prompts (for CI / non-interactive use)
PURGE=false # also remove ~/.ansible/ data on uninstall

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
# Conflict Detection
# ============================================================================
#
# Severity levels:
#   BLOCKER  — will definitely cause silent failures or wrong ansible being run
#   WARNING  — may cause confusion but won't necessarily break anything
#   INFO     — noteworthy but expected (e.g. uv tool venv isolation)
#
# Exit codes from check_conflicts():
#   0 — clean, no issues
#   1 — warnings found (install can proceed)
#   2 — blockers found (install aborts unless --force)
# ============================================================================

_BLOCKERS=0
_WARNINGS=0

_report_finding() {
    local severity="$1"
    local source="$2"
    local message="$3"
    local fix="${4:-}"

    case "$severity" in
        BLOCKER)
            echo -e "  ${RED}[BLOCKER]${NC} ${BOLD}${source}${NC}: ${message}"
            ((_BLOCKERS++)) || true
            ;;
        WARNING)
            echo -e "  ${YELLOW}[WARNING]${NC} ${BOLD}${source}${NC}: ${message}"
            ((_WARNINGS++)) || true
            ;;
        INFO)
            echo -e "  ${GREEN}[ INFO  ]${NC} ${BOLD}${source}${NC}: ${message}"
            ;;
    esac
    [[ -n "$fix" ]] && echo -e "           ${BLUE}→ fix:${NC} ${fix}"
}

# ── Individual checks ────────────────────────────────────────────────────────

_check_apt() {
    # Installed via apt/dpkg — will shadow uv-managed version
    local pkg ver
    for pkg in ansible ansible-core; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
            ver=$(dpkg -l "$pkg" 2>/dev/null | awk '/^ii/{print $3}')
            _report_finding BLOCKER "apt" \
                "${pkg} ${ver} installed via apt — will shadow uv-managed version" \
                "sudo apt remove --purge ${pkg}  OR  re-run with --force"
        fi
    done
}

_check_pip_user() {
    # pip3 --user installs land in ~/.local/lib, executables in ~/.local/bin
    # These would directly clash with uv tool symlinks
    if command -v pip3 &>/dev/null; then
        local found
        found=$(pip3 list --user 2>/dev/null | grep -i '^ansible' | awk '{print $1"=="$2}' | tr '\n' ' ') || true
        if [[ -n "$found" ]]; then
            _report_finding BLOCKER "pip3 --user" \
                "Ansible packages in user pip: ${found}" \
                "pip3 uninstall --user ansible ansible-core  (then re-run)"
        fi
    fi
}

_check_pipx() {
    if command -v pipx &>/dev/null; then
        local found
        found=$(pipx list 2>/dev/null | grep -i 'ansible' | awk '{print $2}' | tr '\n' ' ') || true
        if [[ -n "$found" ]]; then
            _report_finding BLOCKER "pipx" \
                "Ansible installed via pipx: ${found}" \
                "pipx uninstall ansible  (then re-run)"
        fi
    fi
}

_check_brew() {
    if command -v brew &>/dev/null; then
        local found
        found=$(brew list 2>/dev/null | grep -i '^ansible' | tr '\n' ' ') || true
        if [[ -n "$found" ]]; then
            _report_finding BLOCKER "brew" \
                "Ansible installed via Homebrew: ${found}" \
                "brew uninstall ${found}"
        fi
    fi
}

_check_snap() {
    if command -v snap &>/dev/null; then
        local found
        found=$(snap list 2>/dev/null | grep -i 'ansible' | awk '{print $1}' | tr '\n' ' ') || true
        if [[ -n "$found" ]]; then
            _report_finding BLOCKER "snap" \
                "Ansible installed via snap: ${found}" \
                "sudo snap remove ${found}"
        fi
    fi
}

_check_conda() {
    if command -v conda &>/dev/null; then
        local found
        found=$(conda list 2>/dev/null | grep -i '^ansible' | awk '{print $1"="$2}' | tr '\n' ' ') || true
        if [[ -n "$found" ]]; then
            _report_finding BLOCKER "conda" \
                "Ansible installed in active conda env: ${found}" \
                "conda remove ansible ansible-core"
        fi
    fi
}

_check_system_paths() {
    # ansible binaries in system-wide locations outside uv's control
    local dir binary
    for dir in /usr/bin /usr/local/bin /opt/local/bin /snap/bin; do
        for binary in "${dir}"/ansible "${dir}"/ansible-playbook "${dir}"/ansible-galaxy; do
            if [[ -x "$binary" ]]; then
                _report_finding BLOCKER "system path" \
                    "${binary} exists outside uv — may shadow ~/.local/bin/" \
                    "Remove via the package manager that installed it"
                break # one report per dir is enough
            fi
        done
    done
}

_check_path_shadowing() {
    # Detect if ANY ansible binary appears earlier in PATH than ~/.local/bin
    local uv_bin="${HOME}/.local/bin"
    local uv_pos=-1
    local pos=0
    local dir found_before=false
    local shadow_dirs=()

    # Find position of ~/.local/bin in PATH
    while IFS= read -r dir; do
        ((pos++)) || true
        if [[ "$dir" == "$uv_bin" ]]; then
            uv_pos=$pos
            break
        fi
    done < <(echo "$PATH" | tr ':' '\n')

    if [[ $uv_pos -eq -1 ]]; then
        _report_finding WARNING "PATH" \
            "${uv_bin} is not in PATH — ansible commands will not be found" \
            "Add to shell config: export PATH=\"\${HOME}/.local/bin:\${PATH}\""
        return
    fi

    # Check if any earlier PATH entry contains an ansible binary
    pos=0
    while IFS= read -r dir; do
        ((pos++)) || true
        [[ $pos -ge $uv_pos ]] && break
        if [[ -x "${dir}/ansible" ]] || [[ -x "${dir}/ansible-playbook" ]]; then
            shadow_dirs+=("$dir")
            found_before=true
        fi
    done < <(echo "$PATH" | tr ':' '\n')

    if $found_before; then
        local shadow_list
        shadow_list=$(printf '%s, ' "${shadow_dirs[@]}")
        _report_finding BLOCKER "PATH shadow" \
            "Ansible found in PATH before ${uv_bin}: ${shadow_list%, }" \
            "Remove conflicting install OR move ~/.local/bin earlier in PATH"
    fi
}

_check_env_vars() {
    # ANSIBLE_* env vars can silently override config and cause unexpected behavior
    local vars
    vars=$(env 2>/dev/null | grep '^ANSIBLE_' | cut -d= -f1 | sort | tr '\n' ' ') || true
    if [[ -n "$vars" ]]; then
        _report_finding WARNING "env vars" \
            "Active ANSIBLE_* variables may override config: ${vars}" \
            "Unset in shell or check ~/.bashrc / ~/.zshrc for persistent exports"
    fi
}

_check_wrong_uv_pattern() {
    # `uv tool install ansible` (not ansible-core) only exposes ansible-community
    if uv tool list 2>/dev/null | grep -q '^ansible v'; then
        local ver
        ver=$(uv tool list 2>/dev/null | grep '^ansible v' | awk '{print $2}')
        _report_finding WARNING "uv tool" \
            "ansible ${ver} installed as primary tool — only exposes 'ansible-community'" \
            "uv tool uninstall ansible  then: uv tool install ansible-core --with ansible"
    fi
}

_check_stale_tmp() {
    # Stale ansible tmp dirs waste space (informational, not a conflict)
    local count
    count=$(find "${HOME}/.ansible/tmp" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l) || true
    if [[ "$count" -gt 0 ]]; then
        _report_finding INFO "stale tmp" \
            "${count} stale tmp dir(s) in ${HOME}/.ansible/tmp/" \
            "rm -rf ${HOME}/.ansible/tmp/*"
    fi
}

# ── Main conflict check entry point ─────────────────────────────────────────

check_conflicts() {
    log_header "Conflict Detection"

    _BLOCKERS=0
    _WARNINGS=0

    _check_apt
    _check_pip_user
    _check_pipx
    _check_brew
    _check_snap
    _check_conda
    _check_system_paths
    _check_path_shadowing
    _check_env_vars
    _check_wrong_uv_pattern
    _check_stale_tmp

    echo
    if [[ $_BLOCKERS -eq 0 && $_WARNINGS -eq 0 ]]; then
        log_info "No conflicts detected — environment is clean ✓"
        return 0
    fi

    if [[ $_BLOCKERS -gt 0 ]]; then
        log_error "${_BLOCKERS} blocker(s) and ${_WARNINGS} warning(s) found"
        echo
        if $FORCE; then
            log_warn "Continuing despite blockers (--force)"
            return 1
        fi
        echo -e "  Blockers ${RED}must${NC} be resolved before installing, or use ${BOLD}--force${NC} to override."
        echo
        if ! $YES; then
            read -rp "  Abort install? [Y/n] " response
            echo
            case "$response" in
                [Nn]*)
                    log_warn "Continuing with unresolved blockers"
                    return 1
                    ;;
                *)
                    log_warn "Aborting — fix blockers and re-run"
                    exit 2
                    ;;
            esac
        else
            log_warn "Aborting due to blockers (--yes set, non-interactive)"
            exit 2
        fi
    fi

    log_warn "${_WARNINGS} warning(s) found — review above before proceeding"
    return 1
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

# ============================================================================
# Existing uv installation check
# ============================================================================
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
    log_header "Uninstalling Ansible"

    # ── Discover installed uv tools ──────────────────────────────────────────
    local tools=()
    local tool_versions=()
    local tool
    for tool in ansible-core ansible ansible-lint molecule; do
        if uv tool list 2>/dev/null | grep -q "^${tool} "; then
            local ver
            ver=$(uv tool list 2>/dev/null | grep "^${tool} " | awk '{print $2}')
            tools+=("$tool")
            tool_versions+=("${tool} ${ver}")
        fi
    done

    if [ ${#tools[@]} -eq 0 ]; then
        log_warn "No Ansible uv tools are installed — nothing to remove"
        return 0
    fi

    # ── Discover executables that will vanish ────────────────────────────────
    local executables=()
    local bin
    for bin in "${HOME}/.local/bin"/ansible*; do
        [[ -f "$bin" ]] && executables+=("$(basename "$bin")")
    done

    # ── Print preview ────────────────────────────────────────────────────────
    echo
    echo -e "${BOLD}The following will be removed:${NC}"
    echo
    echo "  uv tools:"
    local info
    for info in "${tool_versions[@]}"; do
        echo -e "    ${BLUE}•${NC} ${info}"
    done

    if [ ${#executables[@]} -gt 0 ]; then
        echo
        echo "  executables from ~/.local/bin/:"
        local exe_list
        exe_list=$(printf '%s, ' "${executables[@]}")
        echo "    ${exe_list%, }"
    fi

    if $PURGE; then
        echo
        echo "  data directories (--purge):"
        [[ -d "${HOME}/.ansible" ]] \
            && echo -e "    ${RED}•${NC} ~/.ansible/  (roles, collections cache, facts cache)"
    else
        if [[ -d "${HOME}/.ansible" ]]; then
            echo
            echo -e "  ${YELLOW}Note:${NC} ~/.ansible/ will NOT be removed (add --purge to also wipe user data)"
        fi
    fi

    echo

    # ── Confirm ──────────────────────────────────────────────────────────────
    if $DRY_RUN; then
        log_warn "Dry-run mode — no changes will be made"
        echo
    elif $YES; then
        log_warn "Non-interactive mode (--yes) — skipping confirmation"
        echo
    else
        read -rp "Proceed with uninstall? [y/N] " response
        echo
        case "$response" in
            [Yy]*) ;;
            *)
                log_warn "Uninstall cancelled"
                exit 0
                ;;
        esac
    fi

    # ── Remove tools ─────────────────────────────────────────────────────────
    local removed=()
    local failed=()
    for tool in "${tools[@]}"; do
        log_step "Removing $tool"
        if run_cmd uv tool uninstall "$tool"; then
            log_info "$tool removed"
            removed+=("$tool")
        else
            log_error "Failed to remove $tool"
            failed+=("$tool")
        fi
    done

    # ── Purge data dirs ───────────────────────────────────────────────────────
    if $PURGE; then
        if [[ -d "${HOME}/.ansible" ]]; then
            log_step "Removing ~/.ansible/"
            run_cmd rm -rf "${HOME}/.ansible"
            $DRY_RUN || log_info "${HOME}/.ansible/ removed"
        else
            log_warn "${HOME}/.ansible/ not found — nothing to purge"
        fi
    fi

    # ── Summary ───────────────────────────────────────────────────────────────
    log_header "Uninstall Summary"

    if [ ${#removed[@]} -gt 0 ]; then
        local removed_list
        removed_list=$(printf '%s, ' "${removed[@]}")
        log_info "Removed:   ${removed_list%, }"
    fi
    if [ ${#failed[@]} -gt 0 ]; then
        local failed_list
        failed_list=$(printf '%s, ' "${failed[@]}")
        log_error "Failed:    ${failed_list%, }"
    fi
    if ! $DRY_RUN && [ ${#removed[@]} -gt 0 ]; then
        echo
        log_warn "Run 'hash -r' or open a new terminal to refresh your shell's command cache"
    fi

    if [ ${#failed[@]} -gt 0 ]; then
        return 1
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
    --uninstall        Remove Ansible uv tools (keeps ~/.ansible/ data)
    --purge            With --uninstall: also remove ~/.ansible/ data directory
    --check            Run conflict detection only, then exit (0=clean, 1=warn, 2=blockers)
    --yes              Skip confirmation prompts (for CI / non-interactive use)
    --force            Force install; override blockers and auto-remove apt ansible
    --dry-run          Show what would be done without executing
    --quiet            Suppress uv output
    -h, --help         Show this help message

${BOLD}EXAMPLES${NC}
    $(basename "$0")                         # Standard install (ansible-core + collections)
    $(basename "$0") --with-dev              # Full dev setup with lint + molecule
    $(basename "$0") --check                 # Audit environment for conflicts, then exit
    $(basename "$0") --force                 # Reinstall, override/remove blockers
    $(basename "$0") --upgrade               # Upgrade all ansible tools
    $(basename "$0") --uninstall             # Remove tools, keep ~/.ansible/ data
    $(basename "$0") --uninstall --purge     # Remove tools + wipe ~/.ansible/
    $(basename "$0") --uninstall --yes       # Non-interactive uninstall (CI-safe)

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
            --check) CHECK_ONLY=true ;;
            --purge) PURGE=true ;;
            --yes) YES=true ;;
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

    # Standalone conflict check — exits with 0/1/2
    if $CHECK_ONLY; then
        check_conflicts
        exit $?
    fi

    # Handle uninstall/upgrade early
    if $PURGE && ! $UNINSTALL; then
        log_error "--purge only makes sense with --uninstall"
        echo "  Example: $0 --uninstall --purge"
        exit 1
    fi

    if $UNINSTALL; then
        do_uninstall
        exit 0
    fi

    if $UPGRADE && ! $FORCE; then
        do_upgrade
        verify_install
        exit 0
    fi

    # Conflict detection before install
    check_conflicts

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
