# Remote Script Runner Architecture

## Scalable Design for 200+ Scripts

The Remote Script Runner (RSR) is architected to scale efficiently to hundreds of scripts while maintaining code quality, consistency, and maintainability.

## Core Architecture Principles

### 1. Domain-Specific Libraries

Each major functional area has its own library in `lib/`:

```
lib/
├── common.sh          # Universal utilities (logging, colors, OS detection)
├── config.sh          # Configuration management
├── interactive.sh     # Interactive mode & prompts
├── users.sh          # User management operations
└── docker.sh         # Docker-specific operations
```

**Benefits:**

- **Code Reuse**: Common functionality shared across multiple scripts
- **Maintainability**: Fix once, benefit everywhere
- **Testability**: Libraries can be tested independently
- **Consistency**: Same implementation across all scripts

### 2. Feature Scripts

Scripts in `scripts/bash/` are thin wrappers that:

1. Source required libraries
2. Parse arguments and handle subcommands
3. Call library functions
4. Handle user interaction and output

**Example Structure:**

```bash
#!/bin/bash
# Source libraries
source lib/common.sh
source lib/users.sh
source lib/interactive.sh

# Define metadata and defaults
# Parse arguments
# Route to subcommands
# Call library functions
```

### 3. Central Registry

The `scripts/registry.json` file serves as the single source of truth for:

- Script metadata and versioning
- Subcommands and options
- Platform support
- Documentation and examples
- Tags for discovery

**Benefits:**

- Automated CLI generation
- Consistent help output
- Searchable script catalog
- Web UI integration ready

### 4. Subcommand Architecture

Complex scripts use a hierarchical subcommand structure:

```
rsr usermgmt                    # Top-level command
├── create                      # Subcommand level 1
├── delete
├── password                    # Subcommand level 1
│   ├── reset                   # Subcommand level 2
│   ├── expire
│   └── generate
├── group
│   ├── create
│   ├── add
│   └── remove
└── session
    ├── list
    └── history
```

**Benefits:**

- Natural command structure
- Easy to extend
- Self-documenting
- Follows industry standards (git, docker, kubectl)

## File Organization

```
remote-script-runner/
├── lib/                        # Shared libraries
│   ├── common.sh              # 200 lines - universal utils
│   ├── users.sh               # 800 lines - user management
│   └── docker.sh              # 300 lines - docker utils
├── scripts/
│   ├── registry.json          # Central catalog
│   └── bash/
│       ├── user-management.sh # 1500 lines - thin wrapper
│       ├── user-audit.sh      # 800 lines - auditing
│       └── docker-management.sh
├── docs/                      # Comprehensive documentation
│   ├── USER_MANAGEMENT.md
│   ├── ARCHITECTURE.md
│   └── common-sysadmin-tasks.md
└── test/                      # Test suites
    ├── unit/                  # Library tests
    └── integration/           # End-to-end tests
```

## Scaling Strategy

### Phase 1: Foundation (Current - 13 scripts)

- ✅ Core libraries established
- ✅ Registry structure defined
- ✅ Subcommand pattern proven
- ✅ Cross-platform support working

### Phase 2: Domain Coverage (20-50 scripts)

Add domain libraries:

- `lib/network.sh` - Network operations
- `lib/storage.sh` - Storage & backup
- `lib/services.sh` - Service management
- `lib/monitoring.sh` - System monitoring

### Phase 3: Enterprise Features (50-100 scripts)

- `lib/cloud.sh` - AWS, Azure, GCP operations
- `lib/kubernetes.sh` - K8s management
- `lib/database.sh` - DB administration
- `lib/security.sh` - Security hardening

### Phase 4: Full Coverage (100-200+ scripts)

- Specialized industry scripts
- Compliance automation
- Advanced orchestration
- Custom extensions API

## Library Size Guidelines

| Library Size | Action |
|--------------|--------|
| < 500 lines | Single file, well-organized |
| 500-1000 lines | Consider splitting into modules |
| > 1000 lines | Split into subdirectory |

**Example split:**

```
lib/users/
├── accounts.sh    # User CRUD operations
├── passwords.sh   # Password management
├── groups.sh      # Group management
└── sessions.sh    # Session monitoring
```

## Cross-Platform Strategy

### OS Detection

Every library starts with OS detection:

```bash
_detect_os() {
    case "$(uname -s)" in
        Darwin*) echo "darwin" ;;
        Linux*) echo "linux" ;;
        FreeBSD*) echo "freebsd" ;;
    esac
}
```

### Platform-Specific Implementations

Use internal functions with OS suffix:

```bash
# Public API
user_create() {
    case "$(_detect_os)" in
        darwin) _user_create_darwin "$@" ;;
        linux) _user_create_linux "$@" ;;
    esac
}

# Private implementations
_user_create_darwin() { ... }
_user_create_linux() { ... }
```

### Compatibility Matrix

Track support in registry:

```json
{
  "platforms": {
    "linux": ["ubuntu", "debian", "rhel", "arch"],
    "macos": "full-support",
    "windows": "wsl-only"
  }
}
```

## Error Handling

### Exit Codes

Standardized across all scripts:

```bash
EXIT_OK=0              # Success
EXIT_ERROR=1           # General error
EXIT_INVALID_ARGS=2    # Bad arguments
EXIT_PERMISSION=3      # Permission denied
EXIT_NOT_FOUND=4       # Resource not found
EXIT_CONFLICT=5        # Resource conflict
```

### Error Messages

Always informative with actionable guidance:

```bash
log_error "User 'john' does not exist"
log_info "Create with: rsr usermgmt create -u john"
exit $EXIT_NOT_FOUND
```

## Testing Strategy

### Unit Tests

Test library functions in isolation:

```bash
# test/unit/users.bats
@test "user_exists returns 0 for existing user" {
    run user_exists "root"
    [ "$status" -eq 0 ]
}
```

### Integration Tests

Test full script workflows:

```bash
# test/integration/user-management.bats
@test "create and delete user workflow" {
    run sudo rsr usermgmt create -u testuser --dry-run
    [ "$status" -eq 0 ]
}
```

### Cross-Platform CI

Test on multiple OS in CI/CD:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest]
    shell: [bash, zsh]
```

## Documentation Standards

### Script Headers

Every script includes structured metadata:

```bash
# =============================================================================
# @id           usermgmt
# @name         user-management
# @displayName  User Management
# @description  Comprehensive user management
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         users,accounts,passwords,groups
# @shells       bash
# @requires     sudo
# @os           linux,macos
# =============================================================================
```

### Function Documentation

Library functions are documented:

```bash
# Create user (cross-platform)
# Usage: user_create "username" [options]
# Options: --uid UID --gid GID --home PATH --shell SHELL
# Returns: 0 on success, 1 on error
user_create() { ... }
```

### User Documentation

Each major feature has a guide:

- Quick start examples
- Complete reference
- Best practices
- Troubleshooting
- Integration examples

## Performance Considerations

### Lazy Loading

Libraries only load what's needed:

```bash
# Don't load heavy dependencies upfront
if [[ "$SUBCOMMAND" == "audit" ]]; then
    source lib/audit.sh
fi
```

### Caching

Cache expensive operations:

```bash
# Cache OS detection
_USERS_OS=""
_detect_os() {
    [[ -z "$_USERS_OS" ]] && _USERS_OS=$(uname -s)
    echo "$_USERS_OS"
}
```

### Parallel Execution

Support concurrent operations where safe:

```bash
# Batch operations can run in parallel
for user in "${users[@]}"; do
    user_create "$user" &
done
wait
```

## Security Best Practices

### Input Validation

Always validate user input:

```bash
if [[ ! "$username" =~ ^[a-z][a-z0-9_-]{2,31}$ ]]; then
    log_error "Invalid username format"
    exit $EXIT_INVALID_ARGS
fi
```

### Privilege Checking

Check permissions early:

```bash
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root"
        log_info "Run with: sudo $0 $*"
        exit $EXIT_PERMISSION
    fi
}
```

### Safe Defaults

Always use safe defaults:

```bash
DRY_RUN=false          # Require explicit --execute
VERBOSE=false          # Minimal output by default
INTERACTIVE=auto       # Auto-detect if appropriate
```

### Dry Run Support

All destructive operations support dry-run:

```bash
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would delete user: $username"
    return 0
fi
```

## Extensibility

### Plugin Architecture

Future support for custom extensions:

```bash
# Load custom plugins from ~/.rsr/plugins/
for plugin in ~/.rsr/plugins/*.sh; do
    [[ -f "$plugin" ]] && source "$plugin"
done
```

### Hook System

Allow scripts to define hooks:

```bash
# Pre-execution hook
if [[ "$(type -t pre_user_create)" == "function" ]]; then
    pre_user_create "$username"
fi
```

### Custom Templates

Support user-defined templates:

```bash
# Load custom permission templates
[[ -f ~/.rsr/templates/permissions.conf ]] && \
    source ~/.rsr/templates/permissions.conf
```

## Monitoring & Observability

### Structured Logging

Support multiple output formats:

```bash
if [[ "$LOG_FORMAT" == "json" ]]; then
    echo "{\"level\":\"info\",\"message\":\"$msg\",\"timestamp\":\"$(date -Iseconds)\"}"
else
    log_info "$msg"
fi
```

### Metrics Collection

Optional metrics for automation:

```bash
# Export metrics in Prometheus format
cat << EOF
rsr_user_create_total{status="success"} $success_count
rsr_user_create_total{status="failure"} $failure_count
EOF
```

### Audit Trails

All operations can log to audit:

```bash
audit_log() {
    local action="$1"
    local user="$2"
    echo "$(date -Iseconds) $USER $action $user" >> /var/log/rsr-audit.log
}
```

## Future Enhancements

### Planned Features

1. **Web UI** - Browse and execute scripts from browser
2. **Remote Execution** - Execute scripts on remote hosts via SSH
3. **Schedule Manager** - Cron-like scheduling for scripts
4. **Approval Workflow** - Multi-step approval for sensitive operations
5. **Role-Based Access** - Fine-grained permission control
6. **Configuration Profiles** - Reusable configuration sets
7. **Rollback System** - Automatic rollback on failure
8. **Ansible Integration** - Native Ansible module
9. **Terraform Provider** - Infrastructure as code support
10. **API Server** - RESTful API for automation

## Contribution Guidelines

### Adding New Scripts

1. **Create library** if needed: `lib/newdomain.sh`
2. **Implement functions** with cross-platform support
3. **Create script**: `scripts/bash/new-script.sh`
4. **Update registry**: Add entry to `scripts/registry.json`
5. **Write tests**: `test/unit/new-script.bats`
6. **Document**: Add to `docs/` if major feature
7. **Test on platforms**: Linux and macOS minimum
8. **Submit PR** with comprehensive description

### Code Review Checklist

- ✅ Cross-platform compatibility tested
- ✅ Error handling comprehensive
- ✅ Dry-run mode implemented for destructive ops
- ✅ Help text clear and complete
- ✅ Functions documented
- ✅ Tests passing
- ✅ Registry updated
- ✅ No secrets in code
- ✅ Performance acceptable
- ✅ Follows existing patterns

## Conclusion

This architecture enables RSR to scale from tens to hundreds of scripts while maintaining:

- **Code Quality**: Reusable libraries, consistent patterns
- **User Experience**: Intuitive subcommands, helpful output
- **Maintainability**: Clear organization, comprehensive tests
- **Performance**: Efficient execution, minimal overhead
- **Extensibility**: Plugin system, hooks, templates
- **Security**: Input validation, privilege checking, audit trails

The foundation is solid for building a comprehensive system administration toolkit that serves both individual sysadmins and large enterprise deployments.
