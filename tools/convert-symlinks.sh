#!/bin/bash
# Convert symlinks to remote-compatible redirect scripts
# This allows symlinks to work when accessed via GitHub raw URLs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/symlink-template.sh"

if [ ! -f "$TEMPLATE" ]; then
    echo "Error: Template file not found: $TEMPLATE"
    exit 1
fi

echo "Converting symlinks to remote-compatible scripts..."

# Function to convert a single symlink
convert_symlink() {
    local symlink="$1"
    local target=$(readlink "$symlink")
    
    echo "Converting: $symlink -> $target"
    
    # Create the new script from template
    sed "s|__TARGET_PATH__|$target|g" "$TEMPLATE" > "$symlink.tmp"
    
    # Remove the symlink and replace with the script
    rm "$symlink"
    mv "$symlink.tmp" "$symlink"
    chmod +x "$symlink"
    
    echo "  ✓ Converted to remote-compatible script"
}

# Process arguments or find all symlinks
if [ $# -gt 0 ]; then
    # Convert specific symlinks
    for symlink in "$@"; do
        if [ -L "$symlink" ]; then
            convert_symlink "$symlink"
        else
            echo "Skipping non-symlink: $symlink"
        fi
    done
else
    # Convert all symlinks in the current directory
    find . -type l -name "*.sh" | while read -r symlink; do
        convert_symlink "$symlink"
    done
fi

echo "Done! Symlinks have been converted to remote-compatible scripts."
