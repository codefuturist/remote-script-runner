#!/bin/bash
# Example DNS zone validator for git-auto-sync
set -euo pipefail

REPO_PATH="$1"
ERRORS=0

echo "Validating DNS zone files in: $REPO_PATH"

while IFS= read -r -d '' zone_file; do
    echo "Checking: $zone_file"
    zone_name=$(basename "$zone_file" .zone)
    
    if command -v named-checkzone >/dev/null 2>&1; then
        if ! named-checkzone "$zone_name" "$zone_file" >/dev/null 2>&1; then
            echo "ERROR: Invalid zone file: $zone_file" >&2
            ((ERRORS++))
        else
            echo "  ✓ Valid"
        fi
    fi
done < <(find "$REPO_PATH" -type f \( -name "*.zone" -o -name "db.*" \) -print0 2>/dev/null)

[[ $ERRORS -gt 0 ]] && exit 1
echo "All DNS zones are valid ✓"
exit 0
