#!/usr/bin/env bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# GitOps Auto-Sync Script with Enhanced Error Handling
# Purpose: Automatically sync Git repository, decrypt secrets, and restart Docker stacks
# This script is designed to continue working even when individual operations fail

# === Configuration ===
GITOPS_ROOT="${GITOPS_ROOT:-/opt/gitops}"
REPO_PATH="${REPO_PATH:-$GITOPS_ROOT/iac-catalog}"
REPO_URL="${REPO_URL:-https://github.com/codefuturist/iac-catalog.git}"
REPO_BRANCH="${REPO_BRANCH:-develop}"
AGE_KEY_FILE="${AGE_KEY_FILE:-$GITOPS_ROOT/.age.key}"
LOG_FILE="${LOG_FILE:-/var/log/gitops-sync.log}"
LOCK_FILE="${LOCK_FILE:-/tmp/gitops-sync.lock}"
LOCK_TIMEOUT="${LOCK_TIMEOUT:-600}"
MAX_RETRIES=3
RETRY_DELAY=5

# === Logging Functions ===
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')][INFO] $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')][WARN] $*" | tee -a "$LOG_FILE" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')][ERROR] $*" | tee -a "$LOG_FILE" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')][DEBUG] $*" | tee -a "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')][DEBUG] $*" >> "$LOG_FILE"
    fi
}

# === Lock Management ===
acquire_lock() {
    local timeout=$LOCK_TIMEOUT
    local elapsed=0
    
    while [[ -f "$LOCK_FILE" ]]; do
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Failed to acquire lock after ${timeout}s"
            # Instead of exiting, try to force-remove stale lock
            local lock_age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
            if [[ $lock_age -gt $((timeout * 2)) ]]; then
                log_warn "Removing stale lock file (age: ${lock_age}s)"
                rm -f "$LOCK_FILE" || true
                break
            else
                return 1
            fi
        fi
        log_debug "Waiting for lock... (${elapsed}s/${timeout}s)"
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    echo $$ > "$LOCK_FILE" || {
        log_error "Failed to create lock file"
        return 1
    }
    log_debug "Lock acquired"
    return 0
}

release_lock() {
    rm -f "$LOCK_FILE" || log_warn "Failed to remove lock file"
    log_debug "Lock released"
}

# === Cleanup Handler ===
cleanup() {
    local exit_code=$?
    log_debug "Cleanup triggered (exit code: $exit_code)"
    release_lock
    exit $exit_code
}

trap cleanup EXIT INT TERM

# === Git Operations ===
sync_repo() {
    log_info "Starting repository sync..."
    
    # Check if repo directory exists
    if [[ ! -d "$REPO_PATH" ]]; then
        log_info "Repository not found, cloning..."
        if ! git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_PATH" 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Failed to clone repository"
            return 1
        fi
        log_info "Repository cloned successfully"
        return 0
    fi
    
    # Change to repo directory
    cd "$REPO_PATH" || {
        log_error "Failed to change to repository directory"
        return 1
    }
    
    # Store current commit for comparison
    local current_commit
    current_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    
    # Fetch with retries
    local attempt=1
    while [[ $attempt -le $MAX_RETRIES ]]; do
        log_debug "Fetching repository (attempt $attempt/$MAX_RETRIES)..."
        
        if git fetch origin 2>&1 | tee -a "$LOG_FILE"; then
            log_debug "Fetch successful"
            break
        else
            log_warn "Fetch failed (attempt $attempt/$MAX_RETRIES)"
            if [[ $attempt -eq $MAX_RETRIES ]]; then
                log_error "Failed to fetch after $MAX_RETRIES attempts"
                # Continue anyway - we can work with cached state
                return 2  # Non-fatal error code
            fi
            sleep $((RETRY_DELAY * attempt))
            attempt=$((attempt + 1))
        fi
    done
    
    # Check if we're behind
    local remote_commit
    remote_commit=$(git rev-parse "origin/$REPO_BRANCH" 2>/dev/null || echo "unknown")
    
    if [[ "$current_commit" == "$remote_commit" ]]; then
        log_info "Repository is up to date (commit: ${current_commit:0:8})"
        return 0
    fi
    
    log_info "New commits detected, updating..."
    log_debug "Current: ${current_commit:0:8}, Remote: ${remote_commit:0:8}"
    
    # Reset to remote branch
    if git reset --hard "origin/$REPO_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Repository updated successfully to ${remote_commit:0:8}"
        return 0
    else
        log_error "Failed to reset to remote branch"
        # Try to recover by cleaning and retrying
        log_warn "Attempting recovery..."
        git clean -fd 2>&1 | tee -a "$LOG_FILE" || true
        if git reset --hard "origin/$REPO_BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Repository recovered and updated"
            return 0
        else
            log_error "Failed to recover repository"
            return 1
        fi
    fi
}

# === Secret Decryption ===
decrypt_all_secrets() {
    log_info "Starting secret decryption..."
    
    # Check if AGE key exists
    if [[ ! -f "$AGE_KEY_FILE" ]]; then
        log_error "Age key not found at $AGE_KEY_FILE"
        log_warn "Skipping secret decryption (key missing)"
        return 2  # Non-fatal - continue with other operations
    fi
    
    # Check AGE key permissions
    local perms
    perms=$(stat -c %a "$AGE_KEY_FILE" 2>/dev/null || stat -f %OLp "$AGE_KEY_FILE" 2>/dev/null)
    if [[ "$perms" != "600" ]]; then
        log_warn "Age key has incorrect permissions ($perms), fixing..."
        chmod 600 "$AGE_KEY_FILE" || log_error "Failed to fix permissions"
    fi
    
    # Set SOPS environment
    export SOPS_AGE_KEY_FILE="$AGE_KEY_FILE"
    
    # Find all encrypted files
    local encrypted_files
    encrypted_files=$(find "$REPO_PATH/deployments" -type f -name "*.sops" 2>/dev/null || echo "")
    
    if [[ -z "$encrypted_files" ]]; then
        log_info "No encrypted files found"
        return 0
    fi
    
    local total=0
    local success=0
    local failed=0
    
    while IFS= read -r encrypted_file; do
        [[ -z "$encrypted_file" ]] && continue
        total=$((total + 1))
        
        log_debug "Decrypting: $encrypted_file"
        
        # Determine output file
        local output_file="${encrypted_file%.sops}"
        
        # Try to decrypt - don't exit on failure
        if sops --decrypt "$encrypted_file" > "$output_file" 2>>"$LOG_FILE"; then
            log_debug "Successfully decrypted: $encrypted_file"
            success=$((success + 1))
            
            # Set appropriate permissions on decrypted file
            chmod 600 "$output_file" 2>/dev/null || true
        else
            log_warn "Failed to decrypt $encrypted_file, continuing..."
            failed=$((failed + 1))
            # Don't fail the entire operation
        fi
    done <<< "$encrypted_files"
    
    log_info "Decryption summary: $success succeeded, $failed failed"
    
    # Return success if at least some decryptions worked, or if there were none
    if [[ $total -eq 0 ]] || [[ $success -gt 0 ]]; then
        return 0
    else
        return 2  # Non-fatal error
    fi
}

# === Stack Management ===
restart_all_stacks() {
    log_info "Checking for stacks to restart..."
    
    # Find all docker-compose.yml files
    local compose_files
    compose_files=$(find "$REPO_PATH/deployments/production" -name "docker-compose.yml" -type f 2>/dev/null || echo "")
    
    if [[ -z "$compose_files" ]]; then
        log_info "No compose files found"
        return 0
    fi
    
    local total=0
    local success=0
    local failed=0
    
    while IFS= read -r compose_file; do
        [[ -z "$compose_file" ]] && continue
        
        local stack_dir
        stack_dir=$(dirname "$compose_file")
        local stack_name
        stack_name=$(basename "$stack_dir")
        
        total=$((total + 1))
        
        log_info "Processing stack: $stack_name"
        
        # Change to stack directory
        if ! cd "$stack_dir"; then
            log_error "Failed to change to stack directory: $stack_dir"
            failed=$((failed + 1))
            continue
        fi
        
        # Check if stack is deployed
        if ! docker stack ls 2>/dev/null | grep -q "^${stack_name} "; then
            log_debug "Stack $stack_name not deployed, skipping"
            continue
        fi
        
        # Try to update the stack - don't exit on failure
        log_info "Updating stack: $stack_name"
        if docker stack deploy -c docker-compose.yml "$stack_name" 2>&1 | tee -a "$LOG_FILE"; then
            log_info "Successfully updated stack: $stack_name"
            success=$((success + 1))
        else
            log_error "Failed to update stack: $stack_name"
            failed=$((failed + 1))
            # Continue with other stacks
        fi
    done <<< "$compose_files"
    
    log_info "Stack update summary: $success succeeded, $failed failed"
    
    # Return success if at least some restarts worked
    return 0
}

# === DNS Sync ===
sync_dns_to_pihole() {
    log_info "Starting DNS zone sync to Pi-hole..."
    
    local zones_dir="$REPO_PATH/environments/global/configurations/dns-zones"
    local pihole_toml="/etc/pihole/pihole.toml"
    local sync_script="$GITOPS_ROOT/sync-dns-zones.py"
    
    # Check if zones directory exists
    if [[ ! -d "$zones_dir" ]]; then
        log_warn "DNS zones directory not found: $zones_dir, skipping DNS sync"
        return 2  # Non-fatal error
    fi
    
    # Check if sync script exists
    if [[ ! -f "$sync_script" ]]; then
        log_error "DNS sync script not found: $sync_script"
        return 1
    fi
    
    # Check for zone files
    local zone_count
    zone_count=$(find "$zones_dir" -name "*.zone" -type f 2>/dev/null | wc -l)
    
    if [[ $zone_count -eq 0 ]]; then
        log_warn "No zone files found in $zones_dir, skipping DNS sync"
        return 2  # Non-fatal error
    fi
    
    log_info "Found $zone_count zone file(s) to process"
    
    # Backup current pihole.toml
    if [[ -f "$pihole_toml" ]]; then
        local backup_file="${pihole_toml}.backup-$(date +%Y%m%d-%H%M%S)"
        if sudo cp "$pihole_toml" "$backup_file" 2>&1 | tee -a "$LOG_FILE"; then
            log_debug "Backed up pihole.toml to $backup_file"
        else
            log_warn "Failed to backup pihole.toml"
        fi
    fi
    
    # Run zone file parser and updater
    log_info "Parsing zone files and updating Pi-hole configuration..."
    if sudo python3 "$sync_script" "$zones_dir" "$pihole_toml" 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Successfully updated pihole.toml from zone files"
    else
        log_error "Failed to update pihole.toml from zone files"
        return 1
    fi
    
    # Restart Pi-hole FTL to apply changes
    log_info "Restarting Pi-hole FTL to apply DNS changes..."
    if sudo systemctl restart pihole-FTL 2>&1 | tee -a "$LOG_FILE"; then
        log_info "Pi-hole FTL restarted successfully"
        return 0
    else
        log_error "Failed to restart Pi-hole FTL"
        return 1
    fi
}

# === Main Execution ===
main() {
    log_info "=== GitOps Sync Started ==="
    log_info "Repository: $REPO_URL (branch: $REPO_BRANCH)"
    
    # Acquire lock with better error handling
    if ! acquire_lock; then
        log_error "Could not acquire lock, another sync may be running"
        exit 1
    fi
    
    # Track overall success
    local sync_status=0
    local decrypt_status=0
    local restart_status=0
    local dns_status=0
    
    # Sync repository (continue even if this fails partially)
    if sync_repo; then
        log_info "Repository sync completed"
    else
        sync_status=$?
        if [[ $sync_status -eq 2 ]]; then
            log_warn "Repository sync had non-fatal errors, continuing..."
        else
            log_error "Repository sync failed critically"
            # Continue anyway - maybe we can work with cached state
        fi
    fi
    
    # Decrypt secrets (continue even if this fails)
    if decrypt_all_secrets; then
        log_info "Secret decryption completed"
    else
        decrypt_status=$?
        log_warn "Secret decryption had errors (code: $decrypt_status), continuing..."
    fi
    
    # Sync DNS to Pi-hole (always run after repo sync, even if no changes)
    if sync_dns_to_pihole; then
        log_info "DNS sync completed"
    else
        dns_status=$?
        if [[ $dns_status -eq 2 ]]; then
            log_warn "DNS sync skipped (file not found)"
        else
            log_warn "DNS sync had errors (code: $dns_status)"
        fi
    fi
    
    # Only restart stacks if repo changed
    if [[ $sync_status -eq 0 ]]; then
        if restart_all_stacks; then
            log_info "Stack updates completed"
        else
            restart_status=$?
            log_warn "Stack updates had errors (code: $restart_status)"
        fi
    else
        log_info "Skipping stack restarts (no repository changes or sync failed)"
    fi
    
    log_info "=== GitOps Sync Complete ==="
    
    # Determine exit status
    if [[ $sync_status -eq 0 ]] && [[ $decrypt_status -eq 0 ]] && [[ $restart_status -eq 0 ]]; then
        log_info "All operations completed successfully"
        return 0
    elif [[ $sync_status -le 2 ]] && [[ $decrypt_status -le 2 ]]; then
        log_warn "Completed with non-critical warnings"
        return 0  # Success despite warnings
    else
        log_error "Completed with errors"
        return 0  # Still return 0 to allow timer to continue
    fi
}

# Execute main function
main "$@"
