#!/usr/bin/env bash
# ============================================================================
# Safety Layer
# Undo/restore, backups, and safe operations
# ============================================================================

set -euo pipefail

_SAFETY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SAFETY_DIR/platform.sh" 2>/dev/null || true
source "$_SAFETY_DIR/logger.sh" 2>/dev/null || true

# Undo history directory
UNDO_DIR="${DECLUTTER_CONFIG_DIR:-$HOME/.declutter}/undo"
UNDO_MANIFEST="$UNDO_DIR/manifest.json"
MAX_UNDO_SESSIONS=50

# Initialize undo system
init_undo() {
    mkdir -p "$UNDO_DIR"
    if [[ ! -f "$UNDO_MANIFEST" ]]; then
        echo '{"sessions": []}' > "$UNDO_MANIFEST"
    fi
}

# Create new undo session
create_undo_session() {
    local description=${1:-"Declutter operation"}
    local session_id
    session_id="session_$(date +%Y%m%d_%H%M%S)_$$"
    local session_dir="$UNDO_DIR/$session_id"

    mkdir -p "$session_dir"

    cat > "$session_dir/metadata.json" << EOF
{
    "id": "$session_id",
    "description": "$description",
    "timestamp": "$(date -Iseconds)",
    "platform": "$PLATFORM",
    "operations": []
}
EOF

    echo "$session_id"
}

# Record operation for undo
record_operation() {
    local session_id=$1
    local operation=$2  # delete, move, rename
    local source_path=$3
    local dest_path=${4:-""}
    local session_dir="$UNDO_DIR/$session_id"

    # For delete operations, backup the file
    if [[ "$operation" == "delete" && -f "$source_path" ]]; then
        local backup_name
        backup_name=$(basename "$source_path")
        local backup_path="$session_dir/files/$backup_name"
        mkdir -p "$session_dir/files"
        cp -p "$source_path" "$backup_path"
        dest_path="$backup_path"
    fi

    # Append to operations log
    local ops_file="$session_dir/operations.log"
    echo "$operation|$source_path|$dest_path" >> "$ops_file"

    log_debug "Recorded: $operation $source_path -> $dest_path"
}

# Undo a session
undo_session() {
    local session_id=$1
    local session_dir="$UNDO_DIR/$session_id"

    if [[ ! -d "$session_dir" ]]; then
        log_error "Session not found: $session_id"
        return 1
    fi

    local ops_file="$session_dir/operations.log"
    if [[ ! -f "$ops_file" ]]; then
        log_warn "No operations to undo"
        return 0
    fi

    log_info "Undoing session: $session_id"

    # Process operations in reverse order
    tac "$ops_file" | while IFS='|' read -r operation source_path dest_path; do
        case "$operation" in
            delete)
                if [[ -f "$dest_path" ]]; then
                    local restore_dir
                    restore_dir=$(dirname "$source_path")
                    mkdir -p "$restore_dir"
                    mv "$dest_path" "$source_path"
                    log_success "Restored: $source_path"
                fi
                ;;
            move)
                if [[ -e "$dest_path" ]]; then
                    mv "$dest_path" "$source_path"
                    log_success "Moved back: $dest_path -> $source_path"
                fi
                ;;
            rename)
                if [[ -e "$dest_path" ]]; then
                    mv "$dest_path" "$source_path"
                    log_success "Renamed back: $dest_path -> $source_path"
                fi
                ;;
        esac
    done

    # Mark session as undone
    mv "$session_dir" "${session_dir}.undone"
    log_success "Session $session_id undone successfully"
}

# List available undo sessions
list_undo_sessions() {
    local count=0
    echo ""
    print_header "Available Undo Sessions"

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

        if [[ -f "$metadata" ]]; then
            timestamp=$(grep -o '"timestamp": "[^"]*"' "$metadata" | cut -d'"' -f4)
            description=$(grep -o '"description": "[^"]*"' "$metadata" | cut -d'"' -f4)
        fi

        if [[ -f "$ops_file" ]]; then
            op_count=$(wc -l < "$ops_file")
        fi

        printf "  ${CYAN}%s${NC}\n" "$session_id"
        printf "    Timestamp: %s\n" "$timestamp"
        printf "    Description: %s\n" "$description"
        printf "    Operations: %d\n\n" "$op_count"

        ((count++))
    done

    if [[ $count -eq 0 ]]; then
        echo "  No undo sessions available"
    fi
}

# Cleanup old undo sessions
cleanup_undo_sessions() {
    local sessions=("$UNDO_DIR"/session_*)
    local count=${#sessions[@]}

    if (( count > MAX_UNDO_SESSIONS )); then
        local to_remove=$((count - MAX_UNDO_SESSIONS))
        log_info "Cleaning up $to_remove old undo sessions"

        # Remove oldest sessions first (sorted by name = sorted by date)
        for session in "${sessions[@]:0:$to_remove}"; do
            rm -rf "$session"
            log_debug "Removed old session: $(basename "$session")"
        done
    fi
}

# Safe delete (with backup)
safe_delete() {
    local file=$1
    local session_id=${2:-""}

    if [[ ! -e "$file" ]]; then
        log_warn "File not found: $file"
        return 1
    fi

    # Record for undo if session provided
    if [[ -n "$session_id" ]]; then
        record_operation "$session_id" "delete" "$file"
    fi

    # Check if dry run
    if is_dry_run; then
        log_info "[DRY RUN] Would delete: $file"
        return 0
    fi

    # Use trash or permanent delete
    if use_trash; then
        move_to_trash "$file"
        log_action "TRASH" "$file"
    else
        rm -rf "$file"
        log_action "DELETE" "$file"
    fi
}

# Safe move (with undo support)
safe_move() {
    local source=$1
    local dest=$2
    local session_id=${3:-""}

    if [[ ! -e "$source" ]]; then
        log_warn "Source not found: $source"
        return 1
    fi

    # Record for undo
    if [[ -n "$session_id" ]]; then
        record_operation "$session_id" "move" "$source" "$dest"
    fi

    if is_dry_run; then
        log_info "[DRY RUN] Would move: $source -> $dest"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    mv "$source" "$dest"
    log_action "MOVE" "$source" "to $dest"
}

# Safe rename
safe_rename() {
    local source=$1
    local new_name=$2
    local session_id=${3:-""}

    local dir
    dir=$(dirname "$source")
    local dest="$dir/$new_name"

    if [[ -n "$session_id" ]]; then
        record_operation "$session_id" "rename" "$source" "$dest"
    fi

    if is_dry_run; then
        log_info "[DRY RUN] Would rename: $source -> $new_name"
        return 0
    fi

    mv "$source" "$dest"
    log_action "RENAME" "$source" "to $new_name"
}

# Confirm action from user
confirm_action() {
    local message=$1
    local default=${2:-"n"}

    if ! should_confirm; then
        return 0
    fi

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    echo -en "${YELLOW}$message $prompt${NC} "
    read -r response

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        [nN][oO]|[nN]) return 1 ;;
        "") [[ "$default" == "y" ]] && return 0 || return 1 ;;
        *) return 1 ;;
    esac
}

export -f init_undo create_undo_session record_operation undo_session
export -f list_undo_sessions cleanup_undo_sessions
export -f safe_delete safe_move safe_rename confirm_action
