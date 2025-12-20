#!/usr/bin/env bash
# ============================================================================
# Undo System
# Provides undo/restore capability for file operations
# ============================================================================

set -euo pipefail

# Prevent double-sourcing
[[ "${_DECLUTTER_UNDO_LOADED:-}" == "true" ]] && return 0
readonly _DECLUTTER_UNDO_LOADED="true"

# =============================================================================
# Configuration
# =============================================================================

UNDO_DIR="${DECLUTTER_UNDO_DIR:-$HOME/.declutter/undo}"
MAX_UNDO_SESSIONS="${MAX_UNDO_SESSIONS:-50}"
UNDO_RETENTION_DAYS="${UNDO_RETENTION_DAYS:-30}"

# Current session (set when creating a session)
_CURRENT_UNDO_SESSION=""

# =============================================================================
# Initialization
# =============================================================================

undo_init() {
    mkdir -p "$UNDO_DIR"
}

# =============================================================================
# Session Management
# =============================================================================

# Create a new undo session
undo_create_session() {
    local description=${1:-"Declutter operation"}
    local session_id
    session_id="session_$(date +%Y%m%d_%H%M%S)_$$"
    local session_dir="$UNDO_DIR/$session_id"

    mkdir -p "$session_dir/files"

    # Create metadata
    cat > "$session_dir/metadata.json" << EOF
{
    "id": "$session_id",
    "description": "$description",
    "timestamp": "$(date -Iseconds)",
    "platform": "${PLATFORM:-unknown}",
    "user": "${USER:-unknown}",
    "cwd": "$(pwd)",
    "operation_count": 0
}
EOF

    # Create empty operations log
    touch "$session_dir/operations.log"

    _CURRENT_UNDO_SESSION="$session_id"
    echo "$session_id"
}

# Get current session ID
undo_get_current_session() {
    echo "$_CURRENT_UNDO_SESSION"
}

# Set current session
undo_set_current_session() {
    _CURRENT_UNDO_SESSION="$1"
}

# Close current session
undo_close_session() {
    local session_id=${1:-$_CURRENT_UNDO_SESSION}

    if [[ -n "$session_id" && -d "$UNDO_DIR/$session_id" ]]; then
        # Update operation count in metadata
        local ops_count
        ops_count=$(wc -l < "$UNDO_DIR/$session_id/operations.log" 2>/dev/null || echo "0")

        if command -v jq &>/dev/null; then
            local metadata="$UNDO_DIR/$session_id/metadata.json"
            local tmp
            tmp=$(mktemp)
            jq ".operation_count = $ops_count | .closed_at = \"$(date -Iseconds)\"" "$metadata" > "$tmp" && mv "$tmp" "$metadata"
        fi
    fi

    _CURRENT_UNDO_SESSION=""
}

# =============================================================================
# Operation Recording
# =============================================================================

# Record an operation for potential undo
undo_record() {
    local operation=$1      # delete, move, rename, copy
    local source_path=$2
    local dest_path=${3:-""}
    local session_id=${4:-$_CURRENT_UNDO_SESSION}

    if [[ -z "$session_id" ]]; then
        log_warn "No active undo session"
        return 1
    fi

    local session_dir="$UNDO_DIR/$session_id"

    if [[ ! -d "$session_dir" ]]; then
        log_error "Session not found: $session_id"
        return 1
    fi

    # For delete operations, backup the file
    if [[ "$operation" == "delete" && -e "$source_path" ]]; then
        local basename
        basename=$(basename "$source_path")
        # Use timestamp to avoid collisions
        local backup_name="${basename}.$(date +%s%N)"
        local backup_path="$session_dir/files/$backup_name"

        if [[ -f "$source_path" ]]; then
            cp -p "$source_path" "$backup_path"
        elif [[ -d "$source_path" ]]; then
            cp -rp "$source_path" "$backup_path"
        fi

        # Record with backup path
        echo "$operation|$source_path|$backup_path" >> "$session_dir/operations.log"
    else
        # Record without backup
        echo "$operation|$source_path|$dest_path" >> "$session_dir/operations.log"
    fi
}

# =============================================================================
# Undo Operations
# =============================================================================

# Undo a specific session
undo_session() {
    local session_id=$1
    local session_dir="$UNDO_DIR/$session_id"

    if [[ ! -d "$session_dir" ]]; then
        log_error "Session not found: $session_id"
        return 1
    fi

    local ops_file="$session_dir/operations.log"

    if [[ ! -f "$ops_file" || ! -s "$ops_file" ]]; then
        log_warn "No operations to undo"
        return 0
    fi

    log_info "Undoing session: $session_id"

    local restored=0
    local failed=0

    # Process operations in reverse order
    tac "$ops_file" | while IFS='|' read -r operation source_path backup_or_dest; do
        case "$operation" in
            delete)
                # Restore from backup
                if [[ -e "$backup_or_dest" ]]; then
                    local restore_dir
                    restore_dir=$(dirname "$source_path")
                    mkdir -p "$restore_dir"

                    if mv "$backup_or_dest" "$source_path" 2>/dev/null; then
                        log_success "Restored: $source_path"
                        ((restored++))
                    else
                        log_error "Failed to restore: $source_path"
                        ((failed++))
                    fi
                else
                    log_warn "Backup not found for: $source_path"
                    ((failed++))
                fi
                ;;
            move)
                # Move back to original location
                if [[ -e "$backup_or_dest" ]]; then
                    local restore_dir
                    restore_dir=$(dirname "$source_path")
                    mkdir -p "$restore_dir"

                    if mv "$backup_or_dest" "$source_path" 2>/dev/null; then
                        log_success "Moved back: $backup_or_dest -> $source_path"
                        ((restored++))
                    else
                        log_error "Failed to move back: $backup_or_dest"
                        ((failed++))
                    fi
                fi
                ;;
            rename)
                # Rename back to original name
                if [[ -e "$backup_or_dest" ]]; then
                    if mv "$backup_or_dest" "$source_path" 2>/dev/null; then
                        log_success "Renamed back: $backup_or_dest -> $source_path"
                        ((restored++))
                    else
                        log_error "Failed to rename back: $backup_or_dest"
                        ((failed++))
                    fi
                fi
                ;;
            copy)
                # Remove the copy
                if [[ -e "$backup_or_dest" ]]; then
                    if rm -rf "$backup_or_dest" 2>/dev/null; then
                        log_success "Removed copy: $backup_or_dest"
                        ((restored++))
                    fi
                fi
                ;;
        esac
    done

    # Mark session as undone
    mv "$session_dir" "${session_dir}.undone"

    log_success "Session $session_id undone ($restored restored, $failed failed)"
}

# Undo the most recent session
undo_last() {
    local latest
    latest=$(undo_list_sessions | head -1 | awk '{print $1}')

    if [[ -n "$latest" ]]; then
        undo_session "$latest"
    else
        log_info "No sessions to undo"
    fi
}

# =============================================================================
# Session Listing & Info
# =============================================================================

# List all undo sessions
undo_list_sessions() {
    for session_dir in "$UNDO_DIR"/session_*; do
        [[ -d "$session_dir" ]] || continue
        [[ "$session_dir" == *.undone ]] && continue

        local session_id
        session_id=$(basename "$session_dir")
        local metadata="$session_dir/metadata.json"
        local ops_file="$session_dir/operations.log"

        local timestamp=""
        local description=""
        local op_count=0

        if [[ -f "$metadata" ]] && command -v jq &>/dev/null; then
            timestamp=$(jq -r '.timestamp // ""' "$metadata" 2>/dev/null)
            description=$(jq -r '.description // ""' "$metadata" 2>/dev/null)
        fi

        if [[ -f "$ops_file" ]]; then
            op_count=$(wc -l < "$ops_file" | tr -d ' ')
        fi

        printf "%-35s  %s  %3d ops  %s\n" "$session_id" "${timestamp:0:19}" "$op_count" "$description"
    done | sort -r
}

# Show detailed session info
undo_session_info() {
    local session_id=$1
    local session_dir="$UNDO_DIR/$session_id"

    if [[ ! -d "$session_dir" ]]; then
        log_error "Session not found: $session_id"
        return 1
    fi

    local metadata="$session_dir/metadata.json"
    local ops_file="$session_dir/operations.log"

    print_section "Session: $session_id"

    if [[ -f "$metadata" ]] && command -v jq &>/dev/null; then
        echo "Metadata:"
        jq '.' "$metadata"
    fi

    if [[ -f "$ops_file" && -s "$ops_file" ]]; then
        echo ""
        echo "Operations:"
        while IFS='|' read -r op source dest; do
            printf "  %-8s %s" "$op" "$source"
            [[ -n "$dest" ]] && printf " -> %s" "$dest"
            echo ""
        done < "$ops_file"
    fi
}

# =============================================================================
# Cleanup
# =============================================================================

# Remove old undo sessions
undo_cleanup() {
    local max_age_days=${1:-$UNDO_RETENTION_DAYS}
    local removed=0

    # Remove sessions older than max_age_days
    find "$UNDO_DIR" -maxdepth 1 -type d -name "session_*" -mtime "+$max_age_days" | while read -r session_dir; do
        rm -rf "$session_dir"
        ((removed++))
    done

    # Keep only MAX_UNDO_SESSIONS most recent
    local sessions=("$UNDO_DIR"/session_*)
    local count=${#sessions[@]}

    if ((count > MAX_UNDO_SESSIONS)); then
        local to_remove=$((count - MAX_UNDO_SESSIONS))

        # Remove oldest sessions (sorted by name = sorted by date)
        for session in "${sessions[@]:0:$to_remove}"; do
            [[ -d "$session" ]] && rm -rf "$session"
            ((removed++))
        done
    fi

    # Also remove .undone sessions
    find "$UNDO_DIR" -maxdepth 1 -type d -name "*.undone" -mtime "+7" -exec rm -rf {} \; 2>/dev/null || true

    log_info "Cleaned up $removed old undo sessions"
}

# =============================================================================
# Export
# =============================================================================

export UNDO_DIR MAX_UNDO_SESSIONS UNDO_RETENTION_DAYS

export -f undo_init
export -f undo_create_session undo_get_current_session undo_set_current_session undo_close_session
export -f undo_record
export -f undo_session undo_last
export -f undo_list_sessions undo_session_info
export -f undo_cleanup
