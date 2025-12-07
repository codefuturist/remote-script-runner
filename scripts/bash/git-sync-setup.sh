#!/bin/bash

# Git-Sync Management Script
# Setup and manage automated git repository synchronization
# Example: /bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-sync-setup.sh)" -- --install
# Or: ./git-sync-setup.sh --add-repo /opt/repositories/my-repo:main:15

set -euo pipefail

# Script metadata
SCRIPT_NAME="Git-Sync Setup"
SCRIPT_VERSION="1.0.0"
SCRIPT_DESC="Setup and manage automated git repository synchronization"

# Default values
ACTION=""
REPO_PATH=""
REPO_BRANCH="main"
REPO_INTERVAL="15"
REPO_URL=""
CONFIG_FILE="/etc/git-sync.conf"
REPOSITORIES_DIR="/opt/repositories"
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_proxmox"
DRY_RUN=false
VERBOSE=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[DEBUG]${NC} $*"
    fi
}

# Function to display usage
usage() {
    cat << EOF
${BLUE}${SCRIPT_NAME}${NC} v${SCRIPT_VERSION}
${SCRIPT_DESC}

${YELLOW}Usage:${NC}
    $0 [ACTION] [OPTIONS]

${YELLOW}Actions:${NC}
    --install               Install git-sync service (tools, config, cron)
    --uninstall            Uninstall git-sync service
    --add-repo             Add repository to sync
    --remove-repo          Remove repository from sync
    --list                 List configured repositories
    --status               Show sync status for all repos
    --test                 Test sync for all repositories
    --update               Update cron jobs from config
    --deploy-to HOST       Deploy git-sync to another host

${YELLOW}Options:${NC}
    --repo-url URL         Git repository URL (for --add-repo)
    --repo-path PATH       Repository path (default: auto-generate in $REPOSITORIES_DIR)
    --branch BRANCH        Git branch to sync (default: main)
    --interval MINUTES     Sync interval in minutes (default: 15)
    --ssh-key PATH         SSH key path (default: $SSH_KEY_PATH)
    --dry-run              Show what would be done without doing it
    --verbose              Enable verbose output
    -h, --help             Show this help message

${YELLOW}Examples:${NC}
    # Install git-sync service
    $0 --install

    # Add a new repository
    $0 --add-repo --repo-url git@github.com:user/repo.git

    # Add repo with custom settings
    $0 --add-repo --repo-url git@github.com:user/repo.git \\
        --branch develop --interval 30

    # Remove a repository
    $0 --remove-repo --repo-path /opt/repositories/my-repo

    # List all configured repos
    $0 --list

    # Check sync status
    $0 --status

    # Test all syncs
    $0 --test

    # Deploy to another host
    $0 --deploy-to root@192.168.2.50

${YELLOW}Remote Execution:${NC}
    # Install via curl
    curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-sync-setup.sh | bash -s -- --install

    # Add repo via curl
    curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-sync-setup.sh | bash -s -- \\
        --add-repo --repo-url git@github.com:user/repo.git

EOF
    exit 0
}

# ============================================================================
# Core Functions
# ============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
        exit 1
    fi
}

install_git_sync() {
    log "Installing git-sync service..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Would install git-sync tools"
        return 0
    fi
    
    # Create repositories directory
    verbose "Creating repositories directory: $REPOSITORIES_DIR"
    mkdir -p "$REPOSITORIES_DIR"
    
    # Install git-sync utility
    log "Installing /usr/local/bin/git-sync..."
    cat > /usr/local/bin/git-sync << 'EOFSCRIPT'
#!/bin/bash
# git-sync - Universal Git repository auto-sync service
# Usage: git-sync <repo_path> [branch]

set -euo pipefail

REPO_PATH="${1:-}"
BRANCH="${2:-main}"
LOG_DIR="/var/log/git-sync"
SSH_KEY="${HOME}/.ssh/id_ed25519_proxmox"

if [ -z "$REPO_PATH" ]; then
    echo "Usage: git-sync <repo_path> [branch]"
    exit 1
fi

if [ ! -d "$REPO_PATH/.git" ]; then
    echo "Error: $REPO_PATH is not a git repository"
    exit 1
fi

mkdir -p "$LOG_DIR"
REPO_NAME=$(basename "$REPO_PATH")
LOG_FILE="$LOG_DIR/${REPO_NAME}.log"

cd "$REPO_PATH" || exit 1
export GIT_SSH_COMMAND="ssh -i $SSH_KEY -o StrictHostKeyChecking=no"

log() {
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $1" >> "$LOG_FILE"
}

log "Checking for updates in $REPO_PATH (branch: $BRANCH)..."

if ! git fetch origin "$BRANCH" 2>&1 >> "$LOG_FILE"; then
    log "ERROR: Failed to fetch from origin"
    exit 1
fi

LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse "origin/$BRANCH")

if [ "$LOCAL" != "$REMOTE" ]; then
    log "Updates found, pulling changes..."
    if git pull origin "$BRANCH" 2>&1 >> "$LOG_FILE"; then
        chmod -R 755 "$REPO_PATH" 2>/dev/null || true
        log "Pull completed successfully"
    else
        log "ERROR: Failed to pull changes"
        exit 1
    fi
else
    log "Already up-to-date"
fi
EOFSCRIPT
    
    chmod +x /usr/local/bin/git-sync
    
    # Install git-sync-manager
    log "Installing /usr/local/bin/git-sync-manager..."
    cat > /usr/local/bin/git-sync-manager << 'EOFSCRIPT'
#!/bin/bash
# git-sync-manager - Manages cron jobs for multiple git repositories
# Usage: git-sync-manager [update|list|test]

set -euo pipefail

CONFIG_FILE="/etc/git-sync.conf"
CRON_MARKER="# git-sync-manager"

update_cron() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Configuration file $CONFIG_FILE not found"
        exit 1
    fi

    crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | crontab - 2>/dev/null || true

    local temp_cron=$(mktemp)
    crontab -l 2>/dev/null > "$temp_cron" || true

    while IFS=: read -r repo_path branch interval; do
        [[ -z "$repo_path" || "$repo_path" =~ ^[[:space:]]*# ]] && continue
        
        repo_path=$(echo "$repo_path" | xargs)
        branch=$(echo "$branch" | xargs)
        interval=$(echo "$interval" | xargs)
        
        branch=${branch:-main}
        interval=${interval:-15}
        
        echo "*/$interval * * * * /usr/local/bin/git-sync \"$repo_path\" \"$branch\" >/dev/null 2>&1 $CRON_MARKER" >> "$temp_cron"
        echo "Added sync job: $repo_path ($branch) every $interval minutes"
    done < "$CONFIG_FILE"

    crontab "$temp_cron"
    rm "$temp_cron"
    echo "Cron jobs updated successfully"
}

list_repos() {
    echo "Configured repositories:"
    echo "------------------------"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "No configuration file found"
        return
    fi
    
    while IFS=: read -r repo_path branch interval; do
        [[ -z "$repo_path" || "$repo_path" =~ ^[[:space:]]*# ]] && continue
        repo_path=$(echo "$repo_path" | xargs)
        branch=$(echo "$branch" | xargs)
        interval=$(echo "$interval" | xargs)
        echo "  - $repo_path (branch: ${branch:-main}, interval: ${interval:-15}min)"
    done < "$CONFIG_FILE"
    
    echo ""
    echo "Active cron jobs:"
    echo "----------------"
    crontab -l 2>/dev/null | grep "$CRON_MARKER" || echo "  None"
}

test_sync() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Configuration file $CONFIG_FILE not found"
        exit 1
    fi
    
    echo "Testing git-sync for all configured repositories..."
    echo ""
    
    while IFS=: read -r repo_path branch interval; do
        [[ -z "$repo_path" || "$repo_path" =~ ^[[:space:]]*# ]] && continue
        repo_path=$(echo "$repo_path" | xargs)
        branch=$(echo "$branch" | xargs)
        
        echo "Testing: $repo_path (branch: ${branch:-main})"
        if /usr/local/bin/git-sync "$repo_path" "${branch:-main}"; then
            echo "  ✓ Success"
        else
            echo "  ✗ Failed"
        fi
        echo ""
    done < "$CONFIG_FILE"
}

case "${1:-}" in
    update) update_cron ;;
    list) list_repos ;;
    test) test_sync ;;
    *)
        echo "Usage: git-sync-manager [update|list|test]"
        echo ""
        echo "Commands:"
        echo "  update  - Update cron jobs from $CONFIG_FILE"
        echo "  list    - List configured repositories and active cron jobs"
        echo "  test    - Test sync for all configured repositories"
        exit 1
        ;;
esac
EOFSCRIPT
    
    chmod +x /usr/local/bin/git-sync-manager
    
    # Install git-sync-branch helper
    log "Installing /usr/local/bin/git-sync-branch..."
    cat > /usr/local/bin/git-sync-branch << 'EOFSCRIPT'
#!/bin/bash
# git-sync-branch - Helper to change branch for a synced repository
# Usage: git-sync-branch <repo_path> <new_branch>

set -euo pipefail

REPO_PATH="${1:-}"
NEW_BRANCH="${2:-}"

if [ -z "$REPO_PATH" ] || [ -z "$NEW_BRANCH" ]; then
    echo "Usage: git-sync-branch <repo_path> <new_branch>"
    echo ""
    echo "Example: git-sync-branch /opt/repositories/scripts develop"
    exit 1
fi

if [ ! -d "$REPO_PATH/.git" ]; then
    echo "Error: $REPO_PATH is not a git repository"
    exit 1
fi

echo "Switching $REPO_PATH to branch: $NEW_BRANCH"
cd "$REPO_PATH"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Stashing local changes..."
    git stash
fi

git fetch origin "$NEW_BRANCH"
git checkout "$NEW_BRANCH"
git pull origin "$NEW_BRANCH"

echo "✓ Successfully switched to $NEW_BRANCH"
echo ""
echo "To update git-sync configuration:"
echo "  1. Edit /etc/git-sync.conf"
echo "  2. Change the branch for $REPO_PATH"
echo "  3. Run: git-sync-manager update"
EOFSCRIPT
    
    chmod +x /usr/local/bin/git-sync-branch
    
    # Create initial config file
    if [ ! -f "$CONFIG_FILE" ]; then
        log "Creating configuration file: $CONFIG_FILE"
        cat > "$CONFIG_FILE" << 'EOF'
# git-sync configuration file
# Format: <repo_path>:<branch>:<interval_minutes>
# Lines starting with # are ignored

# Example configurations:
# /opt/repositories/scripts:main:15
# /opt/repositories/configs:develop:30
# /opt/repositories/infrastructure:production:60

EOF
        chmod 644 "$CONFIG_FILE"
    fi
    
    # Create log directory
    mkdir -p /var/log/git-sync
    
    success "Git-sync service installed successfully!"
    log ""
    log "Next steps:"
    log "  1. Add repositories: git-sync-setup.sh --add-repo --repo-url <url>"
    log "  2. Configure SSH key if needed (default: $SSH_KEY_PATH)"
    log "  3. Update cron: git-sync-manager update"
}

uninstall_git_sync() {
    log "Uninstalling git-sync service..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Would uninstall git-sync tools"
        return 0
    fi
    
    # Remove cron jobs
    crontab -l 2>/dev/null | grep -v "# git-sync-manager" | crontab - 2>/dev/null || true
    
    # Remove binaries
    rm -f /usr/local/bin/git-sync
    rm -f /usr/local/bin/git-sync-manager
    rm -f /usr/local/bin/git-sync-branch
    
    # Ask about config and repos
    warn "Configuration file $CONFIG_FILE preserved"
    warn "Repositories in $REPOSITORIES_DIR preserved"
    warn "Logs in /var/log/git-sync preserved"
    
    success "Git-sync service uninstalled"
}

add_repository() {
    if [ -z "$REPO_URL" ]; then
        error "Repository URL required (--repo-url)"
        exit 1
    fi
    
    # Extract repo name from URL
    REPO_NAME=$(basename "$REPO_URL" .git)
    
    # Set default path if not specified
    if [ -z "$REPO_PATH" ]; then
        REPO_PATH="$REPOSITORIES_DIR/$REPO_NAME"
    fi
    
    log "Adding repository: $REPO_NAME"
    verbose "URL: $REPO_URL"
    verbose "Path: $REPO_PATH"
    verbose "Branch: $REPO_BRANCH"
    verbose "Interval: $REPO_INTERVAL minutes"
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Would clone $REPO_URL to $REPO_PATH"
        log "[DRY-RUN] Would add to $CONFIG_FILE"
        return 0
    fi
    
    # Check if repo already exists
    if [ -d "$REPO_PATH" ]; then
        warn "Repository already exists at $REPO_PATH"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        # Clone repository
        log "Cloning repository..."
        mkdir -p "$(dirname "$REPO_PATH")"
        
        if [ -f "$SSH_KEY_PATH" ]; then
            git clone "$REPO_URL" "$REPO_PATH" -b "$REPO_BRANCH" -c "core.sshCommand=ssh -i $SSH_KEY_PATH"
            cd "$REPO_PATH"
            git config core.sshCommand "ssh -i $SSH_KEY_PATH"
        else
            warn "SSH key not found at $SSH_KEY_PATH, using default authentication"
            git clone "$REPO_URL" "$REPO_PATH" -b "$REPO_BRANCH"
        fi
        
        chmod -R 755 "$REPO_PATH"
    fi
    
    # Add to config file
    log "Adding to configuration..."
    
    # Check if already in config
    if grep -q "^$REPO_PATH:" "$CONFIG_FILE" 2>/dev/null; then
        warn "Repository already configured, updating entry..."
        sed -i.bak "/^$(echo "$REPO_PATH" | sed 's/\//\\\//g'):/d" "$CONFIG_FILE"
    fi
    
    echo "" >> "$CONFIG_FILE"
    echo "# $REPO_NAME" >> "$CONFIG_FILE"
    echo "$REPO_PATH:$REPO_BRANCH:$REPO_INTERVAL" >> "$CONFIG_FILE"
    
    # Update cron
    log "Updating cron jobs..."
    git-sync-manager update
    
    success "Repository added successfully!"
    log ""
    log "Test the sync: git-sync-manager test"
}

remove_repository() {
    if [ -z "$REPO_PATH" ]; then
        error "Repository path required (--repo-path)"
        exit 1
    fi
    
    log "Removing repository: $REPO_PATH"
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Would remove from $CONFIG_FILE"
        return 0
    fi
    
    # Remove from config
    if grep -q "^$REPO_PATH:" "$CONFIG_FILE" 2>/dev/null; then
        sed -i.bak "/^$(echo "$REPO_PATH" | sed 's/\//\\\//g'):/d" "$CONFIG_FILE"
        success "Removed from configuration"
        
        # Update cron
        git-sync-manager update
    else
        warn "Repository not found in configuration"
    fi
    
    # Ask about removing files
    if [ -d "$REPO_PATH" ]; then
        warn "Repository files still exist at $REPO_PATH"
        read -p "Remove repository files? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$REPO_PATH"
            success "Repository files removed"
        fi
    fi
}

deploy_to_host() {
    local target_host="$1"
    
    log "Deploying git-sync to $target_host..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Would deploy to $target_host"
        return 0
    fi
    
    # Copy SSH key if exists
    if [ -f "$SSH_KEY_PATH" ]; then
        log "Copying SSH key..."
        scp "$SSH_KEY_PATH" "$target_host:~/.ssh/"
        scp "${SSH_KEY_PATH}.pub" "$target_host:~/.ssh/"
        ssh "$target_host" "chmod 600 ~/.ssh/$(basename $SSH_KEY_PATH)"
    fi
    
    # Copy tools
    log "Copying git-sync tools..."
    scp /usr/local/bin/git-sync "$target_host:/usr/local/bin/"
    scp /usr/local/bin/git-sync-manager "$target_host:/usr/local/bin/"
    scp /usr/local/bin/git-sync-branch "$target_host:/usr/local/bin/"
    ssh "$target_host" "chmod +x /usr/local/bin/git-sync*"
    
    # Copy configuration
    log "Copying configuration..."
    scp "$CONFIG_FILE" "$target_host:$CONFIG_FILE"
    
    # Update cron on target
    log "Setting up cron jobs..."
    ssh "$target_host" "git-sync-manager update"
    
    success "Deployment complete!"
}

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --install)
            ACTION="install"
            shift
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        --add-repo)
            ACTION="add-repo"
            shift
            ;;
        --remove-repo)
            ACTION="remove-repo"
            shift
            ;;
        --list)
            ACTION="list"
            shift
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --test)
            ACTION="test"
            shift
            ;;
        --update)
            ACTION="update"
            shift
            ;;
        --deploy-to)
            ACTION="deploy"
            shift
            if [[ $# -gt 0 ]]; then
                DEPLOY_HOST="$1"
                shift
            else
                error "Host required for --deploy-to"
                exit 1
            fi
            ;;
        --repo-url)
            shift
            if [[ $# -gt 0 ]]; then
                REPO_URL="$1"
                shift
            else
                error "URL required for --repo-url"
                exit 1
            fi
            ;;
        --repo-path)
            shift
            if [[ $# -gt 0 ]]; then
                REPO_PATH="$1"
                shift
            else
                error "Path required for --repo-path"
                exit 1
            fi
            ;;
        --branch)
            shift
            if [[ $# -gt 0 ]]; then
                REPO_BRANCH="$1"
                shift
            else
                error "Branch required for --branch"
                exit 1
            fi
            ;;
        --interval)
            shift
            if [[ $# -gt 0 ]]; then
                REPO_INTERVAL="$1"
                shift
            else
                error "Interval required for --interval"
                exit 1
            fi
            ;;
        --ssh-key)
            shift
            if [[ $# -gt 0 ]]; then
                SSH_KEY_PATH="$1"
                shift
            else
                error "Path required for --ssh-key"
                exit 1
            fi
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# ============================================================================
# Main Execution
# ============================================================================

# Execute action
case "$ACTION" in
    install)
        check_root
        install_git_sync
        ;;
    uninstall)
        check_root
        uninstall_git_sync
        ;;
    add-repo)
        check_root
        add_repository
        ;;
    remove-repo)
        check_root
        remove_repository
        ;;
    list)
        if command -v git-sync-manager &> /dev/null; then
            git-sync-manager list
        else
            error "git-sync not installed. Run: $0 --install"
            exit 1
        fi
        ;;
    status)
        if [ -f "$CONFIG_FILE" ]; then
            log "Git-sync status:"
            git-sync-manager list
        else
            error "git-sync not configured"
            exit 1
        fi
        ;;
    test)
        if command -v git-sync-manager &> /dev/null; then
            git-sync-manager test
        else
            error "git-sync not installed. Run: $0 --install"
            exit 1
        fi
        ;;
    update)
        if command -v git-sync-manager &> /dev/null; then
            git-sync-manager update
        else
            error "git-sync not installed. Run: $0 --install"
            exit 1
        fi
        ;;
    deploy)
        check_root
        deploy_to_host "$DEPLOY_HOST"
        ;;
    "")
        error "No action specified"
        usage
        ;;
    *)
        error "Unknown action: $ACTION"
        usage
        ;;
esac

exit 0
