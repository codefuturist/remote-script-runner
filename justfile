# Remote Script Runner Justfile
# Migrated from Makefile to modular just-modules system

# ═══════════════════════════════════════════════════════════════════════════════
# Configuration

# ═══════════════════════════════════════════════════════════════════════════════
# Imports
# ═══════════════════════════════════════════════════════════════════════════════

# Core (required)
import '.just-modules/core/mod.just'

# Automation & Project Management
import '.just-modules/traits/automation-helpers.just'
import '.just-modules/traits/env.just'

# Features
mod versioning '.just-modules/traits/versioning.just'
mod gitflow '.just-modules/traits/gitflow.just'
mod hooks '.just-modules/traits/hooks.just'
mod docs '.just-modules/traits/docs.just'
mod cog '.just-modules/traits/cocogitto.just'

# Code Quality & Refactoring
import '.just-modules/traits/ast-grep.just'
import '.just-modules/traits/megalinter.just'
import '.just-modules/traits/backup.just'

# Security & Encryption
import '.just-modules/traits/encryption.just'

# AI Features
import '.just-modules/traits/ai.just'

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

project_name := 'Remote Script Runner'

# Import language modules
mod python '.just-modules/languages/python/mod.just'
mod node '.just-modules/languages/node/mod.just'

# Import features
mod security '.just-modules/traits/security.just'

# ═══════════════════════════════════════════════════════════════════════════════
# Default
# ═══════════════════════════════════════════════════════════════════════════════

default:
    @just --list --list-heading $'🚀 Remote Script Runner - Available commands:\n'

# ═══════════════════════════════════════════════════════════════════════════════
# Setup
# ═══════════════════════════════════════════════════════════════════════════════

# Complete project setup
[group('setup')]
setup:
    @just _header "Project Setup"
    @just python::deps
    @just node::deps
    @just hooks-install
    @just _success "Setup complete!"

# Install Husky hooks
[group('setup')]
hooks-install:
    @just _info "Installing Husky hooks..."
    @npx husky install
    @pre-commit install --install-hooks
    @just _success "Hooks installed"

# ═══════════════════════════════════════════════════════════════════════════════
# Script Registry
# ═══════════════════════════════════════════════════════════════════════════════

# List registered scripts
[group('registry')]
registry-list:
    @just _header "Registered Scripts"
    @cat registry.json | jq -r '.scripts[] | "\(.name): \(.description)"'

# Add script to registry
[group('registry')]
registry-add name description path:
    @just _info "Adding script: {{name}}"
    @bash scripts/registry-add.sh {{name}} "{{description}}" {{path}}
    @just _success "Script added to registry"

# Remove script from registry
[group('registry')]
registry-remove name:
    @just _info "Removing script: {{name}}"
    @bash scripts/registry-remove.sh {{name}}
    @just _success "Script removed from registry"

# Validate registry
[group('registry')]
registry-validate:
    @just _header "Validating Registry"
    @python3 scripts/validate_registry.py
    @just _success "Registry valid"

# Generate code from registry
[group('registry')]
registry-generate:
    @just _info "Generating code from registry..."
    @python3 scripts/generate_from_registry.py
    @just _success "Code generated"

# ═══════════════════════════════════════════════════════════════════════════════
# Script Execution
# ═══════════════════════════════════════════════════════════════════════════════

# Run a Bash script
[group('run')]
run-bash script *args:
    @just _info "Running Bash script: {{script}}"
    @bash scripts/bash/{{script}}.sh {{args}}

# Run a PowerShell script
[group('run')]
run-powershell script *args:
    @just _info "Running PowerShell script: {{script}}"
    @pwsh scripts/powershell/{{script}}.ps1 {{args}}

# Run a Python script
[group('run')]
run-python script *args:
    @just _info "Running Python script: {{script}}"
    @python3 scripts/python/{{script}}.py {{args}}

# ═══════════════════════════════════════════════════════════════════════════════
# Testing
# ═══════════════════════════════════════════════════════════════════════════════

# Run all tests
[group('test')]
test:
    @just _header "Running Tests"
    @just test-bash
    @just python::test
    @just _success "All tests passed"

# Run Bash tests (BATS)
[group('test')]
test-bash:
    @just _info "Running BATS tests..."
    @bats tests/bash/*.bats

# Run specific BATS test
[group('test')]
test-bash-file file:
    @just _info "Running BATS test: {{file}}"
    @bats tests/bash/{{file}}.bats

# Verbose BATS output
[group('test')]
test-bash-verbose:
    @just _info "Running BATS tests (verbose)..."
    @bats -t tests/bash/*.bats

# TAP format output
[group('test')]
test-bash-tap:
    @just _info "Running BATS tests (TAP format)..."
    @bats --formatter tap tests/bash/*.bats

# ═══════════════════════════════════════════════════════════════════════════════
# Linting
# ═══════════════════════════════════════════════════════════════════════════════

# Run all linters
[group('lint')]
lint:
    @just _header "Running Linters"
    @just lint-bash
    @just lint-powershell
    @just python::lint
    @just node::lint
    @just lint-yaml
    @just lint-markdown
    @just _success "Linting complete"

# Lint Bash scripts
[group('lint')]
lint-bash:
    @just _info "Linting Bash scripts..."
    @shellcheck scripts/bash/*.sh tests/bash/*.sh

# Lint PowerShell scripts
[group('lint')]
lint-powershell:
    @just _info "Linting PowerShell scripts..."
    @pwsh -Command "Invoke-ScriptAnalyzer -Path scripts/powershell/*.ps1" || echo "PSScriptAnalyzer not available"

# Lint YAML files
[group('lint')]
lint-yaml:
    @just _info "Linting YAML files..."
    @yamllint .

# Lint Markdown files
[group('lint')]
lint-markdown:
    @just _info "Linting Markdown files..."
    @npx markdownlint-cli '**/*.md'

# Format Bash scripts
[group('lint')]
format-bash:
    @just _info "Formatting Bash scripts..."
    @shfmt -w scripts/bash/*.sh tests/bash/*.sh

# ═══════════════════════════════════════════════════════════════════════════════
# Validation
# ═══════════════════════════════════════════════════════════════════════════════

# Validate all scripts
[group('validate')]
validate:
    @just _header "Validating Scripts"
    @bash scripts/validate_all.sh
    @just _success "Validation complete"

# Syntax check Bash scripts
[group('validate')]
validate-bash:
    @just _info "Validating Bash syntax..."
    @for script in scripts/bash/*.sh; do bash -n $$script || exit 1; done

# Syntax check PowerShell scripts
[group('validate')]
validate-powershell:
    @just _info "Validating PowerShell syntax..."
    @for script in scripts/powershell/*.ps1; do pwsh -NoProfile -Command "Get-Command -Syntax $$script" >/dev/null || exit 1; done

# ═══════════════════════════════════════════════════════════════════════════════
# Maintenance
# ═══════════════════════════════════════════════════════════════════════════════

# Clean artifacts
[group('maintenance')]
clean:
    @just _info "Cleaning..."
    @just python::clean
    @just node::clean
    @rm -rf tmp/ dist/
    @just _success "Cleaned"

# Show project info
info:
    @just _header "{{project_name}}"
    @just _kv "Version" "{{_git_tag}}"
    @just _kv "Branch" "{{_git_branch}}"
    @just _kv "Scripts" "$(cat registry.json | jq '.scripts | length')"

# ══════════════════════════════════════════════════════════════════════════════
# Just-Modules Management
# ══════════════════════════════════════════════════════════════════════════════

# Browse and interactively add just-modules to this project
[group('modules')]
modules-browse:
    @just _header "Available just-modules"
    @echo ""
    @echo "{{ BOLD }}{{ CYAN }}Language Modules:{{ NORMAL }}"
    @ls -1 .just-modules/languages/ 2>/dev/null | sed 's/^/  • /' || echo "  (none found)"
    @echo ""
    @echo "{{ BOLD }}{{ CYAN }}Traits/Features:{{ NORMAL }}"
    @ls -1 .just-modules/traits/*.just 2>/dev/null | xargs -n1 basename | sed 's/.just$//' | sed 's/^/  • /' || echo "  (none found)"
    @echo ""
    @echo "{{ BOLD }}{{ YELLOW }}To add a module, edit your justfile and add:{{ NORMAL }}"
    @echo "  {{ GREEN }}mod <name> '.just-modules/languages/<name>/mod.just'{{ NORMAL }}  # For languages"
    @echo "  {{ GREEN }}import '.just-modules/traits/<name>.just'{{ NORMAL }}              # For traits"
    @echo ""
    @echo "{{ BOLD }}Example - Add Go support:{{ NORMAL }}"
    @echo "  Add this line to your imports section:"
    @echo "  {{ CYAN }}mod go '.just-modules/languages/go/mod.just'{{ NORMAL }}"

# Show currently imported modules
[group('modules')]
modules-list:
    @just _header "Currently Imported Modules"
    @echo ""
    @echo "{{ BOLD }}Language Modules:{{ NORMAL }}"
    @grep "^mod .* '.just-modules/languages/" justfile | sed "s/^mod /  • /" | sed "s/ '.*//" || echo "  (none)"
    @echo ""
    @echo "{{ BOLD }}Trait Imports:{{ NORMAL }}"
    @grep "^import '.just-modules/traits/" justfile | sed "s/^import '.just-modules\/traits\//  • /" | sed "s/.just'.*//" || echo "  (none)"
    @echo ""
    @echo "{{ BOLD }}Trait Modules:{{ NORMAL }}"
    @grep "^mod .* '.just-modules/traits/" justfile | sed "s/^mod /  • /" | sed "s/ '.*//" || echo "  (none)"

# Update just-modules submodule to latest version
[group('modules')]
modules-update:
    @just _header "Updating just-modules"
    @just _info "Pulling latest from remote..."
    @cd .just-modules && git pull origin main
    @just _success "just-modules updated to latest version"

# Show just-modules submodule status
[group('modules')]
modules-status:
    @just _header "just-modules Submodule Status"
    @cd .just-modules && git log -1 --format="  {{ BOLD }}Commit:{{ NORMAL }} %h - %s" && git log -1 --format="  {{ BOLD }}Date:{{ NORMAL }}   %cr"
    @cd .just-modules && echo "  {{ BOLD }}Branch:{{ NORMAL }} $(git branch --show-current || echo 'detached')"
    @echo ""
    @cd .just-modules && git fetch origin --quiet && \
        LOCAL=$(git rev-parse HEAD) && \
        REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "$LOCAL") && \
        if [ "$LOCAL" = "$REMOTE" ]; then \
            echo "  {{ GREEN }}✓ Up to date{{ NORMAL }}"; \
        else \
            echo "  {{ YELLOW }}⚠ Updates available{{ NORMAL }} (run: just modules-update)"; \
        fi
