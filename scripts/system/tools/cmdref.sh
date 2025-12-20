#!/bin/bash
# =============================================================================
# @id           cmdref
# @name         cmdref
# @displayName  Command Reference
# @description  Interactive command reference with search, favorites, clipboard, history, custom commands, and aliases
# @category     system
# @version      2.1.0
# @author       codefuturist
# @tags         commands,reference,cheatsheet,git,docker,npm,python,clipboard,tools
# @shells       bash
# @requires     bash 4.0+
# @os           linux,macos
# @sudo         none
# =============================================================================

# This script can be run remotely with curl and accepts arguments
# Example: /bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/system/tools/cmdref.sh)" -- --search git

set -eo pipefail

# =============================================================================
# Load RSR Library
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [[ -n "${SCRIPT_SOURCE}" ]] && [[ "${SCRIPT_SOURCE}" != "bash" ]] && [[ "${SCRIPT_SOURCE}" != "sh" ]] && [[ "${SCRIPT_SOURCE}" != "-bash" ]] && [[ "${SCRIPT_SOURCE}" != "-sh" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

# Load the RSR library if available, otherwise use fallback
if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    # shellcheck source=../../../lib/rsr-lib.sh
    source "$RSR_LIB_DIR/rsr-lib.sh" validate
    USE_RSR_LIB=true
else
    USE_RSR_LIB=false
fi

# =============================================================================
# Script Metadata
# =============================================================================

readonly SCRIPT_NAME="cmdref"
readonly SCRIPT_VERSION="2.1.0"
readonly SCRIPT_DISPLAY_NAME="Command Reference"

# =============================================================================
# Configuration
# =============================================================================

readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rsr/cmdref"
readonly HISTORY_FILE="${CONFIG_DIR}/history.txt"
readonly FAVORITES_FILE="${CONFIG_DIR}/favorites.txt"
readonly CUSTOM_COMMANDS_FILE="${CONFIG_DIR}/custom_commands.yaml"
readonly STATS_FILE="${CONFIG_DIR}/stats.json"
readonly ALIASES_FILE="${CONFIG_DIR}/aliases.txt"
readonly MAX_HISTORY_ENTRIES=100

VERBOSE=false
OUTPUT_FORMAT="text"  # text, json

# =============================================================================
# Color Setup
# =============================================================================

setup_colors() {
    if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        MAGENTA='\033[0;35m'
        CYAN='\033[0;36m'
        WHITE='\033[1;37m'
        BOLD='\033[1m'
        DIM='\033[2m'
        RESET='\033[0m'
    else
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        MAGENTA=''
        CYAN=''
        WHITE=''
        BOLD=''
        DIM=''
        RESET=''
    fi
}

setup_colors

# =============================================================================
# Logging Functions
# =============================================================================

if [[ "$USE_RSR_LIB" == "true" ]]; then
    log_info() { rsr_log_info "$*"; }
    log_ok() { rsr_log_ok "$*"; }
    log_warn() { rsr_log_warn "$*"; }
    log_error() { rsr_log_error "$*"; }
else
    log_info() { printf "${BLUE}▸${RESET} %s\n" "$1"; }
    log_ok() { printf "${GREEN}✓${RESET} %s\n" "$1"; }
    log_warn() { printf "${YELLOW}⚠${RESET} %s\n" "$1" >&2; }
    log_error() { printf "${RED}✗${RESET} %s\n" "$1" >&2; }
fi

# =============================================================================
# Initialize Configuration
# =============================================================================

init_config() {
    [[ ! -d "$CONFIG_DIR" ]] && mkdir -p "$CONFIG_DIR" || true
    [[ ! -f "$HISTORY_FILE" ]] && touch "$HISTORY_FILE" || true
    [[ ! -f "$FAVORITES_FILE" ]] && touch "$FAVORITES_FILE" || true
    [[ ! -f "$CUSTOM_COMMANDS_FILE" ]] && echo "# Custom Commands - Add your own commands here
# Format: key|command|description|category
# Example: my_deploy|./deploy.sh --prod|Deploy to production|Custom
commands: []" > "$CUSTOM_COMMANDS_FILE" || true
    [[ ! -f "$STATS_FILE" ]] && echo '{"commands":{}}' > "$STATS_FILE" || true
    [[ ! -f "$ALIASES_FILE" ]] && touch "$ALIASES_FILE" || true
}

# =============================================================================
# Command Descriptions Database
# =============================================================================

declare -a COMMAND_DESCRIPTIONS=()

init_descriptions() {
    # Git Commands
    COMMAND_DESCRIPTIONS+=("Initialize a new Git repository")
    COMMAND_DESCRIPTIONS+=("Clone a remote repository to local")
    COMMAND_DESCRIPTIONS+=("Check working tree status")
    COMMAND_DESCRIPTIONS+=("Stage all changes for commit")
    COMMAND_DESCRIPTIONS+=("Commit staged changes with message")
    COMMAND_DESCRIPTIONS+=("Push commits to remote branch")
    COMMAND_DESCRIPTIONS+=("Pull latest changes from remote")
    COMMAND_DESCRIPTIONS+=("Create and switch to new branch")
    COMMAND_DESCRIPTIONS+=("Delete a local branch")
    COMMAND_DESCRIPTIONS+=("Temporarily store modified files")
    COMMAND_DESCRIPTIONS+=("Restore stashed changes")
    COMMAND_DESCRIPTIONS+=("View commit history as graph")
    COMMAND_DESCRIPTIONS+=("Undo last commit, keep changes staged")
    COMMAND_DESCRIPTIONS+=("Undo last commit, discard changes")
    COMMAND_DESCRIPTIONS+=("Interactively rebase last n commits")
    COMMAND_DESCRIPTIONS+=("Apply specific commit to current branch")
    COMMAND_DESCRIPTIONS+=("Merge branch into current branch")
    COMMAND_DESCRIPTIONS+=("Add remote repository URL")
    COMMAND_DESCRIPTIONS+=("List all tags")
    COMMAND_DESCRIPTIONS+=("Create annotated tag with message")

    # Git Flow
    COMMAND_DESCRIPTIONS+=("Start new feature branch from develop")
    COMMAND_DESCRIPTIONS+=("Finish feature, merge to develop")
    COMMAND_DESCRIPTIONS+=("Publish feature branch to remote")
    COMMAND_DESCRIPTIONS+=("List all feature branches")
    COMMAND_DESCRIPTIONS+=("Start release branch for version")
    COMMAND_DESCRIPTIONS+=("Finish release, merge and tag")
    COMMAND_DESCRIPTIONS+=("Start hotfix for production bug")
    COMMAND_DESCRIPTIONS+=("Finish hotfix, merge to main/develop")

    # Docker
    COMMAND_DESCRIPTIONS+=("List running containers")
    COMMAND_DESCRIPTIONS+=("List all containers including stopped")
    COMMAND_DESCRIPTIONS+=("List downloaded images")
    COMMAND_DESCRIPTIONS+=("Run container interactively")
    COMMAND_DESCRIPTIONS+=("Build image from Dockerfile")
    COMMAND_DESCRIPTIONS+=("Stop running container")
    COMMAND_DESCRIPTIONS+=("Remove stopped container")
    COMMAND_DESCRIPTIONS+=("Remove image from local storage")
    COMMAND_DESCRIPTIONS+=("Execute command in running container")
    COMMAND_DESCRIPTIONS+=("Follow container logs in real-time")
    COMMAND_DESCRIPTIONS+=("Start services in detached mode")
    COMMAND_DESCRIPTIONS+=("Stop and remove containers")
    COMMAND_DESCRIPTIONS+=("Remove all unused Docker data")
    COMMAND_DESCRIPTIONS+=("List Docker volumes")
    COMMAND_DESCRIPTIONS+=("List Docker networks")
    COMMAND_DESCRIPTIONS+=("Pull latest version of image")
    COMMAND_DESCRIPTIONS+=("Update all images to latest")

    # NPM/Node
    COMMAND_DESCRIPTIONS+=("Create package.json with defaults")
    COMMAND_DESCRIPTIONS+=("Install all dependencies")
    COMMAND_DESCRIPTIONS+=("Install specific package")
    COMMAND_DESCRIPTIONS+=("Install package as dev dependency")
    COMMAND_DESCRIPTIONS+=("Remove package from project")
    COMMAND_DESCRIPTIONS+=("Update all packages")
    COMMAND_DESCRIPTIONS+=("Update specific package to latest")
    COMMAND_DESCRIPTIONS+=("Check for security vulnerabilities")
    COMMAND_DESCRIPTIONS+=("Auto-fix vulnerabilities")
    COMMAND_DESCRIPTIONS+=("Start development server")
    COMMAND_DESCRIPTIONS+=("Build for production")
    COMMAND_DESCRIPTIONS+=("Run test suite")
    COMMAND_DESCRIPTIONS+=("List installed packages")
    COMMAND_DESCRIPTIONS+=("Show outdated packages")
    COMMAND_DESCRIPTIONS+=("Upgrade npm to latest version")

    # Python
    COMMAND_DESCRIPTIONS+=("Install Python package")
    COMMAND_DESCRIPTIONS+=("Install from requirements file")
    COMMAND_DESCRIPTIONS+=("Export installed packages to file")
    COMMAND_DESCRIPTIONS+=("List installed packages")
    COMMAND_DESCRIPTIONS+=("Remove Python package")
    COMMAND_DESCRIPTIONS+=("Upgrade specific package to latest")
    COMMAND_DESCRIPTIONS+=("Upgrade all outdated packages")
    COMMAND_DESCRIPTIONS+=("Show outdated packages")
    COMMAND_DESCRIPTIONS+=("Create virtual environment")
    COMMAND_DESCRIPTIONS+=("Activate virtual environment")
    COMMAND_DESCRIPTIONS+=("Deactivate virtual environment")
    COMMAND_DESCRIPTIONS+=("Start simple HTTP server")

    # UV (Fast Python Package Manager)
    COMMAND_DESCRIPTIONS+=("Initialize new Python project with uv")
    COMMAND_DESCRIPTIONS+=("Add package to project dependencies")
    COMMAND_DESCRIPTIONS+=("Add package as dev dependency")
    COMMAND_DESCRIPTIONS+=("Remove package from project")
    COMMAND_DESCRIPTIONS+=("Sync project dependencies from lockfile")
    COMMAND_DESCRIPTIONS+=("Update project lockfile")
    COMMAND_DESCRIPTIONS+=("Upgrade specific package to latest")
    COMMAND_DESCRIPTIONS+=("Upgrade all packages to latest")
    COMMAND_DESCRIPTIONS+=("Run Python script in project environment")
    COMMAND_DESCRIPTIONS+=("Run command in project environment")
    COMMAND_DESCRIPTIONS+=("Create virtual environment with uv (10x faster)")
    COMMAND_DESCRIPTIONS+=("Install package with uv pip (100x faster)")
    COMMAND_DESCRIPTIONS+=("Install from requirements with uv")
    COMMAND_DESCRIPTIONS+=("Compile requirements to locked file")
    COMMAND_DESCRIPTIONS+=("List installed packages with uv")
    COMMAND_DESCRIPTIONS+=("Show package dependency tree")
    COMMAND_DESCRIPTIONS+=("Show outdated packages")
    COMMAND_DESCRIPTIONS+=("Install specific Python version")
    COMMAND_DESCRIPTIONS+=("List available Python versions")
    COMMAND_DESCRIPTIONS+=("Pin Python version for project")
    COMMAND_DESCRIPTIONS+=("Build Python package for distribution")
    COMMAND_DESCRIPTIONS+=("Run tool without installing (like npx)")
    COMMAND_DESCRIPTIONS+=("Upgrade uv to latest version")

    # Yarn (JavaScript/Node.js)
    COMMAND_DESCRIPTIONS+=("Initialize Yarn project")
    COMMAND_DESCRIPTIONS+=("Install all dependencies")
    COMMAND_DESCRIPTIONS+=("Add package dependency")
    COMMAND_DESCRIPTIONS+=("Add dev dependency")
    COMMAND_DESCRIPTIONS+=("Remove package")
    COMMAND_DESCRIPTIONS+=("Upgrade all packages")
    COMMAND_DESCRIPTIONS+=("Upgrade specific package")
    COMMAND_DESCRIPTIONS+=("Show outdated packages")
    COMMAND_DESCRIPTIONS+=("Run script from package.json")
    COMMAND_DESCRIPTIONS+=("Run package binary (like npx)")
    COMMAND_DESCRIPTIONS+=("Upgrade Yarn to latest stable")

    # pnpm (JavaScript/Node.js)
    COMMAND_DESCRIPTIONS+=("Initialize pnpm project")
    COMMAND_DESCRIPTIONS+=("Install all dependencies")
    COMMAND_DESCRIPTIONS+=("Add package dependency")
    COMMAND_DESCRIPTIONS+=("Add dev dependency")
    COMMAND_DESCRIPTIONS+=("Remove package")
    COMMAND_DESCRIPTIONS+=("Update all packages")
    COMMAND_DESCRIPTIONS+=("Update specific package")
    COMMAND_DESCRIPTIONS+=("Show outdated packages")
    COMMAND_DESCRIPTIONS+=("Run script from package.json")
    COMMAND_DESCRIPTIONS+=("Run package binary (like npx)")
    COMMAND_DESCRIPTIONS+=("Upgrade pnpm to latest version")

    # Go (golang)
    COMMAND_DESCRIPTIONS+=("Initialize Go module")
    COMMAND_DESCRIPTIONS+=("Add dependency")
    COMMAND_DESCRIPTIONS+=("Upgrade dependency to latest")
    COMMAND_DESCRIPTIONS+=("Upgrade all dependencies")
    COMMAND_DESCRIPTIONS+=("Clean up module dependencies")
    COMMAND_DESCRIPTIONS+=("Download dependencies")
    COMMAND_DESCRIPTIONS+=("Build Go project")
    COMMAND_DESCRIPTIONS+=("Run Go file directly")
    COMMAND_DESCRIPTIONS+=("Run all tests")
    COMMAND_DESCRIPTIONS+=("Format Go code")
    COMMAND_DESCRIPTIONS+=("Static analysis")
    COMMAND_DESCRIPTIONS+=("Show outdated dependencies")

    # Rust (cargo)
    COMMAND_DESCRIPTIONS+=("Create new Rust project")
    COMMAND_DESCRIPTIONS+=("Initialize in existing directory")
    COMMAND_DESCRIPTIONS+=("Add crate dependency")
    COMMAND_DESCRIPTIONS+=("Add dev dependency")
    COMMAND_DESCRIPTIONS+=("Update all dependencies")
    COMMAND_DESCRIPTIONS+=("Update specific crate")
    COMMAND_DESCRIPTIONS+=("Build debug version")
    COMMAND_DESCRIPTIONS+=("Build release version")
    COMMAND_DESCRIPTIONS+=("Run project")
    COMMAND_DESCRIPTIONS+=("Run all tests")
    COMMAND_DESCRIPTIONS+=("Format Rust code")
    COMMAND_DESCRIPTIONS+=("Lint with Clippy")
    COMMAND_DESCRIPTIONS+=("Check without building")
    COMMAND_DESCRIPTIONS+=("Show outdated crates")
    COMMAND_DESCRIPTIONS+=("Update Rust toolchain")
    COMMAND_DESCRIPTIONS+=("Update rustup itself")

    # Ruby (gem/bundler)
    COMMAND_DESCRIPTIONS+=("Create Gemfile")
    COMMAND_DESCRIPTIONS+=("Install all gems")
    COMMAND_DESCRIPTIONS+=("Install gem globally")
    COMMAND_DESCRIPTIONS+=("Add gem to project")
    COMMAND_DESCRIPTIONS+=("Update all gems")
    COMMAND_DESCRIPTIONS+=("Update specific gem")
    COMMAND_DESCRIPTIONS+=("Show outdated gems")
    COMMAND_DESCRIPTIONS+=("Run command in bundle context")
    COMMAND_DESCRIPTIONS+=("Run Ruby file")
    COMMAND_DESCRIPTIONS+=("Run Rake tests")
    COMMAND_DESCRIPTIONS+=("Update RubyGems system")

    # PHP (composer)
    COMMAND_DESCRIPTIONS+=("Create composer.json")
    COMMAND_DESCRIPTIONS+=("Install all dependencies")
    COMMAND_DESCRIPTIONS+=("Add package dependency")
    COMMAND_DESCRIPTIONS+=("Add dev dependency")
    COMMAND_DESCRIPTIONS+=("Update all packages")
    COMMAND_DESCRIPTIONS+=("Update specific package")
    COMMAND_DESCRIPTIONS+=("Show outdated packages")
    COMMAND_DESCRIPTIONS+=("Remove package")
    COMMAND_DESCRIPTIONS+=("Run PHP file")
    COMMAND_DESCRIPTIONS+=("Run PHPUnit tests")
    COMMAND_DESCRIPTIONS+=("Dump autoloader")
    COMMAND_DESCRIPTIONS+=("Upgrade Composer to latest")

    # Java (Maven)
    COMMAND_DESCRIPTIONS+=("Create new Maven project")
    COMMAND_DESCRIPTIONS+=("Compile project")
    COMMAND_DESCRIPTIONS+=("Run tests")
    COMMAND_DESCRIPTIONS+=("Build JAR/WAR package")
    COMMAND_DESCRIPTIONS+=("Install to local repository")
    COMMAND_DESCRIPTIONS+=("Clean build files")
    COMMAND_DESCRIPTIONS+=("Show dependency tree")
    COMMAND_DESCRIPTIONS+=("Show outdated dependencies")

    # Java (Gradle)
    COMMAND_DESCRIPTIONS+=("Initialize Gradle project")
    COMMAND_DESCRIPTIONS+=("Build project")
    COMMAND_DESCRIPTIONS+=("Run tests")
    COMMAND_DESCRIPTIONS+=("Clean build files")
    COMMAND_DESCRIPTIONS+=("Show dependencies")
    COMMAND_DESCRIPTIONS+=("Run application")

    # .NET/C# (dotnet)
    COMMAND_DESCRIPTIONS+=("Create new .NET project")
    COMMAND_DESCRIPTIONS+=("Restore dependencies")
    COMMAND_DESCRIPTIONS+=("Build project")
    COMMAND_DESCRIPTIONS+=("Run project")
    COMMAND_DESCRIPTIONS+=("Run tests")
    COMMAND_DESCRIPTIONS+=("Add NuGet package")
    COMMAND_DESCRIPTIONS+=("Show outdated packages")
    COMMAND_DESCRIPTIONS+=("Publish for deployment")
    COMMAND_DESCRIPTIONS+=("Clean build output")
    COMMAND_DESCRIPTIONS+=("Watch and rebuild on changes")

    # Swift (SPM)
    COMMAND_DESCRIPTIONS+=("Initialize Swift package")
    COMMAND_DESCRIPTIONS+=("Build package")
    COMMAND_DESCRIPTIONS+=("Build and run")
    COMMAND_DESCRIPTIONS+=("Run tests")
    COMMAND_DESCRIPTIONS+=("Resolve dependencies")
    COMMAND_DESCRIPTIONS+=("Update dependencies")
    COMMAND_DESCRIPTIONS+=("Show dependency tree")
    COMMAND_DESCRIPTIONS+=("Clean build artifacts")

    # File Operations
    COMMAND_DESCRIPTIONS+=("Find files by name pattern")
    COMMAND_DESCRIPTIONS+=("Find files only (not directories)")
    COMMAND_DESCRIPTIONS+=("Find recently modified files")
    COMMAND_DESCRIPTIONS+=("Search text in files recursively")
    COMMAND_DESCRIPTIONS+=("Case-insensitive text search")
    COMMAND_DESCRIPTIONS+=("Create compressed tar archive")
    COMMAND_DESCRIPTIONS+=("Extract tar.gz archive")
    COMMAND_DESCRIPTIONS+=("Create zip archive")
    COMMAND_DESCRIPTIONS+=("Extract zip archive")
    COMMAND_DESCRIPTIONS+=("Sync files locally with progress")
    COMMAND_DESCRIPTIONS+=("Sync files to remote server")

    # Text Replacement (sed/awk)
    COMMAND_DESCRIPTIONS+=("Replace string in file (in-place)")
    COMMAND_DESCRIPTIONS+=("Replace string with regex (in-place)")
    COMMAND_DESCRIPTIONS+=("Replace string in all files recursively")
    COMMAND_DESCRIPTIONS+=("Preview replacements without modifying")
    COMMAND_DESCRIPTIONS+=("Replace with backup file created")
    COMMAND_DESCRIPTIONS+=("Delete lines matching pattern")
    COMMAND_DESCRIPTIONS+=("Replace only on lines matching pattern")
    COMMAND_DESCRIPTIONS+=("Replace nth occurrence on each line")
    COMMAND_DESCRIPTIONS+=("Case-insensitive replacement (GNU sed)")
    COMMAND_DESCRIPTIONS+=("Replace using awk (complex patterns)")
    COMMAND_DESCRIPTIONS+=("Replace and show only changed lines")
    COMMAND_DESCRIPTIONS+=("Multi-file find and replace")

    # Network
    COMMAND_DESCRIPTIONS+=("HTTP GET request")
    COMMAND_DESCRIPTIONS+=("HTTP POST with JSON body")
    COMMAND_DESCRIPTIONS+=("Download file from URL")
    COMMAND_DESCRIPTIONS+=("Download file with wget")
    COMMAND_DESCRIPTIONS+=("Show listening network ports")
    COMMAND_DESCRIPTIONS+=("Find process using specific port")
    COMMAND_DESCRIPTIONS+=("Kill process on specific port")
    COMMAND_DESCRIPTIONS+=("Test network connectivity")
    COMMAND_DESCRIPTIONS+=("Trace network route to host")
    COMMAND_DESCRIPTIONS+=("DNS lookup for domain")
    COMMAND_DESCRIPTIONS+=("Connect to remote server via SSH")
    COMMAND_DESCRIPTIONS+=("Copy SSH key to remote server")
    COMMAND_DESCRIPTIONS+=("Upload file via SCP")
    COMMAND_DESCRIPTIONS+=("Download file via SCP")

    # Process Management
    COMMAND_DESCRIPTIONS+=("Find running process by name")
    COMMAND_DESCRIPTIONS+=("Force kill process by PID")
    COMMAND_DESCRIPTIONS+=("Show processes sorted by CPU")
    COMMAND_DESCRIPTIONS+=("Interactive process viewer")
    COMMAND_DESCRIPTIONS+=("List background jobs")
    COMMAND_DESCRIPTIONS+=("Resume job in background")
    COMMAND_DESCRIPTIONS+=("Bring job to foreground")

    # Database
    COMMAND_DESCRIPTIONS+=("Connect to MySQL database")
    COMMAND_DESCRIPTIONS+=("Export MySQL database to file")
    COMMAND_DESCRIPTIONS+=("Import SQL file to MySQL")
    COMMAND_DESCRIPTIONS+=("Connect to PostgreSQL database")
    COMMAND_DESCRIPTIONS+=("Export PostgreSQL database")
    COMMAND_DESCRIPTIONS+=("Import SQL to PostgreSQL")
    COMMAND_DESCRIPTIONS+=("Start Redis CLI")
    COMMAND_DESCRIPTIONS+=("Start MongoDB shell")

    # macOS
    COMMAND_DESCRIPTIONS+=("Install package via Homebrew")
    COMMAND_DESCRIPTIONS+=("Uninstall Homebrew package")
    COMMAND_DESCRIPTIONS+=("Update Homebrew package list")
    COMMAND_DESCRIPTIONS+=("Upgrade all packages")
    COMMAND_DESCRIPTIONS+=("Upgrade specific package")
    COMMAND_DESCRIPTIONS+=("Show outdated packages")
    COMMAND_DESCRIPTIONS+=("List installed packages")
    COMMAND_DESCRIPTIONS+=("Search for package")
    COMMAND_DESCRIPTIONS+=("Show package information")
    COMMAND_DESCRIPTIONS+=("Open current directory in Finder")
    COMMAND_DESCRIPTIONS+=("Open application by name")
    COMMAND_DESCRIPTIONS+=("Copy output to clipboard")
    COMMAND_DESCRIPTIONS+=("Paste from clipboard")
    COMMAND_DESCRIPTIONS+=("Text to speech")

    # Development Tools
    COMMAND_DESCRIPTIONS+=("Open VS Code in current directory")
    COMMAND_DESCRIPTIONS+=("Compare two files in VS Code")
    COMMAND_DESCRIPTIONS+=("Open file in Vim editor")
    COMMAND_DESCRIPTIONS+=("Open file in Nano editor")
    COMMAND_DESCRIPTIONS+=("Make file executable")
    COMMAND_DESCRIPTIONS+=("Set permissions recursively")
    COMMAND_DESCRIPTIONS+=("Change file ownership")
    COMMAND_DESCRIPTIONS+=("Create symbolic link")
    COMMAND_DESCRIPTIONS+=("Find command location")
    COMMAND_DESCRIPTIONS+=("View command manual")

    # Make
    COMMAND_DESCRIPTIONS+=("Build release version")
    COMMAND_DESCRIPTIONS+=("Build debug version")
    COMMAND_DESCRIPTIONS+=("Run test suite")
    COMMAND_DESCRIPTIONS+=("Clean build artifacts")
    COMMAND_DESCRIPTIONS+=("Install to system")
    COMMAND_DESCRIPTIONS+=("Run development mode")
    COMMAND_DESCRIPTIONS+=("Run linter checks")
}

# =============================================================================
# Command Database
# =============================================================================

# Using indexed arrays for bash compatibility
declare -a COMMAND_KEYS=()
declare -a COMMAND_VALUES=()

init_commands() {
    # Git Commands
    COMMAND_KEYS+=("git_init"); COMMAND_VALUES+=("git init")
    COMMAND_KEYS+=("git_clone"); COMMAND_VALUES+=("git clone <repository-url>")
    COMMAND_KEYS+=("git_status"); COMMAND_VALUES+=("git status")
    COMMAND_KEYS+=("git_add_all"); COMMAND_VALUES+=("git add .")
    COMMAND_KEYS+=("git_commit"); COMMAND_VALUES+=("git commit -m \"<message>\"")
    COMMAND_KEYS+=("git_push"); COMMAND_VALUES+=("git push origin <branch>")
    COMMAND_KEYS+=("git_pull"); COMMAND_VALUES+=("git pull origin <branch>")
    COMMAND_KEYS+=("git_branch_new"); COMMAND_VALUES+=("git checkout -b <branch-name>")
    COMMAND_KEYS+=("git_branch_delete"); COMMAND_VALUES+=("git branch -d <branch-name>")
    COMMAND_KEYS+=("git_stash"); COMMAND_VALUES+=("git stash")
    COMMAND_KEYS+=("git_stash_pop"); COMMAND_VALUES+=("git stash pop")
    COMMAND_KEYS+=("git_log_pretty"); COMMAND_VALUES+=("git log --oneline --graph --all --decorate")
    COMMAND_KEYS+=("git_reset_soft"); COMMAND_VALUES+=("git reset --soft HEAD~1")
    COMMAND_KEYS+=("git_reset_hard"); COMMAND_VALUES+=("git reset --hard HEAD~1")
    COMMAND_KEYS+=("git_rebase_interactive"); COMMAND_VALUES+=("git rebase -i HEAD~<n>")
    COMMAND_KEYS+=("git_cherry_pick"); COMMAND_VALUES+=("git cherry-pick <commit-hash>")
    COMMAND_KEYS+=("git_merge"); COMMAND_VALUES+=("git merge <branch-name>")
    COMMAND_KEYS+=("git_remote_add"); COMMAND_VALUES+=("git remote add origin <repository-url>")
    COMMAND_KEYS+=("git_tags_list"); COMMAND_VALUES+=("git tag -l")
    COMMAND_KEYS+=("git_tag_create"); COMMAND_VALUES+=("git tag -a v1.0.0 -m \"Version 1.0.0\"")

    # Git Flow Commands (preferred workflow)
    COMMAND_KEYS+=("gitflow_feature_start"); COMMAND_VALUES+=("git flow feature start <feature-name>")
    COMMAND_KEYS+=("gitflow_feature_finish"); COMMAND_VALUES+=("git flow feature finish <feature-name>")
    COMMAND_KEYS+=("gitflow_feature_publish"); COMMAND_VALUES+=("git flow feature publish <feature-name>")
    COMMAND_KEYS+=("gitflow_feature_list"); COMMAND_VALUES+=("git flow feature list")
    COMMAND_KEYS+=("gitflow_release_start"); COMMAND_VALUES+=("git flow release start v<version>")
    COMMAND_KEYS+=("gitflow_release_finish"); COMMAND_VALUES+=("git flow release finish v<version>")
    COMMAND_KEYS+=("gitflow_hotfix_start"); COMMAND_VALUES+=("git flow hotfix start v<version>")
    COMMAND_KEYS+=("gitflow_hotfix_finish"); COMMAND_VALUES+=("git flow hotfix finish v<version>")

    # Docker Commands
    COMMAND_KEYS+=("docker_ps"); COMMAND_VALUES+=("docker ps")
    COMMAND_KEYS+=("docker_ps_all"); COMMAND_VALUES+=("docker ps -a")
    COMMAND_KEYS+=("docker_images"); COMMAND_VALUES+=("docker images")
    COMMAND_KEYS+=("docker_run"); COMMAND_VALUES+=("docker run -it <image>")
    COMMAND_KEYS+=("docker_build"); COMMAND_VALUES+=("docker build -t <tag> .")
    COMMAND_KEYS+=("docker_stop"); COMMAND_VALUES+=("docker stop <container>")
    COMMAND_KEYS+=("docker_rm"); COMMAND_VALUES+=("docker rm <container>")
    COMMAND_KEYS+=("docker_rmi"); COMMAND_VALUES+=("docker rmi <image>")
    COMMAND_KEYS+=("docker_exec"); COMMAND_VALUES+=("docker exec -it <container> /bin/bash")
    COMMAND_KEYS+=("docker_logs"); COMMAND_VALUES+=("docker logs -f <container>")
    COMMAND_KEYS+=("docker_compose_up"); COMMAND_VALUES+=("docker-compose up -d")
    COMMAND_KEYS+=("docker_compose_down"); COMMAND_VALUES+=("docker-compose down")
    COMMAND_KEYS+=("docker_prune_all"); COMMAND_VALUES+=("docker system prune -a")
    COMMAND_KEYS+=("docker_volume_ls"); COMMAND_VALUES+=("docker volume ls")
    COMMAND_KEYS+=("docker_network_ls"); COMMAND_VALUES+=("docker network ls")
    COMMAND_KEYS+=("docker_pull"); COMMAND_VALUES+=("docker pull <image>:latest")
    COMMAND_KEYS+=("docker_update_all"); COMMAND_VALUES+=("docker images --format '{{.Repository}}:{{.Tag}}' | xargs -L1 docker pull")

    # NPM/Node Commands
    COMMAND_KEYS+=("npm_init"); COMMAND_VALUES+=("npm init -y")
    COMMAND_KEYS+=("npm_install"); COMMAND_VALUES+=("npm install")
    COMMAND_KEYS+=("npm_install_package"); COMMAND_VALUES+=("npm install <package>")
    COMMAND_KEYS+=("npm_install_dev"); COMMAND_VALUES+=("npm install --save-dev <package>")
    COMMAND_KEYS+=("npm_uninstall"); COMMAND_VALUES+=("npm uninstall <package>")
    COMMAND_KEYS+=("npm_update"); COMMAND_VALUES+=("npm update")
    COMMAND_KEYS+=("npm_update_package"); COMMAND_VALUES+=("npm update <package>")
    COMMAND_KEYS+=("npm_audit"); COMMAND_VALUES+=("npm audit")
    COMMAND_KEYS+=("npm_audit_fix"); COMMAND_VALUES+=("npm audit fix")
    COMMAND_KEYS+=("npm_run_dev"); COMMAND_VALUES+=("npm run dev")
    COMMAND_KEYS+=("npm_run_build"); COMMAND_VALUES+=("npm run build")
    COMMAND_KEYS+=("npm_run_test"); COMMAND_VALUES+=("npm test")
    COMMAND_KEYS+=("npm_list"); COMMAND_VALUES+=("npm list --depth=0")
    COMMAND_KEYS+=("npm_outdated"); COMMAND_VALUES+=("npm outdated")
    COMMAND_KEYS+=("npm_self_update"); COMMAND_VALUES+=("npm install -g npm@latest")

    # Python/pip Commands
    COMMAND_KEYS+=("pip_install"); COMMAND_VALUES+=("pip install <package>")
    COMMAND_KEYS+=("pip_install_requirements"); COMMAND_VALUES+=("pip install -r requirements.txt")
    COMMAND_KEYS+=("pip_freeze"); COMMAND_VALUES+=("pip freeze > requirements.txt")
    COMMAND_KEYS+=("pip_list"); COMMAND_VALUES+=("pip list")
    COMMAND_KEYS+=("pip_uninstall"); COMMAND_VALUES+=("pip uninstall <package>")
    COMMAND_KEYS+=("pip_upgrade"); COMMAND_VALUES+=("pip install --upgrade <package>")
    COMMAND_KEYS+=("pip_upgrade_all"); COMMAND_VALUES+=("pip list --outdated --format=columns | tail -n +3 | awk '{print \$1}' | xargs -n1 pip install -U")
    COMMAND_KEYS+=("pip_outdated"); COMMAND_VALUES+=("pip list --outdated")
    COMMAND_KEYS+=("python_venv_create"); COMMAND_VALUES+=("python -m venv venv")
    COMMAND_KEYS+=("python_venv_activate"); COMMAND_VALUES+=("source venv/bin/activate")
    COMMAND_KEYS+=("python_venv_deactivate"); COMMAND_VALUES+=("deactivate")
    COMMAND_KEYS+=("python_server"); COMMAND_VALUES+=("python -m http.server 8000")

    # UV Commands (Fast Python Package Manager - https://docs.astral.sh/uv/)
    COMMAND_KEYS+=("uv_init"); COMMAND_VALUES+=("uv init <project-name>")
    COMMAND_KEYS+=("uv_add"); COMMAND_VALUES+=("uv add <package>")
    COMMAND_KEYS+=("uv_add_dev"); COMMAND_VALUES+=("uv add --dev <package>")
    COMMAND_KEYS+=("uv_remove"); COMMAND_VALUES+=("uv remove <package>")
    COMMAND_KEYS+=("uv_sync"); COMMAND_VALUES+=("uv sync")
    COMMAND_KEYS+=("uv_lock"); COMMAND_VALUES+=("uv lock")
    COMMAND_KEYS+=("uv_upgrade"); COMMAND_VALUES+=("uv lock --upgrade-package <package>")
    COMMAND_KEYS+=("uv_upgrade_all"); COMMAND_VALUES+=("uv lock --upgrade")
    COMMAND_KEYS+=("uv_run"); COMMAND_VALUES+=("uv run <script.py>")
    COMMAND_KEYS+=("uv_run_cmd"); COMMAND_VALUES+=("uv run -- <command>")
    COMMAND_KEYS+=("uv_venv"); COMMAND_VALUES+=("uv venv")
    COMMAND_KEYS+=("uv_pip_install"); COMMAND_VALUES+=("uv pip install <package>")
    COMMAND_KEYS+=("uv_pip_requirements"); COMMAND_VALUES+=("uv pip install -r requirements.txt")
    COMMAND_KEYS+=("uv_pip_compile"); COMMAND_VALUES+=("uv pip compile requirements.in -o requirements.txt")
    COMMAND_KEYS+=("uv_pip_list"); COMMAND_VALUES+=("uv pip list")
    COMMAND_KEYS+=("uv_pip_tree"); COMMAND_VALUES+=("uv pip tree")
    COMMAND_KEYS+=("uv_outdated"); COMMAND_VALUES+=("uv pip list --outdated")
    COMMAND_KEYS+=("uv_python_install"); COMMAND_VALUES+=("uv python install <version>")
    COMMAND_KEYS+=("uv_python_list"); COMMAND_VALUES+=("uv python list")
    COMMAND_KEYS+=("uv_python_pin"); COMMAND_VALUES+=("uv python pin <version>")
    COMMAND_KEYS+=("uv_build"); COMMAND_VALUES+=("uv build")
    COMMAND_KEYS+=("uv_tool_run"); COMMAND_VALUES+=("uvx <tool>")
    COMMAND_KEYS+=("uv_self_update"); COMMAND_VALUES+=("uv self update")

    # Yarn Commands (JavaScript/Node.js - https://yarnpkg.com/)
    COMMAND_KEYS+=("yarn_init"); COMMAND_VALUES+=("yarn init -y")
    COMMAND_KEYS+=("yarn_install"); COMMAND_VALUES+=("yarn install")
    COMMAND_KEYS+=("yarn_add"); COMMAND_VALUES+=("yarn add <package>")
    COMMAND_KEYS+=("yarn_add_dev"); COMMAND_VALUES+=("yarn add -D <package>")
    COMMAND_KEYS+=("yarn_remove"); COMMAND_VALUES+=("yarn remove <package>")
    COMMAND_KEYS+=("yarn_upgrade"); COMMAND_VALUES+=("yarn upgrade")
    COMMAND_KEYS+=("yarn_upgrade_package"); COMMAND_VALUES+=("yarn upgrade <package>")
    COMMAND_KEYS+=("yarn_outdated"); COMMAND_VALUES+=("yarn outdated")
    COMMAND_KEYS+=("yarn_run"); COMMAND_VALUES+=("yarn run <script>")
    COMMAND_KEYS+=("yarn_dlx"); COMMAND_VALUES+=("yarn dlx <package>")
    COMMAND_KEYS+=("yarn_self_update"); COMMAND_VALUES+=("yarn set version stable")

    # pnpm Commands (JavaScript/Node.js - https://pnpm.io/)
    COMMAND_KEYS+=("pnpm_init"); COMMAND_VALUES+=("pnpm init")
    COMMAND_KEYS+=("pnpm_install"); COMMAND_VALUES+=("pnpm install")
    COMMAND_KEYS+=("pnpm_add"); COMMAND_VALUES+=("pnpm add <package>")
    COMMAND_KEYS+=("pnpm_add_dev"); COMMAND_VALUES+=("pnpm add -D <package>")
    COMMAND_KEYS+=("pnpm_remove"); COMMAND_VALUES+=("pnpm remove <package>")
    COMMAND_KEYS+=("pnpm_update"); COMMAND_VALUES+=("pnpm update")
    COMMAND_KEYS+=("pnpm_update_package"); COMMAND_VALUES+=("pnpm update <package>")
    COMMAND_KEYS+=("pnpm_outdated"); COMMAND_VALUES+=("pnpm outdated")
    COMMAND_KEYS+=("pnpm_run"); COMMAND_VALUES+=("pnpm run <script>")
    COMMAND_KEYS+=("pnpm_dlx"); COMMAND_VALUES+=("pnpm dlx <package>")
    COMMAND_KEYS+=("pnpm_self_update"); COMMAND_VALUES+=("pnpm self-update")

    # Go Commands (golang - https://go.dev/)
    COMMAND_KEYS+=("go_mod_init"); COMMAND_VALUES+=("go mod init <module-name>")
    COMMAND_KEYS+=("go_get"); COMMAND_VALUES+=("go get <package>")
    COMMAND_KEYS+=("go_get_upgrade"); COMMAND_VALUES+=("go get -u <package>")
    COMMAND_KEYS+=("go_get_upgrade_all"); COMMAND_VALUES+=("go get -u ./...")
    COMMAND_KEYS+=("go_mod_tidy"); COMMAND_VALUES+=("go mod tidy")
    COMMAND_KEYS+=("go_mod_download"); COMMAND_VALUES+=("go mod download")
    COMMAND_KEYS+=("go_build"); COMMAND_VALUES+=("go build")
    COMMAND_KEYS+=("go_run"); COMMAND_VALUES+=("go run <file.go>")
    COMMAND_KEYS+=("go_test"); COMMAND_VALUES+=("go test ./...")
    COMMAND_KEYS+=("go_fmt"); COMMAND_VALUES+=("go fmt ./...")
    COMMAND_KEYS+=("go_vet"); COMMAND_VALUES+=("go vet ./...")
    COMMAND_KEYS+=("go_list_outdated"); COMMAND_VALUES+=("go list -m -u all")

    # Rust/Cargo Commands (https://doc.rust-lang.org/cargo/)
    COMMAND_KEYS+=("cargo_new"); COMMAND_VALUES+=("cargo new <project-name>")
    COMMAND_KEYS+=("cargo_init"); COMMAND_VALUES+=("cargo init")
    COMMAND_KEYS+=("cargo_add"); COMMAND_VALUES+=("cargo add <crate>")
    COMMAND_KEYS+=("cargo_add_dev"); COMMAND_VALUES+=("cargo add --dev <crate>")
    COMMAND_KEYS+=("cargo_update"); COMMAND_VALUES+=("cargo update")
    COMMAND_KEYS+=("cargo_update_package"); COMMAND_VALUES+=("cargo update -p <crate>")
    COMMAND_KEYS+=("cargo_build"); COMMAND_VALUES+=("cargo build")
    COMMAND_KEYS+=("cargo_build_release"); COMMAND_VALUES+=("cargo build --release")
    COMMAND_KEYS+=("cargo_run"); COMMAND_VALUES+=("cargo run")
    COMMAND_KEYS+=("cargo_test"); COMMAND_VALUES+=("cargo test")
    COMMAND_KEYS+=("cargo_fmt"); COMMAND_VALUES+=("cargo fmt")
    COMMAND_KEYS+=("cargo_clippy"); COMMAND_VALUES+=("cargo clippy")
    COMMAND_KEYS+=("cargo_check"); COMMAND_VALUES+=("cargo check")
    COMMAND_KEYS+=("cargo_outdated"); COMMAND_VALUES+=("cargo outdated")
    COMMAND_KEYS+=("rustup_update"); COMMAND_VALUES+=("rustup update")
    COMMAND_KEYS+=("rustup_self_update"); COMMAND_VALUES+=("rustup self update")

    # Ruby/Bundler Commands (https://bundler.io/)
    COMMAND_KEYS+=("bundle_init"); COMMAND_VALUES+=("bundle init")
    COMMAND_KEYS+=("bundle_install"); COMMAND_VALUES+=("bundle install")
    COMMAND_KEYS+=("gem_install"); COMMAND_VALUES+=("gem install <gem>")
    COMMAND_KEYS+=("bundle_add"); COMMAND_VALUES+=("bundle add <gem>")
    COMMAND_KEYS+=("bundle_update"); COMMAND_VALUES+=("bundle update")
    COMMAND_KEYS+=("bundle_update_gem"); COMMAND_VALUES+=("bundle update <gem>")
    COMMAND_KEYS+=("bundle_outdated"); COMMAND_VALUES+=("bundle outdated")
    COMMAND_KEYS+=("bundle_exec"); COMMAND_VALUES+=("bundle exec <command>")
    COMMAND_KEYS+=("ruby_run"); COMMAND_VALUES+=("ruby <file.rb>")
    COMMAND_KEYS+=("rake_test"); COMMAND_VALUES+=("rake test")
    COMMAND_KEYS+=("gem_update_system"); COMMAND_VALUES+=("gem update --system")

    # PHP/Composer Commands (https://getcomposer.org/)
    COMMAND_KEYS+=("composer_init"); COMMAND_VALUES+=("composer init")
    COMMAND_KEYS+=("composer_install"); COMMAND_VALUES+=("composer install")
    COMMAND_KEYS+=("composer_require"); COMMAND_VALUES+=("composer require <package>")
    COMMAND_KEYS+=("composer_require_dev"); COMMAND_VALUES+=("composer require --dev <package>")
    COMMAND_KEYS+=("composer_update"); COMMAND_VALUES+=("composer update")
    COMMAND_KEYS+=("composer_update_package"); COMMAND_VALUES+=("composer update <package>")
    COMMAND_KEYS+=("composer_outdated"); COMMAND_VALUES+=("composer outdated")
    COMMAND_KEYS+=("composer_remove"); COMMAND_VALUES+=("composer remove <package>")
    COMMAND_KEYS+=("php_run"); COMMAND_VALUES+=("php <file.php>")
    COMMAND_KEYS+=("phpunit_test"); COMMAND_VALUES+=("./vendor/bin/phpunit")
    COMMAND_KEYS+=("composer_dump"); COMMAND_VALUES+=("composer dump-autoload")
    COMMAND_KEYS+=("composer_self_update"); COMMAND_VALUES+=("composer self-update")

    # Java/Maven Commands (https://maven.apache.org/)
    COMMAND_KEYS+=("mvn_new"); COMMAND_VALUES+=("mvn archetype:generate -DgroupId=<group> -DartifactId=<artifact>")
    COMMAND_KEYS+=("mvn_compile"); COMMAND_VALUES+=("mvn compile")
    COMMAND_KEYS+=("mvn_test"); COMMAND_VALUES+=("mvn test")
    COMMAND_KEYS+=("mvn_package"); COMMAND_VALUES+=("mvn package")
    COMMAND_KEYS+=("mvn_install"); COMMAND_VALUES+=("mvn install")
    COMMAND_KEYS+=("mvn_clean"); COMMAND_VALUES+=("mvn clean")
    COMMAND_KEYS+=("mvn_deps"); COMMAND_VALUES+=("mvn dependency:tree")
    COMMAND_KEYS+=("mvn_outdated"); COMMAND_VALUES+=("mvn versions:display-dependency-updates")

    # Java/Gradle Commands (https://gradle.org/)
    COMMAND_KEYS+=("gradle_init"); COMMAND_VALUES+=("gradle init")
    COMMAND_KEYS+=("gradle_build"); COMMAND_VALUES+=("gradle build")
    COMMAND_KEYS+=("gradle_test"); COMMAND_VALUES+=("gradle test")
    COMMAND_KEYS+=("gradle_clean"); COMMAND_VALUES+=("gradle clean")
    COMMAND_KEYS+=("gradle_deps"); COMMAND_VALUES+=("gradle dependencies")
    COMMAND_KEYS+=("gradle_run"); COMMAND_VALUES+=("gradle run")

    # .NET Commands (https://dotnet.microsoft.com/)
    COMMAND_KEYS+=("dotnet_new"); COMMAND_VALUES+=("dotnet new <template>")
    COMMAND_KEYS+=("dotnet_restore"); COMMAND_VALUES+=("dotnet restore")
    COMMAND_KEYS+=("dotnet_build"); COMMAND_VALUES+=("dotnet build")
    COMMAND_KEYS+=("dotnet_run"); COMMAND_VALUES+=("dotnet run")
    COMMAND_KEYS+=("dotnet_test"); COMMAND_VALUES+=("dotnet test")
    COMMAND_KEYS+=("dotnet_add"); COMMAND_VALUES+=("dotnet add package <package>")
    COMMAND_KEYS+=("dotnet_outdated"); COMMAND_VALUES+=("dotnet list package --outdated")
    COMMAND_KEYS+=("dotnet_publish"); COMMAND_VALUES+=("dotnet publish -c Release")
    COMMAND_KEYS+=("dotnet_clean"); COMMAND_VALUES+=("dotnet clean")
    COMMAND_KEYS+=("dotnet_watch"); COMMAND_VALUES+=("dotnet watch run")

    # Swift/SPM Commands (https://swift.org/)
    COMMAND_KEYS+=("swift_init"); COMMAND_VALUES+=("swift package init")
    COMMAND_KEYS+=("swift_build"); COMMAND_VALUES+=("swift build")
    COMMAND_KEYS+=("swift_run"); COMMAND_VALUES+=("swift run")
    COMMAND_KEYS+=("swift_test"); COMMAND_VALUES+=("swift test")
    COMMAND_KEYS+=("swift_resolve"); COMMAND_VALUES+=("swift package resolve")
    COMMAND_KEYS+=("swift_update"); COMMAND_VALUES+=("swift package update")
    COMMAND_KEYS+=("swift_deps"); COMMAND_VALUES+=("swift package show-dependencies")
    COMMAND_KEYS+=("swift_clean"); COMMAND_VALUES+=("swift package clean")

    # File Operations
    COMMAND_KEYS+=("find_name"); COMMAND_VALUES+=("find . -name \"<pattern>\"")
    COMMAND_KEYS+=("find_type_file"); COMMAND_VALUES+=("find . -type f -name \"<pattern>\"")
    COMMAND_KEYS+=("find_modified"); COMMAND_VALUES+=("find . -mtime -<days>")
    COMMAND_KEYS+=("grep_recursive"); COMMAND_VALUES+=("grep -r \"<pattern>\" .")
    COMMAND_KEYS+=("grep_case_insensitive"); COMMAND_VALUES+=("grep -i \"<pattern>\" <file>")
    COMMAND_KEYS+=("tar_create"); COMMAND_VALUES+=("tar -czf archive.tar.gz <directory>")
    COMMAND_KEYS+=("tar_extract"); COMMAND_VALUES+=("tar -xzf archive.tar.gz")
    COMMAND_KEYS+=("zip_create"); COMMAND_VALUES+=("zip -r archive.zip <directory>")
    COMMAND_KEYS+=("unzip_extract"); COMMAND_VALUES+=("unzip archive.zip")
    COMMAND_KEYS+=("rsync_local"); COMMAND_VALUES+=("rsync -avh <source> <destination>")
    COMMAND_KEYS+=("rsync_remote"); COMMAND_VALUES+=("rsync -avzh <source> user@host:<destination>")

    # Text Replacement (sed/awk) - Note: macOS uses -i '', Linux uses -i
    COMMAND_KEYS+=("sed_replace"); COMMAND_VALUES+=("sed -i '' 's/<old-string>/<new-string>/g' <file>")
    COMMAND_KEYS+=("sed_regex"); COMMAND_VALUES+=("sed -i '' 's/<regex-pattern>/<replacement>/g' <file>")
    COMMAND_KEYS+=("sed_recursive"); COMMAND_VALUES+=("find . -type f -name \"<file-pattern>\" -exec sed -i '' 's/<old>/<new>/g' {} +")
    COMMAND_KEYS+=("sed_preview"); COMMAND_VALUES+=("sed 's/<old>/<new>/g' <file>")
    COMMAND_KEYS+=("sed_backup"); COMMAND_VALUES+=("sed -i '.bak' 's/<old>/<new>/g' <file>")
    COMMAND_KEYS+=("sed_delete_lines"); COMMAND_VALUES+=("sed -i '' '/<pattern>/d' <file>")
    COMMAND_KEYS+=("sed_conditional"); COMMAND_VALUES+=("sed -i '' '/<line-match>/s/<old>/<new>/g' <file>")
    COMMAND_KEYS+=("sed_nth"); COMMAND_VALUES+=("sed -i '' 's/<old>/<new>/<n>' <file>")
    COMMAND_KEYS+=("sed_case_insensitive"); COMMAND_VALUES+=("sed -i '' 's/<old>/<new>/gI' <file>")
    COMMAND_KEYS+=("awk_replace"); COMMAND_VALUES+=("awk '{gsub(/<old>/,\"<new>\")}1' <file> > tmp && mv tmp <file>")
    COMMAND_KEYS+=("sed_show_changes"); COMMAND_VALUES+=("sed -n 's/<old>/<new>/gp' <file>")
    COMMAND_KEYS+=("sed_find_replace"); COMMAND_VALUES+=("grep -rl '<old>' . | xargs sed -i '' 's/<old>/<new>/g'")

    # Network Commands
    COMMAND_KEYS+=("curl_get"); COMMAND_VALUES+=("curl -X GET <url>")
    COMMAND_KEYS+=("curl_post"); COMMAND_VALUES+=("curl -X POST -H \"Content-Type: application/json\" -d '{\"key\":\"value\"}' <url>")
    COMMAND_KEYS+=("curl_download"); COMMAND_VALUES+=("curl -O <url>")
    COMMAND_KEYS+=("wget_download"); COMMAND_VALUES+=("wget <url>")
    COMMAND_KEYS+=("netstat_ports"); COMMAND_VALUES+=("netstat -an | grep LISTEN")
    COMMAND_KEYS+=("lsof_port"); COMMAND_VALUES+=("lsof -i :<port>")
    COMMAND_KEYS+=("kill_port"); COMMAND_VALUES+=("kill -9 \$(lsof -t -i:<port>)")
    COMMAND_KEYS+=("ping_host"); COMMAND_VALUES+=("ping -c 4 <host>")
    COMMAND_KEYS+=("traceroute"); COMMAND_VALUES+=("traceroute <host>")
    COMMAND_KEYS+=("dns_lookup"); COMMAND_VALUES+=("nslookup <domain>")
    COMMAND_KEYS+=("ssh_connect"); COMMAND_VALUES+=("ssh user@host")
    COMMAND_KEYS+=("ssh_copy_id"); COMMAND_VALUES+=("ssh-copy-id user@host")
    COMMAND_KEYS+=("scp_upload"); COMMAND_VALUES+=("scp <local-file> user@host:<remote-path>")
    COMMAND_KEYS+=("scp_download"); COMMAND_VALUES+=("scp user@host:<remote-file> <local-path>")

    # Process Management
    COMMAND_KEYS+=("ps_aux"); COMMAND_VALUES+=("ps aux | grep <process>")
    COMMAND_KEYS+=("kill_process"); COMMAND_VALUES+=("kill -9 <pid>")
    COMMAND_KEYS+=("top_cpu"); COMMAND_VALUES+=("top -o cpu")
    COMMAND_KEYS+=("htop"); COMMAND_VALUES+=("htop")
    COMMAND_KEYS+=("jobs_list"); COMMAND_VALUES+=("jobs -l")
    COMMAND_KEYS+=("bg_job"); COMMAND_VALUES+=("bg %<job-number>")
    COMMAND_KEYS+=("fg_job"); COMMAND_VALUES+=("fg %<job-number>")

    # Database Commands
    COMMAND_KEYS+=("mysql_connect"); COMMAND_VALUES+=("mysql -u <user> -p")
    COMMAND_KEYS+=("mysql_dump"); COMMAND_VALUES+=("mysqldump -u <user> -p <database> > backup.sql")
    COMMAND_KEYS+=("mysql_import"); COMMAND_VALUES+=("mysql -u <user> -p <database> < backup.sql")
    COMMAND_KEYS+=("psql_connect"); COMMAND_VALUES+=("psql -U <user> -d <database>")
    COMMAND_KEYS+=("psql_dump"); COMMAND_VALUES+=("pg_dump -U <user> <database> > backup.sql")
    COMMAND_KEYS+=("psql_restore"); COMMAND_VALUES+=("psql -U <user> <database> < backup.sql")
    COMMAND_KEYS+=("redis_cli"); COMMAND_VALUES+=("redis-cli")
    COMMAND_KEYS+=("mongo_connect"); COMMAND_VALUES+=("mongo")

    # macOS Specific
    COMMAND_KEYS+=("brew_install"); COMMAND_VALUES+=("brew install <package>")
    COMMAND_KEYS+=("brew_uninstall"); COMMAND_VALUES+=("brew uninstall <package>")
    COMMAND_KEYS+=("brew_update"); COMMAND_VALUES+=("brew update")
    COMMAND_KEYS+=("brew_upgrade"); COMMAND_VALUES+=("brew upgrade")
    COMMAND_KEYS+=("brew_upgrade_package"); COMMAND_VALUES+=("brew upgrade <package>")
    COMMAND_KEYS+=("brew_outdated"); COMMAND_VALUES+=("brew outdated")
    COMMAND_KEYS+=("brew_list"); COMMAND_VALUES+=("brew list")
    COMMAND_KEYS+=("brew_search"); COMMAND_VALUES+=("brew search <package>")
    COMMAND_KEYS+=("brew_info"); COMMAND_VALUES+=("brew info <package>")
    COMMAND_KEYS+=("open_finder"); COMMAND_VALUES+=("open .")
    COMMAND_KEYS+=("open_app"); COMMAND_VALUES+=("open -a <application>")
    COMMAND_KEYS+=("pbcopy"); COMMAND_VALUES+=("<command> | pbcopy")
    COMMAND_KEYS+=("pbpaste"); COMMAND_VALUES+=("pbpaste")
    COMMAND_KEYS+=("say_text"); COMMAND_VALUES+=("say \"<text>\"")

    # Development Tools
    COMMAND_KEYS+=("vscode_open"); COMMAND_VALUES+=("code .")
    COMMAND_KEYS+=("vscode_diff"); COMMAND_VALUES+=("code --diff <file1> <file2>")
    COMMAND_KEYS+=("vim_open"); COMMAND_VALUES+=("vim <file>")
    COMMAND_KEYS+=("nano_open"); COMMAND_VALUES+=("nano <file>")
    COMMAND_KEYS+=("chmod_executable"); COMMAND_VALUES+=("chmod +x <file>")
    COMMAND_KEYS+=("chmod_recursive"); COMMAND_VALUES+=("chmod -R 755 <directory>")
    COMMAND_KEYS+=("chown_user"); COMMAND_VALUES+=("chown <user>:<group> <file>")
    COMMAND_KEYS+=("ln_symbolic"); COMMAND_VALUES+=("ln -s <target> <link>")
    COMMAND_KEYS+=("which_command"); COMMAND_VALUES+=("which <command>")
    COMMAND_KEYS+=("man_page"); COMMAND_VALUES+=("man <command>")

    # Make Commands (RSR preferred build system)
    COMMAND_KEYS+=("make_build"); COMMAND_VALUES+=("make build")
    COMMAND_KEYS+=("make_build_debug"); COMMAND_VALUES+=("make build-debug")
    COMMAND_KEYS+=("make_test"); COMMAND_VALUES+=("make test")
    COMMAND_KEYS+=("make_clean"); COMMAND_VALUES+=("make clean")
    COMMAND_KEYS+=("make_install"); COMMAND_VALUES+=("make install")
    COMMAND_KEYS+=("make_dev"); COMMAND_VALUES+=("make dev")
    COMMAND_KEYS+=("make_lint"); COMMAND_VALUES+=("make lint")
}

# Category definitions
declare -a CATEGORIES=(
    "Git:git_*"
    "Git Flow:gitflow_*"
    "Docker:docker_*"
    "NPM/Node:npm_*"
    "Yarn:yarn_*"
    "pnpm:pnpm_*"
    "Python/pip:pip_*,python_*"
    "UV (Python):uv_*"
    "Go:go_*"
    "Rust/Cargo:cargo_*"
    "Ruby/Bundler:gem_*,bundle_*,ruby_*,rake_*"
    "PHP/Composer:composer_*,php_*,phpunit_*"
    "Java/Maven:mvn_*"
    "Java/Gradle:gradle_*"
    ".NET:dotnet_*"
    "Swift:swift_*"
    "File Operations:find_*,grep_*,tar_*,zip_*,unzip_*,rsync_*,sed_*,awk_*"
    "Network:curl_*,wget_*,netstat_*,lsof_*,ping_*,ssh_*,scp_*,traceroute,dns_*,kill_port"
    "Process Management:ps_*,kill_*,top_*,htop,jobs_*,bg_*,fg_*"
    "Database:mysql_*,psql_*,redis_*,mongo_*"
    "macOS/Homebrew:brew_*,open_*,pbcopy,pbpaste,say_*"
    "Development Tools:vscode_*,vim_*,nano_*,chmod_*,chown_*,ln_*,which_*,man_*"
    "Make/Build:make_*"
)

# =============================================================================
# Utility Functions
# =============================================================================

get_command_by_key() {
    local search_key="$1"
    for i in "${!COMMAND_KEYS[@]}"; do
        if [[ "${COMMAND_KEYS[$i]}" == "$search_key" ]]; then
            echo "${COMMAND_VALUES[$i]}"
            return 0
        fi
    done
    # Check custom commands
    if [[ -f "$CUSTOM_COMMANDS_FILE" ]]; then
        local custom_cmd
        custom_cmd=$(grep "^${search_key}|" "$CUSTOM_COMMANDS_FILE" 2>/dev/null | cut -d'|' -f2)
        if [[ -n "$custom_cmd" ]]; then
            echo "$custom_cmd"
            return 0
        fi
    fi
    # Check aliases
    if [[ -f "$ALIASES_FILE" ]]; then
        local aliased_key
        aliased_key=$(grep "^${search_key}=" "$ALIASES_FILE" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$aliased_key" ]]; then
            get_command_by_key "$aliased_key"
            return $?
        fi
    fi
    return 1
}

get_command_index() {
    local search_key="$1"
    for i in "${!COMMAND_KEYS[@]}"; do
        if [[ "${COMMAND_KEYS[$i]}" == "$search_key" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

get_description_by_key() {
    local search_key="$1"
    local idx
    idx=$(get_command_index "$search_key")
    if [[ -n "$idx" ]] && [[ ${#COMMAND_DESCRIPTIONS[@]} -gt $idx ]]; then
        echo "${COMMAND_DESCRIPTIONS[$idx]}"
        return 0
    fi
    # Check custom commands for description
    if [[ -f "$CUSTOM_COMMANDS_FILE" ]]; then
        local desc
        desc=$(grep "^${search_key}|" "$CUSTOM_COMMANDS_FILE" 2>/dev/null | cut -d'|' -f3)
        if [[ -n "$desc" ]]; then
            echo "$desc"
            return 0
        fi
    fi
    echo "No description available"
}

print_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}  ${BOLD}${WHITE}Command Reference${RESET} - ${GREEN}Interactive Developer Tool${RESET}             ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}  ${DIM}Part of Remote Script Runner (RSR)${RESET}                            ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET}  ${YELLOW}Version ${SCRIPT_VERSION}${RESET}                                                    ${CYAN}║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

copy_to_clipboard() {
    local content="$1"
    local silent="${2:-false}"
    if command -v pbcopy &>/dev/null; then
        echo -n "$content" | pbcopy
        [[ "$silent" != "true" ]] && log_ok "Command copied to clipboard!"
        return 0
    elif command -v xclip &>/dev/null; then
        echo -n "$content" | xclip -selection clipboard
        [[ "$silent" != "true" ]] && log_ok "Command copied to clipboard!"
        return 0
    elif command -v xsel &>/dev/null; then
        echo -n "$content" | xsel --clipboard --input
        [[ "$silent" != "true" ]] && log_ok "Command copied to clipboard!"
        return 0
    else
        [[ "$silent" != "true" ]] && log_warn "Clipboard not available. Command:"
        [[ "$silent" != "true" ]] && echo "  $content"
        return 1
    fi
}

add_to_history() {
    local command="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $command" >> "$HISTORY_FILE"
    # Trim history to max entries
    if [[ $(wc -l < "$HISTORY_FILE") -gt $MAX_HISTORY_ENTRIES ]]; then
        tail -n "$MAX_HISTORY_ENTRIES" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"
        mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    fi
}

add_to_favorites() {
    local key="$1"
    if ! grep -q "^$key$" "$FAVORITES_FILE" 2>/dev/null; then
        echo "$key" >> "$FAVORITES_FILE"
        log_ok "Added to favorites!"
    else
        log_info "Already in favorites"
    fi
}

remove_from_favorites() {
    local key="$1"
    if grep -q "^$key$" "$FAVORITES_FILE" 2>/dev/null; then
        grep -v "^$key$" "$FAVORITES_FILE" > "${FAVORITES_FILE}.tmp"
        mv "${FAVORITES_FILE}.tmp" "$FAVORITES_FILE"
        log_ok "Removed from favorites"
        return 0
    fi
    return 1
}

# =============================================================================
# View Favorites
# =============================================================================

view_favorites() {
    if [[ ! -s "$FAVORITES_FILE" ]]; then
        log_warn "No favorites yet!"
        sleep 2
        return
    fi

    while true; do
        print_header
        echo -e "${BOLD}${GREEN}⭐ Your Favorites${RESET}"
        echo "────────────────────────────────"
        echo

        local favorites=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && favorites+=("$line") || true
        done < "$FAVORITES_FILE"

        local count=1
        for key in "${favorites[@]}"; do
            local display_key="${key//_/ }"
            local cmd
            cmd=$(get_command_by_key "$key" 2>/dev/null || echo "?")
            local desc
            desc=$(get_description_by_key "$key" 2>/dev/null || echo "")
            echo -e "${YELLOW}[$count]${RESET} ${GREEN}${display_key}${RESET}"
            echo -e "    └─ ${WHITE}${cmd}${RESET}"
            [[ -n "$desc" && "$desc" != "No description available" ]] && echo -e "       ${DIM}${desc}${RESET}" || true
            ((count++))
        done

        echo
        echo -e "${CYAN}Actions:${RESET}"
        echo -e "  ${YELLOW}[1-${#favorites[@]}]${RESET} Select command"
        echo -e "  ${YELLOW}[d]${RESET} Delete a favorite"
        echo -e "  ${YELLOW}[c]${RESET} Clear all favorites"
        echo -e "  ${YELLOW}[b]${RESET} Back to main menu"
        echo -e "  ${YELLOW}[q]${RESET} Quit"
        echo

        read -rp "Select: " choice

        case "$choice" in
            b|B)
                return
                ;;
            c|C)
                read -rn 1 -p "Clear all favorites? (y/N) " confirm
                echo
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    : > "$FAVORITES_FILE"
                    log_ok "Favorites cleared!"
                    sleep 1
                    return
                fi
                ;;
            d|D)
                read -rp "Enter number to delete: " del_num
                if [[ "$del_num" =~ ^[0-9]+$ ]] && [[ "$del_num" -ge 1 ]] && [[ "$del_num" -le ${#favorites[@]} ]]; then
                    local del_idx=$((del_num - 1))
                    local del_key="${favorites[$del_idx]}"
                    remove_from_favorites "$del_key"
                    # Check if any favorites left
                    if [[ ! -s "$FAVORITES_FILE" ]]; then
                        log_info "No more favorites"
                        sleep 1
                        return
                    fi
                else
                    log_error "Invalid number"
                    sleep 1
                fi
                ;;
            q|Q)
                exit 0
                ;;
            [0-9]*)
                if [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#favorites[@]} ]]; then
                    local idx=$((choice - 1))
                    display_command "${favorites[$idx]}"
                else
                    log_error "Invalid selection"
                    sleep 1
                fi
                ;;
            *)
                log_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# View History
# =============================================================================

view_history() {
    if [[ ! -s "$HISTORY_FILE" ]]; then
        log_warn "No history yet!"
        sleep 2
        return
    fi

    while true; do
        print_header
        echo -e "${BOLD}${GREEN}📜 Command History${RESET}"
        echo "────────────────────────────────"
        echo

        # Read last 20 entries
        local history_entries=()
        local history_cmds=()
        while IFS='|' read -r timestamp cmd; do
            cmd="${cmd## }"  # Trim leading space
            [[ -n "$cmd" ]] && { history_entries+=("$timestamp|$cmd"); history_cmds+=("$cmd"); } || true
        done < <(tail -n 20 "$HISTORY_FILE" 2>/dev/null || true)

        if [[ ${#history_entries[@]} -eq 0 ]]; then
            log_info "No history entries found"
            sleep 2
            return
        fi

        local count=1
        for entry in "${history_entries[@]}"; do
            local timestamp="${entry%%|*}"
            local cmd="${entry#*|}"
            echo -e "${YELLOW}[$count]${RESET} ${DIM}${timestamp}${RESET}"
            echo -e "    └─ ${WHITE}${cmd}${RESET}"
            ((count++))
        done

        echo
        echo -e "${CYAN}Actions:${RESET}"
        echo -e "  ${YELLOW}[1-${#history_cmds[@]}]${RESET} Copy command to clipboard"
        echo -e "  ${YELLOW}[a]${RESET} Add command from history as custom command"
        echo -e "  ${YELLOW}[r]${RESET} Re-run a command from history"
        echo -e "  ${YELLOW}[c]${RESET} Clear all history"
        echo -e "  ${YELLOW}[b]${RESET} Back to menu"
        echo -e "  ${YELLOW}[q]${RESET} Quit"
        echo

        read -rp "Select: " choice

        case "$choice" in
            b|B)
                return
                ;;
            c|C)
                read -rn 1 -p "Clear all history? (y/N) " confirm
                echo
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    : > "$HISTORY_FILE"
                    log_ok "History cleared!"
                    sleep 1
                    return
                fi
                ;;
            a|A)
                add_command_from_history "${history_cmds[@]}"
                ;;
            r|R)
                rerun_command_from_history "${history_cmds[@]}"
                ;;
            q|Q)
                exit 0
                ;;
            [0-9]*)
                if [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#history_cmds[@]} ]]; then
                    local idx=$((choice - 1))
                    local selected_cmd="${history_cmds[$idx]}"
                    copy_to_clipboard "$selected_cmd"
                    echo
                    read -rn 1 -p "Press any key to continue..."
                else
                    log_error "Invalid selection"
                    sleep 1
                fi
                ;;
            *)
                log_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# Add Command from History
# =============================================================================

add_command_from_history() {
    local history_cmds=("$@")

    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${GREEN}Add Command from History${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo

    # Show numbered list
    local count=1
    for cmd in "${history_cmds[@]}"; do
        echo -e "${YELLOW}[$count]${RESET} ${WHITE}${cmd}${RESET}"
        ((count++))
    done

    echo
    read -rp "Select command number (or Enter to cancel): " selection

    if [[ -z "$selection" ]]; then
        log_info "Cancelled"
        sleep 1
        return
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#history_cmds[@]} ]]; then
        log_error "Invalid selection"
        sleep 1
        return
    fi

    local idx=$((selection - 1))
    local selected_cmd="${history_cmds[$idx]}"

    echo
    echo -e "Selected: ${WHITE}${selected_cmd}${RESET}"
    echo

    # Auto-suggest a key name based on the command
    local suggested_key=""
    case "$selected_cmd" in
        git\ *) suggested_key="my_git_$(echo "${selected_cmd#git }" | cut -d' ' -f1 | tr '-' '_')" ;;
        docker\ *) suggested_key="my_docker_$(echo "${selected_cmd#docker }" | cut -d' ' -f1)" ;;
        npm\ *) suggested_key="my_npm_$(echo "${selected_cmd#npm }" | cut -d' ' -f1)" ;;
        make\ *) suggested_key="my_make_$(echo "${selected_cmd#make }" | cut -d' ' -f1)" ;;
        *) suggested_key="my_custom_cmd" ;;
    esac
    # Clean up suggested key
    suggested_key=$(echo "$suggested_key" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_' | head -c 30)

    read -rp "Command key [${suggested_key}]: " key
    key="${key:-$suggested_key}"

    if [[ -z "$key" ]]; then
        log_error "Key is required"
        sleep 1
        return
    fi

    # Validate key format
    if [[ ! "$key" =~ ^[a-z][a-z0-9_]*$ ]]; then
        log_error "Key must start with letter and contain only lowercase letters, numbers, underscores"
        sleep 2
        return
    fi

    # Check if key exists
    if get_command_by_key "$key" &>/dev/null; then
        log_error "Command key '$key' already exists"
        sleep 1
        return
    fi

    read -rp "Description (optional): " desc
    desc="${desc:-Command saved from history}"

    read -rp "Category [Custom]: " category
    category="${category:-Custom}"

    # Add to custom commands file
    echo "${key}|${selected_cmd}|${desc}|${category}" >> "$CUSTOM_COMMANDS_FILE"

    # Add to current session
    COMMAND_KEYS+=("$key")
    COMMAND_VALUES+=("$selected_cmd")
    COMMAND_DESCRIPTIONS+=("$desc")

    echo
    log_ok "Command saved as '${key}'!"
    echo
    echo -e "  ${CYAN}Search:${RESET} cmdref --search ${key}"
    echo -e "  ${CYAN}Copy:${RESET}   cmdref --copy ${key}"
    echo

    read -rn 1 -p "Press any key to continue..."
}

# =============================================================================
# Re-run Command from History
# =============================================================================

rerun_command_from_history() {
    local history_cmds=("$@")

    echo
    read -rp "Select command number to re-run: " selection

    if [[ -z "$selection" ]]; then
        return
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#history_cmds[@]} ]]; then
        log_error "Invalid selection"
        sleep 1
        return
    fi

    local idx=$((selection - 1))
    local selected_cmd="${history_cmds[$idx]}"

    echo
    echo -e "${YELLOW}Command:${RESET} ${WHITE}${selected_cmd}${RESET}"
    echo
    read -rn 1 -p "Execute this command? (y/N) " confirm
    echo

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Executing: $selected_cmd"
        echo
        eval "$selected_cmd"
        add_to_history "$selected_cmd"
        echo
        read -rn 1 -p "Press any key to continue..."
    fi
}

# =============================================================================
# Usage Statistics
# =============================================================================

update_stats() {
    local key="$1"
    if [[ ! -f "$STATS_FILE" ]]; then
        echo '{"commands":{}}' > "$STATS_FILE"
    fi

    # Simple stats update using sed (no jq dependency)
    local current_count=0
    if grep -q "\"$key\":" "$STATS_FILE" 2>/dev/null; then
        current_count=$(grep -o "\"$key\":[0-9]*" "$STATS_FILE" | cut -d':' -f2)
        ((current_count++))
        sed -i.bak "s/\"$key\":[0-9]*/\"$key\":$current_count/" "$STATS_FILE"
        rm -f "${STATS_FILE}.bak"
    else
        # Add new entry
        sed -i.bak "s/\"commands\":{/\"commands\":{\"$key\":1,/" "$STATS_FILE"
        # Clean up empty comma if first entry
        sed -i.bak 's/:{",/:{"/g' "$STATS_FILE"
        rm -f "${STATS_FILE}.bak"
    fi
}

get_top_commands() {
    local limit="${1:-10}"
    if [[ ! -f "$STATS_FILE" ]]; then
        return
    fi

    # Parse stats and sort by count
    grep -oE '"[^"]+\":[0-9]+' "$STATS_FILE" 2>/dev/null | \
        sed 's/"//g' | \
        sort -t':' -k2 -nr | \
        head -n "$limit"
}

show_stats() {
    print_header
    echo -e "${BOLD}${GREEN}Usage Statistics${RESET}"
    echo "────────────────────────────────"
    echo

    local top_cmds
    top_cmds=$(get_top_commands 15)

    if [[ -z "$top_cmds" ]]; then
        log_info "No usage statistics yet. Start using commands!"
        echo
        read -rn 1 -p "Press any key to continue..."
        return
    fi

    echo -e "${CYAN}Top 15 Most Used Commands:${RESET}"
    echo

    local rank=1
    while IFS=':' read -r key count; do
        local display_key="${key//_/ }"
        local cmd
        cmd=$(get_command_by_key "$key" 2>/dev/null || echo "")
        printf "${YELLOW}%2d.${RESET} ${GREEN}%-25s${RESET} ${DIM}(used %d times)${RESET}\n" "$rank" "$display_key" "$count"
        if [[ -n "$cmd" ]]; then
            echo -e "    └─ ${WHITE}${cmd}${RESET}"
        fi
        ((rank++))
    done <<< "$top_cmds"

    echo
    read -rn 1 -p "Press any key to continue..."
}

# =============================================================================
# Custom Commands
# =============================================================================

load_custom_commands() {
    if [[ ! -f "$CUSTOM_COMMANDS_FILE" ]]; then
        return
    fi

    while IFS='|' read -r key cmd desc category; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ || -z "$key" || "$key" == "commands:"* ]] && continue

        COMMAND_KEYS+=("$key")
        COMMAND_VALUES+=("$cmd")
        COMMAND_DESCRIPTIONS+=("${desc:-Custom command}")
    done < <(grep -v '^#' "$CUSTOM_COMMANDS_FILE" 2>/dev/null | grep -v '^commands:' 2>/dev/null | grep '|' 2>/dev/null || true)
}

add_custom_command() {
    print_header
    echo -e "${BOLD}${GREEN}Add Custom Command${RESET}"
    echo "────────────────────────────────"
    echo

    read -rp "Command key (e.g., my_deploy): " key
    if [[ -z "$key" ]]; then
        log_error "Key is required"
        sleep 1
        return
    fi

    # Validate key format
    if [[ ! "$key" =~ ^[a-z][a-z0-9_]*$ ]]; then
        log_error "Key must start with letter and contain only lowercase letters, numbers, underscores"
        sleep 2
        return
    fi

    # Check if key exists
    if get_command_by_key "$key" &>/dev/null; then
        log_error "Command key '$key' already exists"
        sleep 1
        return
    fi

    read -rp "Command: " cmd
    if [[ -z "$cmd" ]]; then
        log_error "Command is required"
        sleep 1
        return
    fi

    read -rp "Description: " desc
    read -rp "Category (default: Custom): " category
    category="${category:-Custom}"

    echo "${key}|${cmd}|${desc}|${category}" >> "$CUSTOM_COMMANDS_FILE"

    # Add to current session
    COMMAND_KEYS+=("$key")
    COMMAND_VALUES+=("$cmd")
    COMMAND_DESCRIPTIONS+=("${desc:-Custom command}")

    log_ok "Custom command added successfully!"
    echo
    echo -e "Use it with: ${CYAN}cmdref --search ${key}${RESET}"
    echo -e "Or copy directly: ${CYAN}cmdref --copy ${key}${RESET}"

    sleep 2
}

list_custom_commands() {
    print_header
    echo -e "${BOLD}${GREEN}Custom Commands${RESET}"
    echo "────────────────────────────────"
    echo

    if [[ ! -f "$CUSTOM_COMMANDS_FILE" ]] || ! grep -q '|' "$CUSTOM_COMMANDS_FILE" 2>/dev/null; then
        log_info "No custom commands yet."
        echo
        echo -e "Add one with: ${CYAN}cmdref --add${RESET}"
        echo
        read -rn 1 -p "Press any key to continue..."
        return
    fi

    local count=1
    while IFS='|' read -r key cmd desc category; do
        [[ "$key" =~ ^#.*$ || -z "$key" || "$key" == "commands:"* ]] && continue

        echo -e "${YELLOW}[$count]${RESET} ${GREEN}${key//_/ }${RESET} ${DIM}[${category:-Custom}]${RESET}"
        echo -e "    Command: ${WHITE}${cmd}${RESET}"
        [[ -n "$desc" ]] && echo -e "    ${DIM}${desc}${RESET}" || true
        echo
        ((count++)) || true
    done < <(grep -v '^#' "$CUSTOM_COMMANDS_FILE" 2>/dev/null | grep -v '^commands:' 2>/dev/null | grep '|' 2>/dev/null || true)

    echo
    echo -e "${YELLOW}[a]${RESET} Add new custom command"
    echo -e "${YELLOW}[d]${RESET} Delete a custom command"
    echo -e "${YELLOW}[b]${RESET} Back to menu"
    echo

    read -rn 1 -p "Choose action: " action
    echo

    case "$action" in
        a|A)
            add_custom_command
            ;;
        d|D)
            delete_custom_command
            ;;
    esac
}

delete_custom_command() {
    read -rp "Enter command key to delete: " key
    if [[ -z "$key" ]]; then
        return
    fi

    if grep -q "^${key}|" "$CUSTOM_COMMANDS_FILE" 2>/dev/null; then
        grep -v "^${key}|" "$CUSTOM_COMMANDS_FILE" > "${CUSTOM_COMMANDS_FILE}.tmp"
        mv "${CUSTOM_COMMANDS_FILE}.tmp" "$CUSTOM_COMMANDS_FILE"
        log_ok "Custom command '$key' deleted"
    else
        log_error "Custom command '$key' not found"
    fi
    sleep 1
}

# =============================================================================
# Aliases
# =============================================================================

add_alias() {
    local alias_name="$1"
    local target_key="$2"

    if [[ -z "$alias_name" || -z "$target_key" ]]; then
        print_header
        echo -e "${BOLD}${GREEN}Create Command Alias${RESET}"
        echo "────────────────────────────────"
        echo
        read -rp "Alias name (short name): " alias_name
        read -rp "Target command key: " target_key
    fi

    if [[ -z "$alias_name" || -z "$target_key" ]]; then
        log_error "Both alias name and target key are required"
        sleep 1
        return 1
    fi

    # Verify target exists
    if ! get_command_by_key "$target_key" &>/dev/null; then
        log_error "Target command '$target_key' not found"
        sleep 1
        return 1
    fi

    # Remove existing alias if present
    grep -v "^${alias_name}=" "$ALIASES_FILE" > "${ALIASES_FILE}.tmp" 2>/dev/null || true
    mv "${ALIASES_FILE}.tmp" "$ALIASES_FILE" 2>/dev/null || true

    echo "${alias_name}=${target_key}" >> "$ALIASES_FILE"
    log_ok "Alias '${alias_name}' -> '${target_key}' created"
    sleep 1
}

list_aliases() {
    print_header
    echo -e "${BOLD}${GREEN}Command Aliases${RESET}"
    echo "────────────────────────────────"
    echo

    if [[ ! -s "$ALIASES_FILE" ]]; then
        log_info "No aliases defined yet."
        echo
        echo -e "Create one with: ${CYAN}cmdref --alias myshort=git_commit${RESET}"
        echo
        read -rn 1 -p "Press any key to continue..."
        return
    fi

    while IFS='=' read -r alias_name target_key; do
        [[ -z "$alias_name" ]] && continue
        local cmd
        cmd=$(get_command_by_key "$target_key" 2>/dev/null || echo "?")
        echo -e "${GREEN}${alias_name}${RESET} → ${YELLOW}${target_key}${RESET}"
        echo -e "  └─ ${WHITE}${cmd}${RESET}"
        echo
    done < "$ALIASES_FILE"

    echo
    read -rn 1 -p "Press any key to continue..."
}

# =============================================================================
# Export/Import
# =============================================================================

export_config() {
    local export_file="${1:-cmdref_export_$(date +%Y%m%d_%H%M%S).tar.gz}"

    local temp_dir
    temp_dir=$(mktemp -d)

    # Copy config files
    cp "$FAVORITES_FILE" "$temp_dir/" 2>/dev/null || true
    cp "$CUSTOM_COMMANDS_FILE" "$temp_dir/" 2>/dev/null || true
    cp "$ALIASES_FILE" "$temp_dir/" 2>/dev/null || true
    cp "$STATS_FILE" "$temp_dir/" 2>/dev/null || true

    # Create archive
    tar -czf "$export_file" -C "$temp_dir" . 2>/dev/null
    rm -rf "$temp_dir"

    if [[ -f "$export_file" ]]; then
        log_ok "Configuration exported to: $export_file"
        echo -e "  ${DIM}Includes: favorites, custom commands, aliases, stats${RESET}"
    else
        log_error "Export failed"
        return 1
    fi
}

import_config() {
    local import_file="$1"

    if [[ -z "$import_file" ]]; then
        read -rp "Import file path: " import_file
    fi

    if [[ ! -f "$import_file" ]]; then
        log_error "File not found: $import_file"
        return 1
    fi

    local temp_dir
    temp_dir=$(mktemp -d)

    # Extract archive
    if ! tar -xzf "$import_file" -C "$temp_dir" 2>/dev/null; then
        log_error "Failed to extract archive"
        rm -rf "$temp_dir"
        return 1
    fi

    # Merge or replace files
    echo -e "${YELLOW}Import options:${RESET}"
    echo "  [m] Merge with existing (append)"
    echo "  [r] Replace existing"
    echo "  [c] Cancel"
    echo
    read -rn 1 -p "Choose: " import_mode
    echo

    case "$import_mode" in
        m|M)
            # Merge
            [[ -f "$temp_dir/favorites.txt" ]] && { cat "$temp_dir/favorites.txt" >> "$FAVORITES_FILE"; sort -u "$FAVORITES_FILE" -o "$FAVORITES_FILE"; } || true
            [[ -f "$temp_dir/custom_commands.yaml" ]] && { grep '|' "$temp_dir/custom_commands.yaml" >> "$CUSTOM_COMMANDS_FILE" 2>/dev/null || true; }
            [[ -f "$temp_dir/aliases.txt" ]] && { cat "$temp_dir/aliases.txt" >> "$ALIASES_FILE"; sort -u "$ALIASES_FILE" -o "$ALIASES_FILE"; } || true
            log_ok "Configuration merged"
            ;;
        r|R)
            # Replace
            [[ -f "$temp_dir/favorites.txt" ]] && cp "$temp_dir/favorites.txt" "$FAVORITES_FILE" || true
            [[ -f "$temp_dir/custom_commands.yaml" ]] && cp "$temp_dir/custom_commands.yaml" "$CUSTOM_COMMANDS_FILE" || true
            [[ -f "$temp_dir/aliases.txt" ]] && cp "$temp_dir/aliases.txt" "$ALIASES_FILE" || true
            [[ -f "$temp_dir/stats.json" ]] && cp "$temp_dir/stats.json" "$STATS_FILE" || true
            log_ok "Configuration replaced"
            ;;
        *)
            log_info "Import cancelled"
            ;;
    esac

    rm -rf "$temp_dir"
}

# =============================================================================
# FZF Integration
# =============================================================================

has_fzf() {
    command -v fzf &>/dev/null
}

fzf_search() {
    if ! has_fzf; then
        log_warn "fzf not installed. Install with: brew install fzf"
        log_info "Falling back to standard search..."
        sleep 1
        read -rp "Enter search query: " query
        search_commands "$query"
        return
    fi

    local items=()
    for i in "${!COMMAND_KEYS[@]}"; do
        local key="${COMMAND_KEYS[$i]}"
        local cmd="${COMMAND_VALUES[$i]}"
        local desc="${COMMAND_DESCRIPTIONS[$i]:-}"
        items+=("${key}|${cmd}|${desc}")
    done

    local selected
    selected=$(printf '%s\n' "${items[@]}" | \
        fzf --height=60% \
            --layout=reverse \
            --border \
            --header="Search Commands (ESC to cancel)" \
            --preview='echo -e "Command: {2}\n\nDescription: {3}"' \
            --preview-window=down:3:wrap \
            --delimiter='|' \
            --with-nth=1,2 \
            --ansi)

    if [[ -n "$selected" ]]; then
        local key="${selected%%|*}"
        display_command "$key"
    fi
}

# =============================================================================
# Quick Copy Mode
# =============================================================================

quick_copy() {
    local key="$1"

    # Try direct key first
    local cmd
    cmd=$(get_command_by_key "$key" 2>/dev/null)

    if [[ -z "$cmd" ]]; then
        # Try fuzzy match
        for i in "${!COMMAND_KEYS[@]}"; do
            if [[ "${COMMAND_KEYS[$i]}" == *"$key"* ]]; then
                cmd="${COMMAND_VALUES[$i]}"
                key="${COMMAND_KEYS[$i]}"
                break
            fi
        done
    fi

    if [[ -n "$cmd" ]]; then
        if copy_to_clipboard "$cmd" "true"; then
            update_stats "$key"
            if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                echo "{\"key\":\"$key\",\"command\":\"$cmd\",\"copied\":true}"
            else
                echo "$cmd"
                log_ok "Copied to clipboard"
            fi
            return 0
        else
            echo "$cmd"
            return 0
        fi
    else
        log_error "Command not found: $key"
        return 1
    fi
}

# =============================================================================
# Helper Functions for Categories
# =============================================================================

get_category_commands() {
    local patterns="$1"
    IFS=',' read -ra pattern_array <<< "$patterns"

    for i in "${!COMMAND_KEYS[@]}"; do
        local key="${COMMAND_KEYS[$i]}"
        for pattern in "${pattern_array[@]}"; do
            pattern="${pattern# }"  # Trim leading space
            pattern="${pattern% }"  # Trim trailing space

            # Convert wildcard pattern to regex
            if [[ "$pattern" == *"*" ]]; then
                local regex="${pattern//\*/.*}"
                if [[ "$key" =~ ^${regex}$ ]]; then
                    echo "$key"
                    break
                fi
            else
                if [[ "$key" == "$pattern" ]]; then
                    echo "$key"
                    break
                fi
            fi
        done
    done
}

# =============================================================================
# Category Filter
# =============================================================================

filter_by_category() {
    local category_name="$1"

    # Find matching category
    local found=""
    for category in "${CATEGORIES[@]}"; do
        local cat_name="${category%%:*}"
        if [[ "${cat_name,,}" == "${category_name,,}" ]]; then
            found="$category"
            break
        fi
    done

    if [[ -z "$found" ]]; then
        log_error "Category not found: $category_name"
        echo
        echo "Available categories:"
        for category in "${CATEGORIES[@]}"; do
            echo "  - ${category%%:*}"
        done
        return 1
    fi

    local patterns="${found#*:}"

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo '{"category":"'"${found%%:*}"'","commands":['
        local first=true
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            local cmd
            cmd=$(get_command_by_key "$key")
            [[ "$first" != "true" ]] && echo ","
            first=false
            echo -n "{\"key\":\"$key\",\"command\":\"$cmd\"}"
        done < <(get_category_commands "$patterns")
        echo ']}'
    else
        echo -e "${BOLD}${GREEN}${found%%:*}${RESET}"
        echo "────────────────────────────────"
        echo
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            local cmd
            cmd=$(get_command_by_key "$key")
            local display_key="${key//_/ }"
            echo -e "${YELLOW}${display_key}${RESET}: ${WHITE}${cmd}${RESET}"
        done < <(get_category_commands "$patterns")
    fi
}

# =============================================================================
# Random Tip / Command of the Day
# =============================================================================

show_random_command() {
    local total=${#COMMAND_KEYS[@]}
    if [[ $total -eq 0 ]]; then
        return 1
    fi

    local random_idx=$((RANDOM % total))
    local key="${COMMAND_KEYS[$random_idx]}"
    local cmd="${COMMAND_VALUES[$random_idx]}"
    local desc="${COMMAND_DESCRIPTIONS[$random_idx]:-No description}"

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "{\"key\":\"$key\",\"command\":\"$cmd\",\"description\":\"$desc\"}"
    else
        echo -e "${CYAN}💡 Tip of the Day${RESET}"
        echo "────────────────────────────────"
        echo
        echo -e "${BOLD}${GREEN}${key//_/ }${RESET}"
        echo -e "${WHITE}${cmd}${RESET}"
        echo
        echo -e "${DIM}${desc}${RESET}"
    fi
}

# =============================================================================
# Placeholder Substitution
# =============================================================================

fill_placeholders() {
    local command="$1"
    local filled_command="$command"

    # Extract all placeholders
    local placeholders=()
    while [[ "$command" =~ \<([^>]+)\> ]]; do
        local placeholder="${BASH_REMATCH[1]}"
        if [[ ! " ${placeholders[*]} " =~ " ${placeholder} " ]]; then
            placeholders+=("$placeholder")
        fi
        command="${command#*>}"
    done

    if [[ ${#placeholders[@]} -eq 0 ]]; then
        echo "$filled_command"
        return 0
    fi

    echo -e "${CYAN}Fill in the placeholders:${RESET}"
    echo

    for placeholder in "${placeholders[@]}"; do
        local default=""
        # Suggest defaults based on placeholder name
        case "$placeholder" in
            *branch*) default="main" ;;
            *user*) default="$USER" ;;
            *host*) default="localhost" ;;
            *port*) default="8080" ;;
            *file*) default="file.txt" ;;
            *directory*) default="." ;;
            *package*) default="" ;;
        esac

        local prompt="  <${placeholder}>"
        [[ -n "$default" ]] && prompt="$prompt [${default}]"
        read -rp "$prompt: " value
        value="${value:-$default}"

        if [[ -n "$value" ]]; then
            filled_command="${filled_command//<$placeholder>/$value}"
        fi
    done

    echo
    echo -e "${GREEN}Result:${RESET} ${WHITE}${filled_command}${RESET}"
    echo "$filled_command"
}

# =============================================================================
# Search Commands
# =============================================================================

search_commands() {
    local query="$1"
    local query_lower="${query,,}"
    local matches=()

    # Search in keys, commands, and descriptions
    for i in "${!COMMAND_KEYS[@]}"; do
        local key="${COMMAND_KEYS[$i]}"
        local cmd="${COMMAND_VALUES[$i]}"
        local desc="${COMMAND_DESCRIPTIONS[$i]:-}"

        local key_lower="${key,,}"
        local cmd_lower="${cmd,,}"
        local desc_lower="${desc,,}"

        if [[ "$key_lower" == *"$query_lower"* ]] || \
           [[ "$cmd_lower" == *"$query_lower"* ]] || \
           [[ "$desc_lower" == *"$query_lower"* ]]; then
            matches+=("$i")
        fi
    done

    if [[ ${#matches[@]} -eq 0 ]]; then
        log_warn "No commands found matching: $query"
        sleep 2
        return 1
    fi

    # Interactive selection
    while true; do
        print_header
        echo -e "${BOLD}${GREEN}Search Results for: ${YELLOW}$query${RESET}"
        echo "────────────────────────────────"
        echo

        local count=1
        for idx in "${matches[@]}"; do
            local key="${COMMAND_KEYS[$idx]}"
            local cmd="${COMMAND_VALUES[$idx]}"
            local desc="${COMMAND_DESCRIPTIONS[$idx]:-}"

            echo -e "${YELLOW}[$count]${RESET} ${GREEN}${key//_/ }${RESET}"
            echo -e "    └─ ${WHITE}${cmd}${RESET}"
            [[ -n "$desc" ]] && echo -e "       ${DIM}${desc}${RESET}"
            echo
            ((count++))
        done

        echo -e "${CYAN}Actions:${RESET}"
        echo -e "  ${YELLOW}[1-${#matches[@]}]${RESET} Select command"
        echo -e "  ${YELLOW}[b]${RESET} Back to menu"
        echo -e "  ${YELLOW}[q]${RESET} Quit"
        echo

        read -rp "Select: " choice

        case "$choice" in
            b|B)
                return 0
                ;;
            q|Q)
                exit 0
                ;;
            [0-9]*)
                if [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#matches[@]} ]]; then
                    local arr_idx=$((choice - 1))
                    local match_idx="${matches[$arr_idx]}"
                    display_command "${COMMAND_KEYS[$match_idx]}"
                else
                    log_error "Invalid selection"
                    sleep 1
                fi
                ;;
            *)
                log_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# Display Single Command
# =============================================================================

display_command() {
    local key="$1"
    local cmd
    cmd=$(get_command_by_key "$key")

    if [[ -z "$cmd" ]]; then
        log_error "Command not found: $key"
        sleep 1
        return 1
    fi

    local desc
    desc=$(get_description_by_key "$key")

    while true; do
        print_header
        echo -e "${BOLD}${GREEN}Command Details${RESET}"
        echo "────────────────────────────────"
        echo

        local display_key="${key//_/ }"
        echo -e "${CYAN}Name:${RESET} ${GREEN}${display_key}${RESET}"
        echo -e "${CYAN}Command:${RESET} ${WHITE}${cmd}${RESET}"
        [[ -n "$desc" && "$desc" != "No description available" ]] && \
            echo -e "${CYAN}Description:${RESET} ${DIM}${desc}${RESET}"

        # Check if in favorites
        local is_favorite=false
        if grep -q "^$key$" "$FAVORITES_FILE" 2>/dev/null; then
            is_favorite=true
            echo -e "${CYAN}Status:${RESET} ${YELLOW}⭐ Favorite${RESET}"
        fi

        echo
        echo -e "${CYAN}Actions:${RESET}"
        echo -e "  ${YELLOW}[c]${RESET} Copy to clipboard"
        echo -e "  ${YELLOW}[f]${RESET} Fill placeholders and copy"
        if [[ "$is_favorite" == "true" ]]; then
            echo -e "  ${YELLOW}[u]${RESET} Remove from favorites"
        else
            echo -e "  ${YELLOW}[s]${RESET} Add to favorites"
        fi
        echo -e "  ${YELLOW}[r]${RESET} Run command now"
        echo -e "  ${YELLOW}[b]${RESET} Back"
        echo -e "  ${YELLOW}[q]${RESET} Quit"
        echo

        read -rn 1 -p "Select: " action
        echo

        case "$action" in
            c|C)
                copy_to_clipboard "$cmd"
                add_to_history "$cmd"
                update_stats "$key"
                echo
                read -rn 1 -p "Press any key to continue..."
                ;;
            f|F)
                local filled_cmd
                filled_cmd=$(fill_placeholders "$cmd")
                if [[ -n "$filled_cmd" ]]; then
                    copy_to_clipboard "$filled_cmd"
                    add_to_history "$filled_cmd"
                    update_stats "$key"
                fi
                echo
                read -rn 1 -p "Press any key to continue..."
                ;;
            s|S)
                add_to_favorites "$key"
                sleep 1
                ;;
            u|U)
                remove_from_favorites "$key"
                sleep 1
                ;;
            r|R)
                echo -e "${YELLOW}Run command:${RESET} ${WHITE}${cmd}${RESET}"
                echo
                read -rn 1 -p "Execute? (y/N) " confirm
                echo
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    log_info "Executing: $cmd"
                    echo
                    eval "$cmd"
                    add_to_history "$cmd"
                    update_stats "$key"
                    echo
                    read -rn 1 -p "Press any key to continue..."
                fi
                ;;
            b|B)
                return 0
                ;;
            q|Q)
                exit 0
                ;;
            *)
                log_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# Browse Category
# =============================================================================

browse_category() {
    local category="$1"
    local category_name="${category%%:*}"
    local patterns="${category#*:}"

    while true; do
        print_header
        echo -e "${BOLD}${GREEN}${category_name}${RESET}"
        echo "────────────────────────────────"
        echo

        local commands=()
        while IFS= read -r key; do
            [[ -n "$key" ]] && commands+=("$key")
        done < <(get_category_commands "$patterns")

        if [[ ${#commands[@]} -eq 0 ]]; then
            log_info "No commands in this category"
            sleep 2
            return
        fi

        local count=1
        for key in "${commands[@]}"; do
            local cmd
            cmd=$(get_command_by_key "$key")
            local desc
            desc=$(get_description_by_key "$key")

            echo -e "${YELLOW}[$count]${RESET} ${GREEN}${key//_/ }${RESET}"
            echo -e "    └─ ${WHITE}${cmd}${RESET}"
            [[ -n "$desc" && "$desc" != "No description available" ]] && \
                echo -e "       ${DIM}${desc}${RESET}"
            echo
            ((count++))
        done

        echo -e "${CYAN}Actions:${RESET}"
        echo -e "  ${YELLOW}[1-${#commands[@]}]${RESET} Select command"
        echo -e "  ${YELLOW}[b]${RESET} Back to main menu"
        echo -e "  ${YELLOW}[q]${RESET} Quit"
        echo

        read -rp "Select: " choice

        case "$choice" in
            b|B)
                return
                ;;
            q|Q)
                exit 0
                ;;
            [0-9]*)
                if [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#commands[@]} ]]; then
                    local idx=$((choice - 1))
                    display_command "${commands[$idx]}"
                else
                    log_error "Invalid selection"
                    sleep 1
                fi
                ;;
            *)
                log_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# List All Commands
# =============================================================================

list_all_commands() {
    print_header
    echo -e "${BOLD}${GREEN}All Commands${RESET}"
    echo "────────────────────────────────"
    echo

    for category in "${CATEGORIES[@]}"; do
        local category_name="${category%%:*}"
        local patterns="${category#*:}"

        echo -e "${BOLD}${CYAN}${category_name}${RESET}"
        echo

        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            local cmd
            cmd=$(get_command_by_key "$key")
            local display_key="${key//_/ }"
            printf "  ${GREEN}%-30s${RESET} ${WHITE}%s${RESET}\n" "$display_key" "$cmd"
        done < <(get_category_commands "$patterns")

        echo
    done
}

# =============================================================================
# JSON Output
# =============================================================================

output_json_list() {
    echo '{"commands":['
    local first=true
    for i in "${!COMMAND_KEYS[@]}"; do
        [[ "$first" != "true" ]] && echo ","
        first=false
        local key="${COMMAND_KEYS[$i]}"
        local cmd="${COMMAND_VALUES[$i]}"
        local desc="${COMMAND_DESCRIPTIONS[$i]:-}"
        # Escape special characters
        cmd="${cmd//\\/\\\\}"
        cmd="${cmd//\"/\\\"}"
        desc="${desc//\\/\\\\}"
        desc="${desc//\"/\\\"}"
        echo -n "{\"key\":\"$key\",\"command\":\"$cmd\",\"description\":\"$desc\"}"
    done
    echo ']}'
}
# =============================================================================
# Main Execution
# =============================================================================

main() {
    # Initialize configuration
    init_config

    # Initialize command database
    init_commands

    # Initialize command descriptions
    init_descriptions

    # Load custom commands
    load_custom_commands

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            --search|-s)
                shift
                if [[ -n "${1:-}" ]]; then
                    search_commands "$1"
                    exit $?
                else
                    log_error "Search query required"
                    exit 1
                fi
                ;;
            --list|-l)
                if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                    output_json_list
                else
                    list_all_commands
                fi
                exit 0
                ;;
            --copy|-c)
                shift
                if [[ -n "${1:-}" ]]; then
                    quick_copy "$1"
                    exit $?
                else
                    log_error "Command key required"
                    exit 1
                fi
                ;;
            --category)
                shift
                if [[ -n "${1:-}" ]]; then
                    filter_by_category "$1"
                    exit $?
                else
                    log_error "Category name required"
                    exit 1
                fi
                ;;
            --tip)
                show_random_command
                exit 0
                ;;
            --add)
                add_custom_command
                exit 0
                ;;
            --alias)
                shift
                if [[ -n "${1:-}" ]] && [[ "$1" == *"="* ]]; then
                    local alias_name="${1%%=*}"
                    local target_key="${1#*=}"
                    add_alias "$alias_name" "$target_key"
                    exit $?
                else
                    log_error "Alias format: --alias name=target_key"
                    exit 1
                fi
                ;;
            --export)
                shift
                export_config "${1:-}"
                exit $?
                ;;
            --import)
                shift
                if [[ -n "${1:-}" ]]; then
                    import_config "$1"
                    exit $?
                else
                    log_error "Import file required"
                    exit 1
                fi
                ;;
            --stats)
                if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                    cat "$STATS_FILE" 2>/dev/null || echo '{}'
                else
                    show_stats
                fi
                exit 0
                ;;
            --fzf)
                fzf_search
                exit 0
                ;;
            --history)
                # Non-interactive history view
                if [[ ! -s "$HISTORY_FILE" ]]; then
                    log_warn "No history yet"
                    exit 0
                fi
                echo -e "${CYAN}Command History (Last 20):${RESET}"
                echo "────────────────────────────────"
                tail -n 20 "$HISTORY_FILE" | while IFS='|' read -r timestamp cmd; do
                    echo -e "${DIM}${timestamp}${RESET} ${WHITE}${cmd## }${RESET}"
                done
                exit 0
                ;;
            --from-history)
                # Interactive add from history
                if [[ ! -s "$HISTORY_FILE" ]]; then
                    log_warn "No history yet"
                    exit 1
                fi
                local hist_cmds=()
                while IFS='|' read -r _ cmd; do
                    cmd="${cmd## }"
                    [[ -n "$cmd" ]] && hist_cmds+=("$cmd")
                done < <(tail -n 20 "$HISTORY_FILE")
                add_command_from_history "${hist_cmds[@]}"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Run interactive mode if no arguments
    main_menu
}

# =============================================================================
# Main Menu
# =============================================================================

main_menu() {
    while true; do
        print_header

        echo -e "${BOLD}${WHITE}Main Menu${RESET}"
        echo "────────────────────────────────"
        echo

        echo -e "${CYAN}Browse by Category:${RESET}"
        local count=1
        for category in "${CATEGORIES[@]}"; do
            local category_name="${category%%:*}"
            echo -e "  ${YELLOW}[$count]${RESET} $category_name"
            ((count++))
        done

        echo
        echo -e "${CYAN}Quick Actions:${RESET}"
        echo -e "  ${YELLOW}[s]${RESET} Search commands"
        echo -e "  ${YELLOW}[z]${RESET} FZF search (fuzzy finder)"
        echo -e "  ${YELLOW}[f]${RESET} View favorites"
        echo -e "  ${YELLOW}[h]${RESET} View history"
        echo -e "  ${YELLOW}[l]${RESET} List all commands"
        echo -e "  ${YELLOW}[t]${RESET} Tip of the day"
        echo
        echo -e "${CYAN}Manage:${RESET}"
        echo -e "  ${YELLOW}[c]${RESET} Custom commands"
        echo -e "  ${YELLOW}[a]${RESET} Aliases"
        echo -e "  ${YELLOW}[u]${RESET} Usage statistics"
        echo -e "  ${YELLOW}[e]${RESET} Export/Import config"
        echo
        echo -e "  ${YELLOW}[?]${RESET} Help"
        echo -e "  ${YELLOW}[q]${RESET} Quit"
        echo

        read -rp "Select option: " choice

        case "$choice" in
            s|S)
                read -rp "Enter search query: " query
                [[ -n "$query" ]] && search_commands "$query"
                ;;
            z|Z)
                fzf_search
                ;;
            f|F)
                view_favorites
                ;;
            h|H)
                view_history
                ;;
            l|L)
                list_all_commands
                read -rn 1 -p "Press any key to continue..."
                ;;
            t|T)
                print_header
                show_random_command
                echo
                read -rn 1 -p "Press any key to continue..."
                ;;
            c|C)
                list_custom_commands
                ;;
            a|A)
                list_aliases
                ;;
            u|U)
                show_stats
                ;;
            e|E)
                print_header
                echo -e "${BOLD}${GREEN}Export/Import Configuration${RESET}"
                echo "────────────────────────────────"
                echo
                echo -e "  ${YELLOW}[e]${RESET} Export configuration"
                echo -e "  ${YELLOW}[i]${RESET} Import configuration"
                echo -e "  ${YELLOW}[b]${RESET} Back"
                echo
                read -rn 1 -p "Choose: " ei_choice
                echo
                case "$ei_choice" in
                    e|E) export_config ;;
                    i|I) import_config ;;
                esac
                sleep 2
                ;;
            \?)
                show_help
                read -rn 1 -p "Press any key to continue..."
                ;;
            q|Q)
                echo
                log_info "Thank you for using $SCRIPT_DISPLAY_NAME!"
                exit 0
                ;;
            [0-9]*)
                if [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#CATEGORIES[@]} ]]; then
                    local idx=$((choice - 1))
                    browse_category "${CATEGORIES[$idx]}"
                else
                    log_error "Invalid selection"
                    sleep 1
                fi
                ;;
            *)
                log_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# Help Function
# =============================================================================

show_help() {
    cat << EOF
${BOLD}${SCRIPT_DISPLAY_NAME}${RESET} - Version ${SCRIPT_VERSION}

${CYAN}USAGE:${RESET}
    ${SCRIPT_NAME} [OPTIONS]
    ${SCRIPT_NAME} --search <query>
    ${SCRIPT_NAME} --copy <key>
    ${SCRIPT_NAME} --category <name>

${CYAN}OPTIONS:${RESET}
    -h, --help              Show this help message
    -v, --version           Show version
    -s, --search QUERY      Search commands by keyword
    -l, --list              List all commands (non-interactive)
    -c, --copy KEY          Copy command to clipboard by key
    --category NAME         Filter by category name
    --tip                   Show random command tip
    --json                  Output in JSON format
    --add                   Add a custom command interactively
    --from-history          Add a custom command from history
    --history               Show command history (non-interactive)
    --alias NAME=KEY        Create alias (e.g., --alias gc=git_commit)
    --export [FILE]         Export configuration
    --import FILE           Import configuration
    --stats                 Show usage statistics
    --fzf                   Use FZF for interactive search
    --verbose               Enable verbose output

${CYAN}FEATURES:${RESET}
    • Browse commands by category
    • Search commands by keyword with descriptions
    • Copy commands to clipboard
    • Fill placeholders interactively
    • Save favorite commands
    • View command history
    • Add custom commands
    • Create command aliases
    • Track usage statistics
    • Export/import configuration
    • FZF integration for fuzzy search
    • JSON output for scripting

${CYAN}CATEGORIES:${RESET}
    JavaScript: NPM/Node, Yarn, pnpm
    Python: Python/pip, UV
    Go, Rust/Cargo, Ruby/Bundler, PHP/Composer
    Java: Maven, Gradle | .NET | Swift
    Git, Git Flow, Docker, Make/Build
    File Operations, Network, Process Management
    Database, macOS/Homebrew, Development Tools

${CYAN}TIPS:${RESET}
    • Commands with <placeholders> can be filled interactively
    • Use --copy for quick clipboard access in scripts
    • Add custom commands for your specific workflows
    • Create short aliases for frequently used commands
    • Save useful one-liners from history with --from-history

${CYAN}CONFIGURATION:${RESET}
    Config directory: ${CONFIG_DIR}
    Favorites: ${FAVORITES_FILE}
    Custom commands: ${CUSTOM_COMMANDS_FILE}
    Aliases: ${ALIASES_FILE}
    Statistics: ${STATS_FILE}
    History: ${HISTORY_FILE}

${CYAN}EXAMPLES:${RESET}
    ${SCRIPT_NAME}                          # Interactive mode
    ${SCRIPT_NAME} --search git             # Search for git commands
    ${SCRIPT_NAME} --copy git_commit        # Copy git commit command
    ${SCRIPT_NAME} --category docker        # List docker commands
    ${SCRIPT_NAME} --tip                    # Show random tip
    ${SCRIPT_NAME} --add                    # Add custom command
    ${SCRIPT_NAME} --from-history           # Add command from history
    ${SCRIPT_NAME} --history                # View command history
    ${SCRIPT_NAME} --alias gc=git_commit    # Create alias
    ${SCRIPT_NAME} --list --json            # List all as JSON
    ${SCRIPT_NAME} --fzf                    # Fuzzy search with fzf

EOF
}

show_version() {
    echo "${SCRIPT_DISPLAY_NAME} version ${SCRIPT_VERSION}"
}

# Run main function
main "$@"
