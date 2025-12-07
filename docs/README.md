# Documentation

Welcome to the Remote Script Runner documentation!

## Quick Links

- **[Header Convention](HEADER_CONVENTION.md)** - Comprehensive guide for script metadata and searchability
- **[Script Template](templates/script-template.sh)** - Starter template following best practices
- **[Scripts Guide](SCRIPTS.md)** - Overview of available scripts
- **[Syntax Guide](SYNTAX_GUIDE.md)** - Shell-specific syntax reference
- **[Testing Guide](TESTING.md)** - How to test scripts
- **[Changelog](CHANGELOG.md)** - Version history

## For Script Authors

### Creating a New Script

1. **Start with the template**:
   ```bash
   cp docs/templates/script-template.sh scripts/bash/my-new-script.sh
   ```

2. **Fill in the metadata header**:
   - Required fields: `@id`, `@name`, `@displayName`, `@description`, `@category`, `@version`, `@author`, `@tags`, `@shells`
   - See [Header Convention](HEADER_CONVENTION.md) for details

3. **Implement functionality**:
   - Follow the structure: logging functions, usage, main function, argument parsing
   - Use `set -euo pipefail` for strict error handling
   - Include comprehensive examples in the usage function

4. **Test locally**:
   ```bash
   ./scripts/bash/my-new-script.sh --help
   ./scripts/bash/my-new-script.sh -v
   ```

5. **Validate and build**:
   ```bash
   make validate     # Check header format
   make build-registry    # Update registry.json
   ```

6. **Commit and push**:
   ```bash
   git add scripts/bash/my-new-script.sh scripts/registry.json rsr index.html
   git commit -m "feat: add my-new-script for XYZ functionality"
   git push
   ```

### Header Metadata Quick Reference

```bash
#!/bin/bash
# =============================================================================
# @id           unique-id          # Used in: rsr <id>
# @name         script-name        # Matches filename
# @displayName  Display Name       # Shown in web UI
# @description  What it does       # Search/description
# @category     monitoring         # Groups scripts
# @version      1.0.0              # Semantic versioning
# @author       yourname           # Your identifier
# @tags         tag1,tag2,tag3     # Enable search (3-12 tags)
# @shells       bash,zsh           # Available variants
# =============================================================================
```

### Tag Strategy for Searchability

Choose tags that users would search for:

**Good Tags** ✅:
- Specific technologies: `postgresql`, `nginx`, `docker`
- Resources: `cpu`, `memory`, `disk`, `network`
- Actions: `backup`, `restore`, `monitor`, `audit`
- Use cases: `security`, `performance`, `diagnostics`

**Poor Tags** ❌:
- Too generic: `script`, `tool`, `system`
- Too vague: `important`, `useful`

### Categories

Use standard categories for consistency:
- `monitoring` - Health checks, metrics, status
- `configuration` - Setup, installation, settings
- `security` - Hardening, auditing, compliance
- `backup` - Backup and recovery operations
- `maintenance` - Cleanup, updates, optimization
- `networking` - Network diagnostics and config
- `database` - Database operations

## Registry Integration

The `scripts/registry.json` file is **auto-generated** from script headers:

```bash
# Extract metadata from headers
./tools/build-registry.sh

# Or use Makefile
make build-registry
```

This updates:
1. `scripts/registry.json` - Central metadata database
2. `rsr` - Embedded script mappings
3. `index.html` - Web UI script cards

## Web UI Searchability

Scripts are searchable on GitHub Pages through:

### Search Fields
- Script ID (`@id`)
- Script name (`@name`)
- Display name (`@displayName`)
- Description (`@description`)
- Tags (`@tags`)
- Category (`@category`)

### Search Tips

Use tags strategically to maximize discoverability:

```bash
# Database backup script - comprehensive tags
@tags backup,database,postgresql,mysql,mongodb,dump,restore,archive

# Network diagnostics - searchable terms
@tags network,diagnostics,ping,traceroute,dns,connectivity,troubleshoot

# Security audit - multiple angles
@tags security,audit,compliance,hardening,ssh,firewall,permissions
```

## Best Practices

### 1. Metadata Quality

- ✅ Keep `@description` under 100 characters
- ✅ Use 5-10 relevant tags
- ✅ Include technology names in tags
- ✅ Update `@version` when changing behavior
- ✅ Test all shells listed in `@shells`

### 2. Documentation

- ✅ Include remote execution example in comment
- ✅ Provide comprehensive usage function
- ✅ Show multiple examples in help text
- ✅ Document all options and arguments
- ✅ Explain exit codes

### 3. Code Structure

- ✅ Use `set -euo pipefail` for safety
- ✅ Define color codes consistently
- ✅ Implement logging functions (info, warn, error, debug)
- ✅ Add cleanup handlers with `trap`
- ✅ Validate inputs early
- ✅ Support `--dry-run` for safety
- ✅ Support `--verbose` for debugging

### 4. Error Handling

```bash
# Check dependencies
command_exists() {
    command -v "$1" &> /dev/null
}

# Validate parameters
validate_params() {
    if [[ -z "$PARAM" ]]; then
        log_error "Parameter required"
        return 1
    fi
}

# Use meaningful exit codes
exit 0  # Success
exit 1  # General error
exit 2  # Invalid argument
exit 3  # Dependency missing
```

## Validation Tools

### Check Script Headers

```bash
# Validate all scripts
./tools/validate.sh

# Validate specific script
./tools/validate.sh scripts/bash/my-script.sh

# Show detailed validation
./tools/validate.sh --strict
```

### Linting

```bash
# ShellCheck linting
make lint

# Format scripts
make format

# Full quality check
make all
```

## Testing

See [TESTING.md](TESTING.md) for comprehensive testing guide.

Quick test workflow:

```bash
# Run unit tests
make test-unit

# Run integration tests
make test-integration

# Run all tests
make test
```

## Contributing

1. Read [CONTRIBUTING.md](../CONTRIBUTING.md)
2. Follow [Header Convention](HEADER_CONVENTION.md)
3. Use the [script template](templates/script-template.sh)
4. Test thoroughly
5. Update documentation if adding new features

## Questions?

- **Issues**: https://github.com/codefuturist/remote-script-runner/issues
- **Discussions**: https://github.com/codefuturist/remote-script-runner/discussions
- **Contributing**: See [CONTRIBUTING.md](../CONTRIBUTING.md)

---

**Last Updated**: 2025-12-07  
**Version**: 1.0.0
