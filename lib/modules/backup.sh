#!/bin/sh
# lib/modules/backup.sh - RSR Backup Management Module
# Unified backup operations across multiple backup tools
#
# Usage: . "${RSR_LIB_DIR:-./lib}/modules/backup.sh"
#
# Provides:
#   - Tool detection (rsync, rclone, restic, borg, kopia, timemachine)
#   - Unified backup interface
#   - Profile management
#   - Retention policies
#   - Pre/post hooks
#   - Verification and restore
#   - Notifications (desktop, email, webhook)
#   - Health checks and diagnostics

# =============================================================================
# Guard: Prevent double-sourcing
# =============================================================================

[ -n "${_RSR_MODULE_BACKUP_LOADED:-}" ] && return 0
_RSR_MODULE_BACKUP_LOADED=1

# Ensure core is loaded
if [ -z "${_RSR_CORE_INIT_LOADED:-}" ]; then
    _script_dir="$(cd "$(dirname "$0")" 2> /dev/null && pwd)" || _script_dir="."
    . "${_script_dir}/../core/init.sh" 2> /dev/null || . "./lib/core/init.sh" 2> /dev/null || {
        echo "ERROR: RSR core/init.sh must be sourced first" >&2
        return 1
    }
fi

# =============================================================================
# Module Metadata
# =============================================================================

_RSR_BACKUP_VERSION="1.0.0"

# Supported backup tools in priority order
RSR_BACKUP_TOOLS="restic rclone borg kopia rsync"

# =============================================================================
# Tool Detection
# =============================================================================

# Check if a specific backup tool is installed
# Usage: if rsr_backup_tool_installed "restic"; then ...
rsr_backup_tool_installed() {
    _tool="$1"
    case "$_tool" in
        rsync) rsr_has_command rsync ;;
        rclone) rsr_has_command rclone ;;
        restic) rsr_has_command restic ;;
        borg) rsr_has_command borg ;;
        kopia) rsr_has_command kopia ;;
        timemachine) [ "$(rsr_detect_os)" = "darwin" ] && rsr_has_command tmutil ;;
        duplicity) rsr_has_command duplicity ;;
        *) return 1 ;;
    esac
}

# Get version of a backup tool
# Usage: version=$(rsr_backup_tool_version "restic")
rsr_backup_tool_version() {
    _tool="$1"
    case "$_tool" in
        rsync)
            rsync --version 2> /dev/null | head -1 | awk '{print $3}'
            ;;
        rclone)
            rclone version 2> /dev/null | head -1 | awk '{print $2}' | tr -d 'v'
            ;;
        restic)
            restic version 2> /dev/null | awk '{print $2}'
            ;;
        borg)
            borg --version 2> /dev/null | awk '{print $2}'
            ;;
        kopia)
            kopia --version 2> /dev/null | awk '{print $1}'
            ;;
        timemachine)
            sw_vers -productVersion 2> /dev/null || echo "unknown"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# List all installed backup tools
# Usage: tools=$(rsr_backup_list_tools)
rsr_backup_list_tools() {
    _installed=""
    for _tool in $RSR_BACKUP_TOOLS timemachine; do
        if rsr_backup_tool_installed "$_tool"; then
            _version=$(rsr_backup_tool_version "$_tool")
            if [ -n "$_installed" ]; then
                _installed="$_installed $_tool:$_version"
            else
                _installed="$_tool:$_version"
            fi
        fi
    done
    echo "$_installed"
}

# Get best available backup tool
# Usage: tool=$(rsr_backup_get_default_tool)
rsr_backup_get_default_tool() {
    for _tool in $RSR_BACKUP_TOOLS; do
        if rsr_backup_tool_installed "$_tool"; then
            echo "$_tool"
            return 0
        fi
    done
    return 1
}

# =============================================================================
# Repository/Destination Management
# =============================================================================

# Initialize a backup repository
# Usage: rsr_backup_init_repo "restic" "/backup/repo" [password]
rsr_backup_init_repo() {
    _tool="$1"
    _repo="$2"
    _password="${3:-}"

    case "$_tool" in
        restic)
            if [ -n "$_password" ]; then
                RESTIC_PASSWORD="$_password" restic init --repo "$_repo"
            else
                restic init --repo "$_repo"
            fi
            ;;
        borg)
            if [ -n "$_password" ]; then
                BORG_PASSPHRASE="$_password" borg init --encryption=repokey "$_repo"
            else
                borg init --encryption=none "$_repo"
            fi
            ;;
        kopia)
            if [ -n "$_password" ]; then
                kopia repository create filesystem --path "$_repo" --password "$_password"
            else
                kopia repository create filesystem --path "$_repo"
            fi
            ;;
        rclone)
            # rclone doesn't need init for local, just ensure dir exists
            mkdir -p "$_repo"
            rsr_log_ok "Created rclone destination: $_repo"
            ;;
        rsync)
            mkdir -p "$_repo"
            rsr_log_ok "Created rsync destination: $_repo"
            ;;
        *)
            rsr_log_error "Unknown tool: $_tool"
            return 1
            ;;
    esac
}

# Check if repository exists and is valid
# Usage: if rsr_backup_repo_exists "restic" "/backup/repo"; then ...
rsr_backup_repo_exists() {
    _tool="$1"
    _repo="$2"

    case "$_tool" in
        restic)
            restic -r "$_repo" snapshots --json > /dev/null 2>&1
            ;;
        borg)
            borg info "$_repo" > /dev/null 2>&1
            ;;
        kopia)
            kopia repository status --path "$_repo" > /dev/null 2>&1
            ;;
        rclone | rsync)
            [ -d "$_repo" ]
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Backup Operations
# =============================================================================

# Perform a backup using the specified tool
# Usage: rsr_backup_create "restic" "/backup/repo" "/home/user" [options]
rsr_backup_create() {
    _tool="$1"
    _repo="$2"
    _source="$3"
    shift 3
    _opts="$*"

    if ! rsr_backup_tool_installed "$_tool"; then
        rsr_log_error "$_tool is not installed"
        return "$RSR_EXIT_DEPENDENCY"
    fi

    rsr_log_info "Creating backup with $_tool..."
    rsr_log_debug "Source: $_source"
    rsr_log_debug "Destination: $_repo"

    case "$_tool" in
        rsync)
            _rsync_opts="-avz --delete --progress"
            [ -n "$_opts" ] && _rsync_opts="$_rsync_opts $_opts"
            rsync $_rsync_opts "$_source/" "$_repo/"
            ;;
        rclone)
            _rclone_opts="sync --progress"
            [ -n "$_opts" ] && _rclone_opts="$_rclone_opts $_opts"
            rclone $_rclone_opts "$_source" "$_repo"
            ;;
        restic)
            _restic_opts=""
            [ -n "$_opts" ] && _restic_opts="$_opts"
            restic -r "$_repo" backup $_restic_opts "$_source"
            ;;
        borg)
            _timestamp=$(date +%Y-%m-%d_%H%M%S)
            _borg_opts=""
            [ -n "$_opts" ] && _borg_opts="$_opts"
            borg create $_borg_opts "${_repo}::backup-${_timestamp}" "$_source"
            ;;
        kopia)
            _kopia_opts=""
            [ -n "$_opts" ] && _kopia_opts="$_opts"
            kopia snapshot create $_kopia_opts "$_source"
            ;;
        *)
            rsr_log_error "Unknown tool: $_tool"
            return 1
            ;;
    esac
}

# List backups/snapshots
# Usage: rsr_backup_list "restic" "/backup/repo"
rsr_backup_list() {
    _tool="$1"
    _repo="$2"

    case "$_tool" in
        rsync | rclone)
            # Show directory listing for non-versioned tools
            ls -la "$_repo" 2> /dev/null
            ;;
        restic)
            restic -r "$_repo" snapshots
            ;;
        borg)
            borg list "$_repo"
            ;;
        kopia)
            kopia snapshot list
            ;;
        timemachine)
            tmutil listbackups 2> /dev/null
            ;;
        *)
            rsr_log_error "Unknown tool: $_tool"
            return 1
            ;;
    esac
}

# Restore from backup
# Usage: rsr_backup_restore "restic" "/backup/repo" "/restore/path" [snapshot_id]
rsr_backup_restore() {
    _tool="$1"
    _repo="$2"
    _target="$3"
    _snapshot="${4:-latest}"

    rsr_log_info "Restoring from $_tool backup..."

    case "$_tool" in
        rsync)
            rsync -avz --progress "$_repo/" "$_target/"
            ;;
        rclone)
            rclone sync --progress "$_repo" "$_target"
            ;;
        restic)
            restic -r "$_repo" restore "$_snapshot" --target "$_target"
            ;;
        borg)
            cd "$_target" && borg extract "${_repo}::${_snapshot}"
            ;;
        kopia)
            kopia snapshot restore "$_snapshot" "$_target"
            ;;
        *)
            rsr_log_error "Unknown tool: $_tool"
            return 1
            ;;
    esac
}

# =============================================================================
# Retention & Cleanup
# =============================================================================

# Apply retention policy
# Usage: rsr_backup_prune "restic" "/backup/repo" [keep_daily] [keep_weekly] [keep_monthly]
rsr_backup_prune() {
    _tool="$1"
    _repo="$2"
    _keep_daily="${3:-7}"
    _keep_weekly="${4:-4}"
    _keep_monthly="${5:-6}"

    rsr_log_info "Applying retention policy..."

    case "$_tool" in
        rsync | rclone)
            rsr_log_warn "Retention not supported for $_tool (no versioning)"
            ;;
        restic)
            restic -r "$_repo" forget \
                --keep-daily "$_keep_daily" \
                --keep-weekly "$_keep_weekly" \
                --keep-monthly "$_keep_monthly" \
                --prune
            ;;
        borg)
            borg prune "$_repo" \
                --keep-daily "$_keep_daily" \
                --keep-weekly "$_keep_weekly" \
                --keep-monthly "$_keep_monthly"
            ;;
        kopia)
            kopia policy set --global \
                --keep-daily "$_keep_daily" \
                --keep-weekly "$_keep_weekly" \
                --keep-monthly "$_keep_monthly"
            kopia maintenance run --full
            ;;
        *)
            rsr_log_error "Unknown tool: $_tool"
            return 1
            ;;
    esac
}

# =============================================================================
# Verification
# =============================================================================

# Verify backup integrity
# Usage: rsr_backup_verify "restic" "/backup/repo" [snapshot_id]
rsr_backup_verify() {
    _tool="$1"
    _repo="$2"
    _snapshot="${3:-}"

    rsr_log_info "Verifying backup integrity..."

    case "$_tool" in
        rsync | rclone)
            rsr_log_warn "Verification not directly supported for $_tool"
            [ -d "$_repo" ] && rsr_log_ok "Destination exists"
            ;;
        restic)
            if [ -n "$_snapshot" ]; then
                restic -r "$_repo" check --read-data-subset="$_snapshot"
            else
                restic -r "$_repo" check
            fi
            ;;
        borg)
            if [ -n "$_snapshot" ]; then
                borg check --verify-data "${_repo}::${_snapshot}"
            else
                borg check --verify-data "$_repo"
            fi
            ;;
        kopia)
            kopia snapshot verify
            ;;
        *)
            rsr_log_error "Unknown tool: $_tool"
            return 1
            ;;
    esac
}

# =============================================================================
# Statistics & Info
# =============================================================================

# Get backup statistics
# Usage: rsr_backup_stats "restic" "/backup/repo"
rsr_backup_stats() {
    _tool="$1"
    _repo="$2"

    case "$_tool" in
        rsync | rclone)
            du -sh "$_repo" 2> /dev/null
            ;;
        restic)
            restic -r "$_repo" stats
            ;;
        borg)
            borg info "$_repo"
            ;;
        kopia)
            kopia repository status
            ;;
        *)
            rsr_log_error "Unknown tool: $_tool"
            return 1
            ;;
    esac
}

# =============================================================================
# Profile Management
# =============================================================================

# Default profile directory
RSR_BACKUP_PROFILE_DIR="${RSR_CONFIG_DIR:-$HOME/.config/rsr}/backup/profiles"

# Load a backup profile
# Usage: eval $(rsr_backup_load_profile "daily")
rsr_backup_load_profile() {
    _profile_name="$1"
    _profile_file="$RSR_BACKUP_PROFILE_DIR/${_profile_name}.conf"

    if [ ! -f "$_profile_file" ]; then
        rsr_log_error "Profile not found: $_profile_name"
        return 1
    fi

    cat "$_profile_file"
}

# List available profiles
# Usage: rsr_backup_list_profiles
rsr_backup_list_profiles() {
    if [ -d "$RSR_BACKUP_PROFILE_DIR" ]; then
        ls -1 "$RSR_BACKUP_PROFILE_DIR"/*.conf 2> /dev/null | xargs -n1 basename 2> /dev/null | sed 's/\.conf$//'
    else
        rsr_log_warn "No profiles directory found"
    fi
}

# Create a backup profile
# Usage: rsr_backup_create_profile "daily" "restic" "/backup/repo" "/home"
rsr_backup_create_profile() {
    _name="$1"
    _tool="$2"
    _repo="$3"
    _sources="$4"
    _excludes="${5:-}"

    mkdir -p "$RSR_BACKUP_PROFILE_DIR"
    _profile_file="$RSR_BACKUP_PROFILE_DIR/${_name}.conf"

    cat > "$_profile_file" << EOF
# RSR Backup Profile: $_name
# Created: $(date -Iseconds)

BACKUP_TOOL="$_tool"
BACKUP_REPO="$_repo"
BACKUP_SOURCES="$_sources"
BACKUP_EXCLUDES="$_excludes"

# Retention policy
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6
KEEP_YEARLY=1

# Options
BACKUP_VERIFY=true
BACKUP_PRUNE=true
EOF

    rsr_log_ok "Created profile: $_name"
}

# =============================================================================
# Hooks
# =============================================================================

# Run pre-backup hooks
# Usage: rsr_backup_run_pre_hooks "/path/to/hooks"
rsr_backup_run_pre_hooks() {
    _hooks_dir="$1"
    if [ -d "$_hooks_dir/pre-backup.d" ]; then
        for _hook in "$_hooks_dir/pre-backup.d"/*; do
            if [ -x "$_hook" ]; then
                rsr_log_debug "Running pre-hook: $_hook"
                "$_hook" || rsr_log_warn "Pre-hook failed: $_hook"
            fi
        done
    fi
}

# Run post-backup hooks
# Usage: rsr_backup_run_post_hooks "/path/to/hooks" [exit_code]
rsr_backup_run_post_hooks() {
    _hooks_dir="$1"
    _exit_code="${2:-0}"
    export BACKUP_EXIT_CODE="$_exit_code"

    if [ -d "$_hooks_dir/post-backup.d" ]; then
        for _hook in "$_hooks_dir/post-backup.d"/*; do
            if [ -x "$_hook" ]; then
                rsr_log_debug "Running post-hook: $_hook"
                "$_hook" || rsr_log_warn "Post-hook failed: $_hook"
            fi
        done
    fi
}

# =============================================================================
# Installation Helpers
# =============================================================================

# Install a backup tool
# Usage: rsr_backup_install_tool "restic"
rsr_backup_install_tool() {
    _tool="$1"
    _os=$(rsr_detect_os)

    rsr_log_info "Installing $_tool..."

    case "$_os" in
        darwin)
            if rsr_has_command brew; then
                brew install "$_tool"
            else
                rsr_log_error "Homebrew required. Install with: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                return 1
            fi
            ;;
        linux)
            _distro=$(rsr_detect_distro)
            case "$_distro" in
                debian | ubuntu)
                    sudo apt-get update && sudo apt-get install -y "$_tool"
                    ;;
                fedora)
                    sudo dnf install -y "$_tool"
                    ;;
                arch)
                    sudo pacman -S --noconfirm "$_tool"
                    ;;
                alpine)
                    sudo apk add "$_tool"
                    ;;
                *)
                    rsr_log_error "Unsupported distribution: $_distro"
                    return 1
                    ;;
            esac
            ;;
        *)
            rsr_log_error "Unsupported OS: $_os"
            return 1
            ;;
    esac
}

# =============================================================================
# Scheduling Helpers
# =============================================================================

# Generate cron entry for backup
# Usage: cron_entry=$(rsr_backup_generate_cron "0 2 * * *" "daily")
rsr_backup_generate_cron() {
    _schedule="$1"
    _profile="$2"
    _rsr_path="${3:-rsr}"

    echo "$_schedule $_rsr_path backup run --profile $_profile --quiet"
}

# Generate launchd plist for macOS
# Usage: rsr_backup_generate_launchd "daily" > ~/Library/LaunchAgents/com.rsr.backup.daily.plist
rsr_backup_generate_launchd() {
    _profile="$1"
    _hour="${2:-2}"
    _minute="${3:-0}"

    cat << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.rsr.backup.$_profile</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/rsr</string>
        <string>backup</string>
        <string>run</string>
        <string>--profile</string>
        <string>$_profile</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$_hour</integer>
        <key>Minute</key>
        <integer>$_minute</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/rsr-backup-$_profile.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/rsr-backup-$_profile.err</string>
</dict>
</plist>
EOF
}

# Generate systemd timer for Linux
# Usage: rsr_backup_generate_systemd_timer "daily" > /etc/systemd/system/rsr-backup-daily.timer
rsr_backup_generate_systemd_timer() {
    _profile="$1"
    _oncalendar="${2:-*-*-* 02:00:00}"

    cat << EOF
[Unit]
Description=RSR Backup Timer ($_profile)

[Timer]
OnCalendar=$_oncalendar
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF
}

# Generate systemd service for Linux
# Usage: rsr_backup_generate_systemd_service "daily" > /etc/systemd/system/rsr-backup-daily.service
rsr_backup_generate_systemd_service() {
    _profile="$1"

    cat << EOF
[Unit]
Description=RSR Backup Service ($_profile)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rsr backup run --profile $_profile
User=root
Nice=19
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF
}

# =============================================================================
# Notifications
# =============================================================================

# Send backup notification
# Usage: rsr_backup_notify "success" "Backup completed" "Details..."
rsr_backup_notify() {
    _status="$1" # success, warning, error
    _title="$2"
    _message="$3"
    _os=$(rsr_detect_os)

    # Desktop notification
    case "$_os" in
        darwin)
            # macOS notification
            if rsr_has_command osascript; then
                osascript -e "display notification \"$_message\" with title \"$_title\""
            fi
            ;;
        linux)
            # Linux notification (notify-send)
            if rsr_has_command notify-send; then
                _icon="dialog-information"
                [ "$_status" = "error" ] && _icon="dialog-error"
                [ "$_status" = "warning" ] && _icon="dialog-warning"
                notify-send -i "$_icon" "$_title" "$_message"
            fi
            ;;
    esac

    # Email notification (if configured)
    if [ -n "${RSR_BACKUP_EMAIL:-}" ]; then
        rsr_backup_send_email "$_status" "$_title" "$_message"
    fi

    # Webhook notification (if configured)
    if [ -n "${RSR_BACKUP_WEBHOOK:-}" ]; then
        rsr_backup_send_webhook "$_status" "$_title" "$_message"
    fi
}

# Send email notification
# Usage: rsr_backup_send_email "success" "Backup completed" "Details..."
rsr_backup_send_email() {
    _status="$1"
    _title="$2"
    _message="$3"
    _email="${RSR_BACKUP_EMAIL:-}"

    [ -z "$_email" ] && return 1

    if rsr_has_command mail; then
        echo "$_message" | mail -s "[$_status] $_title" "$_email"
    elif rsr_has_command sendmail; then
        printf "Subject: [%s] %s\n\n%s" "$_status" "$_title" "$_message" | sendmail "$_email"
    fi
}

# Send webhook notification
# Usage: rsr_backup_send_webhook "success" "Backup completed" "Details..."
rsr_backup_send_webhook() {
    _status="$1"
    _title="$2"
    _message="$3"
    _webhook="${RSR_BACKUP_WEBHOOK:-}"

    [ -z "$_webhook" ] && return 1

    if rsr_has_command curl; then
        _json="{\"status\":\"$_status\",\"title\":\"$_title\",\"message\":\"$_message\",\"timestamp\":\"$(date -Iseconds)\",\"host\":\"$(hostname)\"}"
        curl -s -X POST -H "Content-Type: application/json" -d "$_json" "$_webhook" > /dev/null 2>&1
    fi
}

# =============================================================================
# Health Checks & Diagnostics
# =============================================================================

# Run backup health check
# Usage: rsr_backup_health_check [profile_name]
rsr_backup_health_check() {
    _profile="${1:-}"
    _issues=0

    echo "═══ Backup Health Check ═══"
    echo ""

    # Check 1: Backup tools installed
    echo "Backup Tools:"
    _tools_found=0
    for _tool in $RSR_BACKUP_TOOLS; do
        if rsr_backup_tool_installed "$_tool"; then
            _version=$(rsr_backup_tool_version "$_tool")
            echo "  ✓ $_tool ($_version)"
            _tools_found=1
        fi
    done

    if [ "$_tools_found" -eq 0 ]; then
        echo "  ✗ No backup tools installed!"
        _issues=$((_issues + 1))
    fi
    echo ""

    # Check 2: Profile configuration
    if [ -n "$_profile" ]; then
        echo "Profile: $_profile"
        _profile_file="$RSR_BACKUP_PROFILE_DIR/${_profile}.conf"

        if [ -f "$_profile_file" ]; then
            echo "  ✓ Profile file exists"

            # Source profile and check paths
            . "$_profile_file"

            # Check source paths
            for _src in $BACKUP_SOURCES; do
                if [ -e "$_src" ]; then
                    echo "  ✓ Source accessible: $_src"
                else
                    echo "  ✗ Source not found: $_src"
                    _issues=$((_issues + 1))
                fi
            done

            # Check destination
            if [ -n "${BACKUP_REPO:-}" ]; then
                # For local paths, check existence
                case "$BACKUP_REPO" in
                    /*)
                        if [ -d "$BACKUP_REPO" ] || [ -w "$(dirname "$BACKUP_REPO")" ]; then
                            echo "  ✓ Destination accessible: $BACKUP_REPO"
                        else
                            echo "  ⚠ Destination may need initialization: $BACKUP_REPO"
                        fi
                        ;;
                    *)
                        echo "  ○ Remote destination: $BACKUP_REPO"
                        ;;
                esac
            fi
        else
            echo "  ✗ Profile file not found"
            _issues=$((_issues + 1))
        fi
        echo ""
    fi

    # Check 3: Recent backups
    echo "Recent Backup Activity:"
    _backup_log="${RSR_LOG_DIR:-/var/log/rsr}/backup.log"
    if [ -f "$_backup_log" ]; then
        _last_backup=$(tail -1 "$_backup_log" 2> /dev/null)
        if [ -n "$_last_backup" ]; then
            echo "  Last entry: $_last_backup"
        fi
    else
        echo "  ○ No backup log found"
    fi
    echo ""

    # Check 4: Disk space
    echo "Disk Space:"
    if [ -n "${BACKUP_REPO:-}" ]; then
        case "$BACKUP_REPO" in
            /*)
                if [ -d "$BACKUP_REPO" ]; then
                    _usage=$(df -h "$BACKUP_REPO" 2> /dev/null | tail -1 | awk '{print $5}')
                    _available=$(df -h "$BACKUP_REPO" 2> /dev/null | tail -1 | awk '{print $4}')
                    if [ -n "$_usage" ]; then
                        echo "  Destination: $_usage used, $_available available"
                        # Warn if over 90%
                        _pct=$(echo "$_usage" | tr -d '%')
                        if [ "$_pct" -gt 90 ]; then
                            echo "  ⚠ Low disk space warning!"
                            _issues=$((_issues + 1))
                        fi
                    fi
                fi
                ;;
        esac
    fi
    echo ""

    # Check 5: Scheduled tasks
    echo "Scheduled Backups:"
    _os=$(rsr_detect_os)
    case "$_os" in
        darwin)
            _jobs=$(launchctl list 2> /dev/null | grep -c "rsr.backup" || echo "0")
            echo "  LaunchAgent jobs: $_jobs"
            ;;
        linux)
            if rsr_has_command systemctl; then
                _jobs=$(systemctl list-timers 2> /dev/null | grep -c "rsr-backup" || echo "0")
                echo "  Systemd timers: $_jobs"
            fi
            _cron_jobs=$(crontab -l 2> /dev/null | grep -c "rsr backup" || echo "0")
            echo "  Cron jobs: $_cron_jobs"
            ;;
    esac
    echo ""

    # Summary
    echo "─────────────────────────"
    if [ "$_issues" -eq 0 ]; then
        echo "Health check: PASSED ✓"
    else
        echo "Health check: $_issues issue(s) found ⚠"
    fi

    return "$_issues"
}

# Get backup statistics summary
# Usage: rsr_backup_summary "restic" "/backup/repo"
rsr_backup_summary() {
    _tool="$1"
    _repo="$2"

    echo "═══ Backup Summary ═══"
    echo ""
    echo "Tool: $_tool"
    echo "Repository: $_repo"
    echo ""

    case "$_tool" in
        restic)
            if [ -n "${RESTIC_PASSWORD:-}" ]; then
                _snapshots=$(restic -r "$_repo" snapshots --json 2> /dev/null | grep -c '"id"' || echo "0")
                echo "Snapshots: $_snapshots"
                restic -r "$_repo" stats --mode raw-data 2> /dev/null | head -10
            fi
            ;;
        borg)
            if [ -n "${BORG_PASSPHRASE:-}" ]; then
                borg info "$_repo" 2> /dev/null | head -20
            fi
            ;;
        kopia)
            kopia repository status 2> /dev/null | head -10
            ;;
        *)
            if [ -d "$_repo" ]; then
                _size=$(du -sh "$_repo" 2> /dev/null | cut -f1)
                echo "Size: $_size"
                _count=$(find "$_repo" -type f 2> /dev/null | wc -l | tr -d ' ')
                echo "Files: $_count"
            fi
            ;;
    esac
}

# Quick backup status check
# Usage: if rsr_backup_is_running; then echo "Backup in progress"; fi
rsr_backup_is_running() {
    # Check for common backup processes
    pgrep -x "restic" > /dev/null 2>&1 && return 0
    pgrep -x "borg" > /dev/null 2>&1 && return 0
    pgrep -x "kopia" > /dev/null 2>&1 && return 0
    pgrep -x "rclone" > /dev/null 2>&1 && return 0
    pgrep -f "rsync.*--delete" > /dev/null 2>&1 && return 0
    return 1
}

# Get last backup time from log
# Usage: last_time=$(rsr_backup_last_time "profile_name")
rsr_backup_last_time() {
    _profile="${1:-}"
    _backup_log="${RSR_LOG_DIR:-$HOME/.local/share/rsr}/backup.log"

    if [ -f "$_backup_log" ]; then
        if [ -n "$_profile" ]; then
            grep "$_profile" "$_backup_log" 2> /dev/null | tail -1 | awk '{print $1, $2}'
        else
            tail -1 "$_backup_log" 2> /dev/null | awk '{print $1, $2}'
        fi
    fi
}

rsr_log_debug "RSR Backup module v$_RSR_BACKUP_VERSION loaded"
