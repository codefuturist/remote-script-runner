#!/usr/bin/env bash
#
# Declutter - Journal System
# Action logging for undo capability
#

# Prevent multiple inclusion
[[ -n "${_DECLUTTER_JOURNAL_LOADED:-}" ]] && return 0
readonly _DECLUTTER_JOURNAL_LOADED=1

# =============================================================================
# Dependencies
# =============================================================================

# Module directory
_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/utils.sh
source "$_MODULE_DIR/../core/utils.sh"
# shellcheck source=../core/logger.sh
source "$_MODULE_DIR/../core/logger.sh"
# shellcheck source=../core/config.sh
source "$_MODULE_DIR/../core/config.sh"

# =============================================================================
# Journal Configuration
# =============================================================================

JOURNAL_DIR=""
JOURNAL_SESSION=""
JOURNAL_FILE=""

# Maximum journal entries to keep
JOURNAL_MAX_ENTRIES="${JOURNAL_MAX_ENTRIES:-1000}"

# Maximum age of journal entries (days)
JOURNAL_MAX_AGE="${JOURNAL_MAX_AGE:-30}"

# =============================================================================
# Journal Initialization
# =============================================================================

# Initialize journal for current session
journal_init() {
    JOURNAL_DIR="$(get_journal_dir)"
    JOURNAL_SESSION="$(get_timestamp)"
    JOURNAL_FILE="${JOURNAL_DIR}/session_$(date +%Y%m%d_%H%M%S).json"

    mkdir -p "$JOURNAL_DIR"

    # Create session file with header
    cat > "$JOURNAL_FILE" << EOF
{
  "session": "$JOURNAL_SESSION",
  "started": "$(get_timestamp)",
  "user": "$USER",
  "hostname": "$(hostname)",
  "pwd": "$PWD",
  "entries": [
EOF

    log_debug "Journal initialized: $JOURNAL_FILE"
}

# Close journal session
journal_close() {
    if [[ -f "$JOURNAL_FILE" ]]; then
        # Remove trailing comma and close JSON
        sed -i.bak '$ s/,$//' "$JOURNAL_FILE" 2>/dev/null || \
        sed -i '' '$ s/,$//' "$JOURNAL_FILE" 2>/dev/null
        rm -f "${JOURNAL_FILE}.bak"

        cat >> "$JOURNAL_FILE" << EOF

  ],
  "ended": "$(get_timestamp)"
}
EOF
        log_debug "Journal closed: $JOURNAL_FILE"
    fi
}

# =============================================================================
# Journal Entries
# =============================================================================

# Record an action in the journal
journal_record() {
    local action="$1"      # delete, move, rename, compress
    local source="$2"      # Source path
    local destination="${3:-}"  # Destination (for move/rename)
    local metadata="${4:-{}}"   # Additional metadata JSON

    if ! is_journal_enabled; then
        return 0
    fi

    if [[ -z "$JOURNAL_FILE" ]]; then
        journal_init
    fi

    local entry_id
    entry_id="$(generate_uuid)"

    local size=""
    local hash=""
    local permissions=""

    if [[ -f "$source" ]]; then
        size="$(get_file_size "$source")"
        hash="$(get_file_hash "$source" md5 2>/dev/null || echo "")"
        permissions="$(stat -f%Mp%Lp "$source" 2>/dev/null || stat -c%a "$source" 2>/dev/null || echo "")"
    elif [[ -d "$source" ]]; then
        size="$(du -sk "$source" 2>/dev/null | cut -f1 | awk '{print $1 * 1024}')"
    fi

    # Determine if reversible
    local reversible="true"
    case "$action" in
        delete)
            if is_trash_enabled && command -v trash &>/dev/null; then
                reversible="true"
            else
                reversible="false"
            fi
            ;;
        move|rename)
            reversible="true"
            ;;
        compress)
            reversible="true"  # Keep original path in metadata
            ;;
    esac

    # Write entry
    cat >> "$JOURNAL_FILE" << EOF
    {
      "id": "$entry_id",
      "timestamp": "$(get_timestamp)",
      "action": "$action",
      "source": "$(json_escape "$source")",
      "destination": "$(json_escape "$destination")",
      "metadata": {
        "size": $size,
        "hash": "$hash",
        "permissions": "$permissions"
      },
      "reversible": $reversible
    },
EOF

    log_trace "Journal entry: $action $source"
    echo "$entry_id"
}

# =============================================================================
# Journal Queries
# =============================================================================

# List all journal sessions
journal_list_sessions() {
    local limit="${1:-20}"

    if [[ ! -d "$JOURNAL_DIR" ]]; then
        echo "[]"
        return
    fi

    echo "["
    local first=true
    find "$JOURNAL_DIR" -name "session_*.json" -type f | \
        sort -r | head -n "$limit" | while read -r file; do

        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi

        local session started entries
        session="$(jq -r '.session // ""' "$file" 2>/dev/null)"
        started="$(jq -r '.started // ""' "$file" 2>/dev/null)"
        entries="$(jq -r '.entries | length' "$file" 2>/dev/null || echo "0")"

        printf '  {"file": "%s", "session": "%s", "started": "%s", "entries": %s}' \
            "$(basename "$file")" "$session" "$started" "$entries"
    done
    echo ""
    echo "]"
}

# Get entries from a session
journal_get_entries() {
    local session_file="$1"
    local limit="${2:-50}"

    if [[ ! -f "$session_file" ]]; then
        # Try to find by name
        session_file="${JOURNAL_DIR}/${session_file}"
    fi

    if [[ ! -f "$session_file" ]]; then
        echo "[]"
        return 1
    fi

    jq -r ".entries | reverse | .[0:$limit]" "$session_file" 2>/dev/null || echo "[]"
}

# Get single entry by ID
journal_get_entry() {
    local entry_id="$1"

    # Search all session files for the entry
    find "$JOURNAL_DIR" -name "session_*.json" -type f | while read -r file; do
        local entry
        entry="$(jq -r ".entries[] | select(.id == \"$entry_id\")" "$file" 2>/dev/null)"
        if [[ -n "$entry" ]]; then
            echo "$entry"
            return 0
        fi
    done
}

# Get recent entries across all sessions
journal_recent() {
    local limit="${1:-20}"
    local action_filter="${2:-}"

    local all_entries="["
    local first=true

    find "$JOURNAL_DIR" -name "session_*.json" -type f | \
        sort -r | head -5 | while read -r file; do

        local filter=".entries[]"
        if [[ -n "$action_filter" ]]; then
            filter=".entries[] | select(.action == \"$action_filter\")"
        fi

        jq -r "$filter" "$file" 2>/dev/null
    done | jq -s "sort_by(.timestamp) | reverse | .[0:$limit]" 2>/dev/null || echo "[]"
}

# =============================================================================
# Undo Operations
# =============================================================================

# Undo a single entry
journal_undo_entry() {
    local entry_id="$1"

    local entry
    entry="$(journal_get_entry "$entry_id")"

    if [[ -z "$entry" || "$entry" == "null" ]]; then
        log_error "Entry not found: $entry_id"
        return 1
    fi

    local action source destination reversible
    action="$(echo "$entry" | jq -r '.action')"
    source="$(echo "$entry" | jq -r '.source')"
    destination="$(echo "$entry" | jq -r '.destination')"
    reversible="$(echo "$entry" | jq -r '.reversible')"

    if [[ "$reversible" != "true" ]]; then
        log_error "Entry is not reversible: $entry_id"
        return 1
    fi

    log_info "Undoing: $action $source"

    case "$action" in
        delete)
            # Restore from trash
            if [[ -n "$destination" ]] && [[ -e "$destination" ]]; then
                mv "$destination" "$source"
                log_success "Restored: $source"
            else
                log_error "Cannot restore: file not found in trash"
                return 1
            fi
            ;;

        move)
            # Move back
            if [[ -e "$destination" ]]; then
                mv "$destination" "$source"
                log_success "Moved back: $destination → $source"
            else
                log_error "Cannot undo move: destination not found"
                return 1
            fi
            ;;

        rename)
            # Rename back
            if [[ -e "$destination" ]]; then
                mv "$destination" "$source"
                log_success "Renamed back: $destination → $source"
            else
                log_error "Cannot undo rename: file not found"
                return 1
            fi
            ;;

        compress)
            # Decompress
            log_warn "Undo compress not yet implemented"
            return 1
            ;;

        *)
            log_error "Unknown action type: $action"
            return 1
            ;;
    esac

    return 0
}

# Undo last N entries
journal_undo_last() {
    local count="${1:-1}"

    local entries
    entries="$(journal_recent "$count")"

    echo "$entries" | jq -r '.[].id' 2>/dev/null | while read -r entry_id; do
        journal_undo_entry "$entry_id"
    done
}

# Undo entire session
journal_undo_session() {
    local session_file="$1"

    if [[ ! -f "$session_file" ]]; then
        session_file="${JOURNAL_DIR}/${session_file}"
    fi

    if [[ ! -f "$session_file" ]]; then
        log_error "Session file not found: $session_file"
        return 1
    fi

    log_step "Undoing session: $(basename "$session_file")"

    # Get entries in reverse order (undo last first)
    jq -r '.entries | reverse | .[].id' "$session_file" 2>/dev/null | while read -r entry_id; do
        journal_undo_entry "$entry_id"
    done
}

# =============================================================================
# Journal Maintenance
# =============================================================================

# Clean old journal files
journal_cleanup() {
    local max_age="${1:-$JOURNAL_MAX_AGE}"

    if [[ ! -d "$JOURNAL_DIR" ]]; then
        return 0
    fi

    log_info "Cleaning journal entries older than $max_age days..."

    local count=0
    find "$JOURNAL_DIR" -name "session_*.json" -type f -mtime "+$max_age" | while read -r file; do
        rm -f "$file"
        ((count++))
    done

    log_success "Removed $count old journal files"
}

# Get journal statistics
journal_stats() {
    if [[ ! -d "$JOURNAL_DIR" ]]; then
        echo "No journal directory found"
        return
    fi

    local file_count total_entries
    file_count="$(find "$JOURNAL_DIR" -name "session_*.json" -type f | wc -l | tr -d ' ')"
    total_entries="$(find "$JOURNAL_DIR" -name "session_*.json" -type f -exec jq '.entries | length' {} \; 2>/dev/null | awk '{sum+=$1} END {print sum}')"

    print_section "Journal Statistics"
    print_kv "Directory" "$JOURNAL_DIR"
    print_kv "Session files" "$file_count"
    print_kv "Total entries" "${total_entries:-0}"
    print_kv "Disk usage" "$(du -sh "$JOURNAL_DIR" 2>/dev/null | cut -f1)"
}

# =============================================================================
# History Display
# =============================================================================

# Display formatted history
journal_show_history() {
    local limit="${1:-20}"

    print_section "Recent Actions"

    local entries
    entries="$(journal_recent "$limit")"

    if [[ "$entries" == "[]" ]] || [[ -z "$entries" ]]; then
        echo "  No history found"
        return
    fi

    echo "$entries" | jq -r '.[] | "\(.timestamp) | \(.action) | \(.source)"' 2>/dev/null | \
    while IFS='|' read -r timestamp action source; do
        timestamp="$(echo "$timestamp" | tr -d ' ')"
        action="$(echo "$action" | tr -d ' ')"
        source="$(echo "$source" | tr -d ' ')"

        local color
        case "$action" in
            delete) color="$LOG_RED" ;;
            move)   color="$LOG_BLUE" ;;
            rename) color="$LOG_CYAN" ;;
            *)      color="$LOG_WHITE" ;;
        esac

        printf "  ${LOG_DIM}%s${LOG_RESET} ${color}%-8s${LOG_RESET} %s\n" \
            "${timestamp%T*}" "$action" "$(basename "$source")"
    done
}
