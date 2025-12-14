# Package Verifier - Quick Start Guide

## 5-Minute Setup

### 1. Install UV

```bash
# Install UV (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Or with Homebrew
brew install uv
```

That's it! UV handles all dependencies automatically.

### 2. Run Your First Verification

```bash
# Verify all packages (takes 3-5 minutes)
# UV automatically installs dependencies on first run
uv run tools/verify_packages.py

# Or run directly with UV shebang
tools/verify_packages.py

# Verify a single profile (faster)
uv run tools/verify_packages.py --profile kubernetes.yaml
```

### 3. Understand the Output

```
======================================================================
Package Verification Report
======================================================================
Total packages:    1284
Verified:          511 ✓  <- Package exists in repository
Not found:         105 ✗  <- Package doesn't exist (needs fixing)
Unverifiable:      570 ?  <- No API available (apt/dnf)
Errors:            98 ⚠   <- API errors (usually rate limits)
```

## Common Tasks

### Check Specific Package Manager

```bash
# Verify only Homebrew packages
uv run tools/verify_packages.py --manager brew

# Verify only NPM packages
uv run tools/verify_packages.py --manager npm
```

### Generate Reports

```bash
# JSON report for CI/CD
uv run tools/verify_packages.py --format json > report.json

# Markdown report for documentation
uv run tools/verify_packages.py --format markdown > VERIFICATION.md
```

### Fix GitHub Rate Limiting

If you see HTTP 403 errors:

```bash
# 1. Create GitHub token: https://github.com/settings/tokens
# 2. Set environment variable
export GITHUB_TOKEN=ghp_your_token_here

# 3. Run verification again
uv run tools/verify_packages.py
```

### CI Integration

```bash
# Exit code 0 = success, 1 = failures found
uv run tools/verify_packages.py --ci

# Use in CI pipeline
if uv run tools/verify_packages.py --ci; then
    echo "All packages verified!"
else
    echo "Verification failed - check output"
    exit 1
fi
```

## Understanding Package Managers

### ✅ Fully Verifiable (850+ packages)

- **brew**: Homebrew formulas (macOS/Linux)
- **npm**: Node.js packages
- **pip**: Python packages
- **cargo**: Rust crates
- **choco**: Chocolatey (Windows)
- **winget**: Windows Package Manager
- **krew**: kubectl plugins

### ⚠️ Unverifiable (570+ packages)

- **apt**: Ubuntu/Debian (repo-dependent)
- **dnf**: Fedora/RHEL (repo-dependent)
- **yum**: Legacy Fedora (repo-dependent)

These managers require specific repositories to be configured and cannot be verified via public APIs.

## Troubleshooting

### "Package not found" but it exists

**Possible reasons:**

1. Typo in package name (case-sensitive)
2. Package in third-party repository (e.g., Homebrew tap)
3. Wrong package manager

**Example fix:**

```yaml
# ❌ Not found
brew: kubectl

# ✅ Correct
brew: kubernetes-cli
# OR
krew: kubectl
```

### Slow verification

**First run:** Downloads full catalogs (Homebrew ~8,000 packages)
**Solution:** Cache is saved after first run - next runs are faster

```bash
# Force cache refresh
python3 tools/verify-packages.py --refresh-cache
```

### High error count

**Usually caused by:** GitHub API rate limiting

**Solution:** Set GITHUB_TOKEN (increases limit from 60/hr to 5000/hr)

## What's Next?

- Read full documentation: `tools/README.md`
- Learn about architecture: `docs/PACKAGE_VERIFICATION.md`
- Check GitHub Actions workflow: `.github/workflows/verify-packages.yml`

## Quick Reference

| Command | Description |
|---------|-------------|
| `python3 tools/verify-packages.py` | Verify all packages |
| `--profile <name>` | Verify specific profile |
| `--manager <name>` | Verify specific manager |
| `--format json` | Output as JSON |
| `--format markdown` | Output as Markdown |
| `--ci` | CI mode (exit 1 on failures) |
| `--refresh-cache` | Clear and rebuild cache |

## Support

- Report issues: [GitHub Issues](https://github.com/your-repo/issues)
- Documentation: `tools/README.md`
- Examples: `docs/PACKAGE_VERIFICATION.md`
