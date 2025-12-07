#!/bin/bash
# Generate redirect scripts for all symlinks in the repository
# These redirect scripts act like symlinks but work with remote execution

set -euo pipefail

# Configuration
REPO_BASE_URL="https://codefuturist.github.io/remote-script-runner"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Function to create a redirect script
create_redirect() {
    local symlink_path="$1"
    local target_path="$2"
    local redirect_path="${symlink_path%.sh}-redirect.sh"
    
    echo "Creating redirect script: $redirect_path -> $target_path"
    
    cat > "$redirect_path" << EOF
#!/bin/bash
# Auto-generated redirect script - acts like a symlink for remote execution
# Target: $target_path
# Generated: $(date)

# Configuration
REPO_BASE_URL="$REPO_BASE_URL"
TARGET_SCRIPT="$target_path"

# Fetch and execute the target script with all arguments
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "\$REPO_BASE_URL/\$TARGET_SCRIPT" | bash -s -- "\$@"
elif command -v wget >/dev/null 2>&1; then
    wget -qO- "\$REPO_BASE_URL/\$TARGET_SCRIPT" | bash -s -- "\$@"
else
    echo "Error: Neither curl nor wget is available"
    exit 1
fi
EOF
    
    chmod +x "$redirect_path"
}

# Find all symlinks in the repo
echo "Scanning for symlinks in the repository..."
cd "$REPO_ROOT"

find . -type l -name "*.sh" | while read -r symlink; do
    # Get the target of the symlink
    target=$(readlink "$symlink")
    
    # Skip if not a relative path within the repo
    if [[ "$target" =~ ^/ ]]; then
        echo "Skipping absolute symlink: $symlink -> $target"
        continue
    fi
    
    # Create redirect script
    create_redirect "$symlink" "$target"
done

echo "Done! Redirect scripts have been generated."
echo "These scripts will work for remote execution while maintaining the symlink behavior."
