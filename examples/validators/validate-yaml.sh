#!/bin/bash
# Example YAML validator for git-auto-sync
set -euo pipefail

REPO_PATH="$1"
ERRORS=0

echo "Validating YAML files in: $REPO_PATH"

while IFS= read -r -d '' yaml_file; do
    echo "Checking: $yaml_file"
    
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
            echo "ERROR: Invalid YAML: $yaml_file" >&2
            ((ERRORS++))
        else
            echo "  ✓ Valid"
        fi
    fi
done < <(find "$REPO_PATH" -type f \( -name "*.yaml" -o -name "*.yml" \) -print0 2>/dev/null)

[[ $ERRORS -gt 0 ]] && exit 1
echo "All YAML files are valid ✓"
exit 0
