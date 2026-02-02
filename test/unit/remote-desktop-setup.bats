#!/usr/bin/env bats
# =============================================================================
# Unit Tests for remote-desktop-setup.sh
# =============================================================================

load '../test_helper'

# Override SCRIPT_DIR for this specific script location
REMOTE_DESKTOP_SCRIPT="$PROJECT_ROOT/scripts/system/remote-desktop/remote-desktop-setup.sh"

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Help and Usage Tests
# =============================================================================

@test "remote-desktop: shows help with -h flag" {
    run bash "$REMOTE_DESKTOP_SCRIPT" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "remote-desktop-setup"
    assert_output --partial "USAGE"
}

@test "remote-desktop: shows help with --help flag" {
    run bash "$REMOTE_DESKTOP_SCRIPT" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "SUBCOMMANDS"
    assert_output --partial "OPTIONS"
}

@test "remote-desktop: help shows all subcommands" {
    run bash "$REMOTE_DESKTOP_SCRIPT" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "install"
    assert_output --partial "status"
    assert_output --partial "start"
    assert_output --partial "stop"
    assert_output --partial "restart"
    assert_output --partial "enable"
    assert_output --partial "disable"
    assert_output --partial "firewall"
    assert_output --partial "security"
    assert_output --partial "uninstall"
}

@test "remote-desktop: help shows examples" {
    run bash "$REMOTE_DESKTOP_SCRIPT" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "EXAMPLES"
    assert_output --partial "install"
}

@test "remote-desktop: shows version with --version flag" {
    run bash "$REMOTE_DESKTOP_SCRIPT" --version
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "remote-desktop-setup"
    assert_output --partial "v"
}

@test "remote-desktop: shows supported distributions in help" {
    run bash "$REMOTE_DESKTOP_SCRIPT" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "SUPPORTED DISTRIBUTIONS"
    assert_output --partial "Ubuntu"
    assert_output --partial "Debian"
    assert_output --partial "Fedora"
}

@test "remote-desktop: shows connection info in help" {
    run bash "$REMOTE_DESKTOP_SCRIPT" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "CONNECTING"
    assert_output --partial "RDP"
}

# =============================================================================
# Option Parsing Tests
# =============================================================================

@test "remote-desktop: supports --dry-run option" {
    run bash "$REMOTE_DESKTOP_SCRIPT" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-d"
    assert_output --partial "dry-run"
}

@test "remote-desktop: supports --verbose option" {
    run bash "$REMOTE_DESKTOP_SCRIPT" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-v"
    assert_output --partial "verbose"
}

@test "remote-desktop: supports --force option" {
    run bash "$REMOTE_DESKTOP_SCRIPT" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-f"
    assert_output --partial "force"
}

@test "remote-desktop: supports --yes option" {
    run bash "$REMOTE_DESKTOP_SCRIPT" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-y"
    assert_output --partial "yes"
}

# =============================================================================
# Syntax and Structure Tests
# =============================================================================

@test "remote-desktop: has valid bash syntax" {
    run bash -n "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: script is executable" {
    assert_file_executable "$REMOTE_DESKTOP_SCRIPT"
}

@test "remote-desktop: contains script metadata" {
    run grep -E "^# @name" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
    
    run grep -E "^# @version" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
    
    run grep -E "^# @description" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: uses set -eo pipefail" {
    run grep -E "set -eo pipefail" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "remote-desktop: handles unknown option" {
    run bash "$REMOTE_DESKTOP_SCRIPT" --unknown-option-xyz 2>&1
    assert_failure
    output=$(strip_colors "$output")
    assert_output --partial "Unknown option"
}

@test "remote-desktop: handles unknown subcommand" {
    run bash "$REMOTE_DESKTOP_SCRIPT" unknown-subcommand 2>&1
    assert_failure
    output=$(strip_colors "$output")
    assert_output --partial "Unknown subcommand"
}

@test "remote-desktop: shows help when no arguments (non-interactive)" {
    # When piped (non-interactive), should show help
    run bash "$REMOTE_DESKTOP_SCRIPT" < /dev/null
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "USAGE"
}

# =============================================================================
# Dry-run Mode Tests
# =============================================================================

@test "remote-desktop: dry-run shows warning message" {
    # Skip if running as root (would try actual install)
    if [[ $EUID -eq 0 ]]; then
        skip "Test should not run as root"
    fi
    
    run bash "$REMOTE_DESKTOP_SCRIPT" --dry-run install 2>&1
    # Should fail because not root, but should show dry-run message first
    output=$(strip_colors "$output")
    assert_output --partial "Dry run"
}

# =============================================================================
# Distribution Detection Tests
# =============================================================================

@test "remote-desktop: contains distro detection logic" {
    run grep -E "detect_system|DISTRO|os-release" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: supports Debian family" {
    run grep -E "debian|ubuntu|apt" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: supports RHEL family" {
    run grep -E "rhel|rocky|alma|dnf|yum" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: supports Fedora" {
    run grep -E "fedora" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: supports openSUSE" {
    run grep -E "suse|zypper" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

# =============================================================================
# xRDP Configuration Tests
# =============================================================================

@test "remote-desktop: references xrdp config files" {
    run grep -E "xrdp\.ini|sesman\.ini" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: configures startwm session" {
    run grep -E "startwm|session" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: supports multiple desktop environments" {
    run grep -E "GNOME|KDE|XFCE|MATE|Cinnamon" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: detects desktop environment" {
    run grep -E "XDG_CURRENT_DESKTOP|DESKTOP_SESSION|detect_desktop" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

# =============================================================================
# Firewall Configuration Tests
# =============================================================================

@test "remote-desktop: supports UFW firewall" {
    run grep -E "ufw" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: supports firewalld" {
    run grep -E "firewall-cmd|firewalld" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: supports iptables" {
    run grep -E "iptables" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: uses correct RDP port (3389)" {
    run grep -E "3389|RDP_PORT" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

# =============================================================================
# Security Hardening Tests
# =============================================================================

@test "remote-desktop: has security hardening function" {
    run grep -E "apply_security|security" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: configures TLS encryption" {
    run grep -E "tls|TLS|ssl|SSL|security_layer" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: supports fail2ban integration" {
    run grep -E "fail2ban" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: configures encryption level" {
    run grep -E "crypt_level|encryption" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: generates TLS certificates" {
    run grep -E "openssl|cert\.pem|key\.pem" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

# =============================================================================
# Service Management Tests
# =============================================================================

@test "remote-desktop: supports systemd" {
    run grep -E "systemctl|systemd" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: supports sysvinit fallback" {
    run grep -E "service xrdp|init\.d" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: has service start function" {
    run grep -E "service_start|start.*xrdp" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: has service stop function" {
    run grep -E "service_stop|stop.*xrdp" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: has service enable function" {
    run grep -E "service_enable|enable.*xrdp" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

# =============================================================================
# Safety Tests
# =============================================================================

@test "remote-desktop: checks for root privileges" {
    run grep -E "EUID|check_root|root" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: creates config backups" {
    run grep -E "backup|\.orig|\.bak" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: has uninstall function" {
    run grep -E "do_uninstall|uninstall" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: has confirmation prompts" {
    run grep -E "read.*-r.*confirm|Are you sure" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

# =============================================================================
# Polkit Configuration Tests
# =============================================================================

@test "remote-desktop: configures polkit rules" {
    run grep -E "polkit|pkla|color-manager" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

# =============================================================================
# Status Output Tests
# =============================================================================

@test "remote-desktop: status shows service info" {
    run grep -E "service_status|Service Status" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: status shows listening ports" {
    run grep -E "Listening|ss.*-tlnp|netstat" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: status shows connection info" {
    run grep -E "Connection Info|ip.*route|hostname" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

# =============================================================================
# RSR Library Integration Tests
# =============================================================================

@test "remote-desktop: attempts to load RSR library" {
    run grep -E "rsr-lib\.sh|RSR_LIB_DIR" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: has standalone fallback logging" {
    run grep -E "rsr_log_info|RSR_STANDALONE" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

# =============================================================================
# Color Support Tests
# =============================================================================

@test "remote-desktop: supports NO_COLOR environment" {
    run grep -E "NO_COLOR" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: has color definitions" {
    run grep -E "RED=|GREEN=|YELLOW=|BLUE=|NC=" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

# =============================================================================
# Interactive Mode Tests
# =============================================================================

@test "remote-desktop: has interactive menu function" {
    run grep -E "show_interactive_menu" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: interactive menu shows all options" {
    run grep -E "Install Remote Desktop|Uninstall|Start service|Stop service" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}

@test "remote-desktop: supports menu subcommand" {
    run bash "$REMOTE_DESKTOP_SCRIPT" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "menu"
}

@test "remote-desktop: help mentions interactive mode" {
    run bash "$REMOTE_DESKTOP_SCRIPT" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "INTERACTIVE MODE"
}

@test "remote-desktop: interactive menu checks TTY" {
    run grep -E "\-t 0|\-t 1|tty" "$REMOTE_DESKTOP_SCRIPT"
    assert_success
}
