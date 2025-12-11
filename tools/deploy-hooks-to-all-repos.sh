#!/usr/bin/env bash
# =============================================================================
# Developer-Friendly Git Hooks Setup Script
# =============================================================================
# Deploys comprehensive git hooks with timeouts and non-blocking behavior
# to all repositories in /Users/colin/Developer/Projects/personal/
#
# Usage:
#   ./deploy-hooks-to-all-repos.sh
#   ./deploy-hooks-to-all-repos.sh --dry-run
#   ./deploy-hooks-to-all-repos.sh --repo-filter "monorepo"
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PERSONAL_DIR="/Users/colin/Developer/Projects/personal"
SOURCE_REPO="$PERSONAL_DIR/remote-script-runner"
DRY_RUN=false
REPO_FILTER=""
VERBOSE=false

# Counters
TOTAL_REPOS=0
UPDATED_REPOS=0
SKIPPED_REPOS=0
FAILED_REPOS=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --repo-filter)
            REPO_FILTER="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run           Show what would be done without making changes"
            echo "  --repo-filter NAME  Only process repos matching NAME"
            echo "  --verbose, -v       Show detailed output"
            echo "  --help, -h          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Helper Functions
# =============================================================================

info() {
    echo -e "${BLUE}▸${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

error() {
    echo -e "${RED}✗${NC} $*"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "  $*"
    fi
}

# =============================================================================
# Check Source Repository
# =============================================================================

if [ ! -d "$SOURCE_REPO" ]; then
    error "Source repository not found: $SOURCE_REPO"
    exit 1
fi

if [ ! -d "$SOURCE_REPO/.husky" ]; then
    error "Source repository doesn't have .husky directory"
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Developer-Friendly Git Hooks Deployment"
echo "═══════════════════════════════════════════════════════════"
echo ""
info "Source: $SOURCE_REPO"
info "Target: $PERSONAL_DIR/*/"
[ "$DRY_RUN" = true ] && warn "DRY RUN MODE - No changes will be made"
[ -n "$REPO_FILTER" ] && info "Filter: *$REPO_FILTER*"
echo ""

# =============================================================================
# Deploy Hooks Function
# =============================================================================

deploy_hooks_to_repo() {
    local repo_path="$1"
    local repo_name=$(basename "$repo_path")
    
    # Skip if doesn't match filter
    if [ -n "$REPO_FILTER" ] && [[ ! "$repo_name" =~ $REPO_FILTER ]]; then
        log_verbose "Skipped $repo_name (doesn't match filter)"
        return 1
    fi
    
    # Skip if not a git repo
    if [ ! -d "$repo_path/.git" ]; then
        log_verbose "Skipped $repo_name (not a git repo)"
        return 1
    fi
    
    # Skip source repo
    if [ "$repo_path" = "$SOURCE_REPO" ]; then
        log_verbose "Skipped $repo_name (source repo)"
        return 1
    fi
    
    # ONLY UPDATE REPOS THAT ALREADY HAVE HOOKS
    local has_hooks=false
    if [ -d "$repo_path/.husky" ] || [ -f "$repo_path/.pre-commit-config.yaml" ] || [ -f "$repo_path/.git/hooks/pre-commit" ]; then
        has_hooks=true
    fi
    
    if [ "$has_hooks" = false ]; then
        log_verbose "Skipped $repo_name (no existing hooks)"
        return 1
    fi
    
    TOTAL_REPOS=$((TOTAL_REPOS + 1))
    
    echo ""
    info "Processing: $repo_name"
    
    if [ "$DRY_RUN" = true ]; then
        echo "  Would copy:"
        echo "    - .husky/ hooks"
        if [ ! -f "$repo_path/.pre-commit-config.yaml" ]; then
            echo "    - .pre-commit-config.yaml (new)"
        else
            echo "    - .pre-commit-config.yaml (already exists, skip)"
        fi
        if [ -d "$repo_path/docs" ]; then
            echo "    - docs/GIT_HOOKS.md"
        fi
        UPDATED_REPOS=$((UPDATED_REPOS + 1))
        return 0
    fi
    
    # Create .husky directory if it doesn't exist
    if [ ! -d "$repo_path/.husky" ]; then
        log_verbose "Creating .husky directory"
        mkdir -p "$repo_path/.husky"
    fi
    
    # Copy husky hooks
    log_verbose "Copying .husky hooks"
    cp -r "$SOURCE_REPO/.husky/_" "$repo_path/.husky/" 2>/dev/null || true
    cp "$SOURCE_REPO/.husky/pre-commit" "$repo_path/.husky/"
    cp "$SOURCE_REPO/.husky/commit-msg" "$repo_path/.husky/"
    cp "$SOURCE_REPO/.husky/pre-push" "$repo_path/.husky/"
    cp "$SOURCE_REPO/.husky/post-merge" "$repo_path/.husky/"
    
    # Make hooks executable
    chmod +x "$repo_path/.husky/pre-commit"
    chmod +x "$repo_path/.husky/commit-msg"
    chmod +x "$repo_path/.husky/pre-push"
    chmod +x "$repo_path/.husky/post-merge"
    
    # Copy .pre-commit-config.yaml if repo doesn't have one
    if [ ! -f "$repo_path/.pre-commit-config.yaml" ]; then
        log_verbose "Creating .pre-commit-config.yaml"
        cp "$SOURCE_REPO/.pre-commit-config.yaml" "$repo_path/"
    else
        log_verbose "Skipping .pre-commit-config.yaml (already exists)"
    fi
    
    # Copy documentation if docs directory exists
    if [ -d "$repo_path/docs" ]; then
        log_verbose "Copying GIT_HOOKS.md to docs/"
        cp "$SOURCE_REPO/docs/GIT_HOOKS.md" "$repo_path/docs/"
    fi
    
    # Check if package.json exists and needs husky
    if [ -f "$repo_path/package.json" ]; then
        if ! grep -q '"husky"' "$repo_path/package.json"; then
            warn "$repo_name: package.json exists but husky not configured"
            echo "       Run: cd $repo_path && npm install --save-dev husky && npx husky install"
        fi
    fi
    
    success "Updated $repo_name"
    UPDATED_REPOS=$((UPDATED_REPOS + 1))
    return 0
}

# =============================================================================
# Main Processing Loop
# =============================================================================

for repo in "$PERSONAL_DIR"/*/; do
    if deploy_hooks_to_repo "$repo"; then
        :
    else
        SKIPPED_REPOS=$((SKIPPED_REPOS + 1))
    fi
done

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Total repositories: $TOTAL_REPOS"
echo "  Updated: $GREEN$UPDATED_REPOS$NC"
echo "  Skipped: $YELLOW$SKIPPED_REPOS$NC"
echo "  Failed: $RED$FAILED_REPOS$NC"
echo ""

if [ "$DRY_RUN" = false ]; then
    success "Deployment complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Review changes: git status"
    echo "  2. Test hooks: cd <repo> && git commit (without changes)"
    echo "  3. Install husky in repos with package.json: npm install"
    echo ""
else
    info "Dry run complete - no changes made"
    echo ""
    echo "To apply changes, run without --dry-run:"
    echo "  $0"
    echo ""
fi

exit 0
