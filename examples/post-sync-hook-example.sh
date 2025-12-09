#!/bin/bash
set -euo pipefail

REPO_NAME="$1"
REPO_PATH="$2"
OLD_COMMIT="$3"
NEW_COMMIT="$4"

echo "Post-sync hook: $REPO_NAME synced from $OLD_COMMIT to $NEW_COMMIT"
