#!/usr/bin/env bash
# =============================================================================
# Declutter Tool - Undo/Restore Module
# Transaction logging and restore capabilities
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

DECLUTTER_DATA_DIR="${DECLUTTER_DATA_DIR:-$(get_home_dir)/.declutter}"
UNDO_LOG_DIR="$DECLUTTER_DATA_DIR/undo"
MAX_UNDO_HISTORY="${MAX_UNDO_HISTORY:-100}"

# Current transaction
CURRENT_TRANSACTION_ID=""
CURRENT_TRANSACTION_FILE=""

# =============================================================================
# INITIALIZATION
# =============================================================================

init_undo_system() {
    mkdir -p "$UNDO_LOG_DIR"

    # Clean old transactions
    cleanup_old_transactions

    log_debug "Undo system initialized at: $UNDO_LOG_DIR"
}

cleanup_old_transactions() {
    local count
    count=$(find "$UNDO_LOG_DIR" -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ $count -gt $MAX_UNDO_HISTORY ]]; then
        local to_delete=$((count - MAX_UNDO_HISTORY))
        find "$UNDO_LOG_DIR" -name "*.log" -type f -printf '%T+ %p\n' 2>/dev/null | \
            sort | head -n "$to_delete" | cut -d' ' -f2- | \
            xargs rm -f 2>/dev/null || true

        log_debug "Cleaned $to_delete old transaction logs"
    fi
}

# =============================================================================
# TRANSACTION MANAGEMENT
# =============================================================================

start_transaction() {
    local description="${1:-Declutter operation}"

    CURRENT_TRANSACTION_ID="$(date +%Y%m%d_%H%M%S)_$$"
    CURRENT_TRANSACTION_FILE="$UNDO_LOG_DIR/${CURRENT_TRANSACTION_ID}.log"

    mkdir -p "$UNDO_LOG_DIR"

    cat > "$CURRENT_TRANSACTION_FILE" <<EOF
# Declutter Transaction Log
# ID: $CURRENT_TRANSACTION_ID
# Description: $description
# Started: $(date '+%Y-%m-%d %H:%M:%S')
# Status: IN_PROGRESS
#
# Format: ACTION|SOURCE|DESTINATION|SIZE|TIMESTAMP
EOF

    log_debug "Started transaction: $CURRENT_TRANSACTION_ID"
    echo "$CURRENT_TRANSACTION_ID"
}

commit_transaction() {
    if [[ -z "$CURRENT_TRANSACTION_FILE" ]] || [[ ! -f "$CURRENT_TRANSACTION_FILE" ]]; then
        return 1
    fi

    sed -i.bak "s/Status: IN_PROGRESS/Status: COMMITTED/" "$CURRENT_TRANSACTION_FILE"
    rm -f "${CURRENT_TRANSACTION_FILE}.bak"

    echo "# Committed: $(date '+%Y-%m-%d %H:%M:%S')" >> "$CURRENT_TRANSACTION_FILE"

    log_debug "Committed transaction: $CURRENT_TRANSACTION_ID"

    CURRENT_TRANSACTION_ID=""
    CURRENT_TRANSACTION_FILE=""
}

rollback_transaction() {
    if [[ -z "$CURRENT_TRANSACTION_FILE" ]] || [[ ! -f "$CURRENT_TRANSACTION_FILE" ]]; then
        return 1
    fi

    log_info "Rolling back transaction: $CURRENT_TRANSACTION_ID"

    undo_transaction "$CURRENT_TRANSACTION_ID"

    sed -i.bak "s/Status: IN_PROGRESS/Status: ROLLED_BACK/" "$CURRENT_TRANSACTION_FILE"
    rm -f "${CURRENT_TRANSACTION_FILE}.bak"

    CURRENT_TRANSACTION_ID=""
    CURRENT_TRANSACTION_FILE=""
}

# =============================================================================
# ACTION LOGGING
# =============================================================================

log_action() {
    local action="$1"      # MOVE, DELETE, RENAME, CREATE
    local source="$2"
    local destination="${3:-}"
    local size="${4:-0}"

    if [[ -z "$CURRENT_TRANSACTION_FILE" ]]; then
        # Create a single-action transaction
        start_transaction "Single action"
    fi

    local timestamp
    timestamp=$(date +%s)

    echo "${action}|${source}|${destination}|${size}|${timestamp}" >> "$CURRENT_TRANSACTION_FILE"
}

# Wrapped safe operations that log actions
logged_move() {
    local src="$1"
    local dest="$2"

    local size=0
    if [[ -e "$src" ]]; then
        if [[ -d "$src" ]]; then
            size=$(du -sk "$src" 2>/dev/null | cut -f1 || echo 0)
            size=$((size * 1024))
        else
            size=$(stat -f%z "$src" 2>/dev/null || stat -c%s "$src" 2>/dev/null || echo 0)
        fi
    fi

    if safe_move "$src" "$dest"; then
        log_action "MOVE" "$src" "$dest" "$size"
        return 0
    fi
    return 1
}

logged_delete() {
    local file="$1"
    local use_trash="${2:-true}"

    local size=0
    local trash_dest=""

    if [[ -e "$file" ]]; then
        if [[ -d "$file" ]]; then
            size=$(du -sk "$file" 2>/dev/null | cut -f1 || echo 0)
            size=$((size * 1024))
        else
            size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        fi
    fi

    if [[ "$use_trash" == "true" ]]; then
        trash_dest="$(get_trash_dir)/$(basename "$file")"
    fi

    if safe_delete "$file" "$use_trash"; then
        if [[ "$use_trash" == "true" ]]; then
            log_action "TRASH" "$file" "$trash_dest" "$size"
        else
            log_action "DELETE" "$file" "" "$size"
        fi
        return 0
    fi
    return 1
}

# =============================================================================
# UNDO OPERATIONS
# =============================================================================

list_transactions() {
    local limit="${1:-20}"

    echo "Recent transactions:"
    echo ""
    printf "%-24s %-12s %-40s\n" "TRANSACTION ID" "STATUS" "DESCRIPTION"
    echo "--------------------------------------------------------------------------------"

    find "$UNDO_LOG_DIR" -name "*.log" -type f 2>/dev/null | \
        sort -r | head -n "$limit" | while read -r log_file; do
        local id
        id=$(basename "$log_file" .log)

        local status
        status=$(grep "^# Status:" "$log_file" | cut -d: -f2 | xargs)

        local desc
        desc=$(grep "^# Description:" "$log_file" | cut -d: -f2- | xargs | cut -c1-40)

        printf "%-24s %-12s %-40s\n" "$id" "$status" "$desc"
    done
}

show_transaction() {
    local transaction_id="$1"
    local log_file="$UNDO_LOG_DIR/${transaction_id}.log"

    if [[ ! -f "$log_file" ]]; then
        log_error "Transaction not found: $transaction_id"
        return 1
    fi

    echo "Transaction: $transaction_id"
    echo ""

    # Show header info
    grep "^#" "$log_file" | head -6

    echo ""
    echo "Actions:"
    echo ""

    local action_num=0
    while IFS='|' read -r action source dest size timestamp; do
        [[ "$action" == "#"* ]] && continue
        [[ -z "$action" ]] && continue

        ((action_num++))

        local date_str
        date_str=$(date -r "$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")

        echo "  $action_num. [$action] $source"
        [[ -n "$dest" ]] && echo "      -> $dest"
        echo "      Size: $(human_readable_size "$size"), Time: $date_str"
        echo ""
    done < <(grep -v "^#" "$log_file")

    echo "Total actions: $action_num"
}

undo_transaction() {
    local transaction_id="$1"
    local log_file="$UNDO_LOG_DIR/${transaction_id}.log"

    if [[ ! -f "$log_file" ]]; then
        log_error "Transaction not found: $transaction_id"
        return 1
    fi

    log_info "Undoing transaction: $transaction_id"

    # Read actions in reverse order
    local actions=()
    while IFS= read -r line; do
        [[ "$line" == "#"* ]] && continue
        [[ -z "$line" ]] && continue
        actions+=("$line")
    done < "$log_file"

    local undone=0
    local failed=0

    # Process in reverse
    for ((i=${#actions[@]}-1; i>=0; i--)); do
        IFS='|' read -r action source dest size timestamp <<< "${actions[$i]}"

        case "$action" in
            MOVE|RENAME)
                if [[ -e "$dest" ]] && [[ ! -e "$source" ]]; then
                    if mv "$dest" "$source" 2>/dev/null; then
                        log_info "Restored: $dest -> $source"
                        ((undone++))
                    else
                        log_error "Failed to restore: $dest"
                        ((failed++))
                    fi
                else
                    log_warn "Cannot undo: source exists or dest missing"
                    ((failed++))
                fi
                ;;
            TRASH)
                if [[ -e "$dest" ]] && [[ ! -e "$source" ]]; then
                    local dest_dir
                    dest_dir="$(dirname "$source")"
                    mkdir -p "$dest_dir"

                    if mv "$dest" "$source" 2>/dev/null; then
                        log_info "Restored from trash: $source"
                        ((undone++))
                    else
                        log_error "Failed to restore from trash: $dest"
                        ((failed++))
                    fi
                else
                    log_warn "Cannot restore: file missing from trash or already exists"
                    ((failed++))
                fi
                ;;
            DELETE)
                log_warn "Cannot undo permanent delete: $source"
                ((failed++))
                ;;
            CREATE)
                if [[ -e "$source" ]]; then
                    rm -rf "$source" 2>/dev/null
                    log_info "Removed created item: $source"
                    ((undone++))
                fi
                ;;
        esac
    done

    # Mark transaction as undone
    sed -i.bak "s/Status: COMMITTED/Status: UNDONE/" "$log_file"
    rm -f "${log_file}.bak"

    echo "# Undone: $(date '+%Y-%m-%d %H:%M:%S')" >> "$log_file"

    echo ""
    log_info "Undo complete: $undone restored, $failed failed"
}

undo_last() {
    local last_transaction
    last_transaction=$(find "$UNDO_LOG_DIR" -name "*.log" -type f 2>/dev/null | \
                       sort -r | head -1 | xargs basename 2>/dev/null | sed 's/.log$//')

    if [[ -z "$last_transaction" ]]; then
        log_error "No transactions to undo"
        return 1
    fi

    # Check if already undone
    local status
    status=$(grep "^# Status:" "$UNDO_LOG_DIR/${last_transaction}.log" | cut -d: -f2 | xargs)

    if [[ "$status" == "UNDONE" ]]; then
        log_warn "Last transaction already undone"
        return 1
    fi

    undo_transaction "$last_transaction"
}

# =============================================================================
# BACKUP/RESTORE
# =============================================================================

create_restore_point() {
    local name="${1:-manual}"
    local dirs=("${@:2}")

    local restore_id
    restore_id="restore_$(date +%Y%m%d_%H%M%S)_${name}"
    local restore_dir="$DECLUTTER_DATA_DIR/restore_points/$restore_id"

    mkdir -p "$restore_dir"

    log_info "Creating restore point: $restore_id"

    # Save directory listings
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local safe_name
            safe_name=$(echo "$dir" | tr '/' '_')
            find "$dir" -type f > "$restore_dir/${safe_name}.files"
            find "$dir" -type d > "$restore_dir/${safe_name}.dirs"
        fi
    done

    # Save metadata
    cat > "$restore_dir/metadata.json" <<EOF
{
  "id": "$restore_id",
  "name": "$name",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "directories": $(printf '%s\n' "${dirs[@]}" | jq -R . | jq -s .)
}
EOF

    log_info "Restore point created: $restore_id"
    echo "$restore_id"
}

list_restore_points() {
    local restore_dir="$DECLUTTER_DATA_DIR/restore_points"

    if [[ ! -d "$restore_dir" ]]; then
        echo "No restore points found"
        return 0
    fi

    echo "Restore points:"
    echo ""

    find "$restore_dir" -maxdepth 1 -type d -name "restore_*" | sort -r | while read -r rp; do
        local id
        id=$(basename "$rp")

        if [[ -f "$rp/metadata.json" ]]; then
            local name created
            name=$(grep '"name"' "$rp/metadata.json" | cut -d'"' -f4)
            created=$(grep '"created"' "$rp/metadata.json" | cut -d'"' -f4)
            echo "  $id ($name) - $created"
        else
            echo "  $id"
        fi
    done
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export DECLUTTER_DATA_DIR UNDO_LOG_DIR
export -f init_undo_system cleanup_old_transactions
export -f start_transaction commit_transaction rollback_transaction
export -f log_action logged_move logged_delete
export -f list_transactions show_transaction undo_transaction undo_last
export -f create_restore_point list_restore_points
