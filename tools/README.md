# Package Verification System

> ⚡ **Now using [UV](https://docs.astral.sh/uv/)** - 10-100x faster Python dependency management!
> See [UV_MIGRATION.md](UV_MIGRATION.md) for migration details.

Automated verification tool for validating package names across all YAML profiles in the remote-script-runner project.

## Overview

This tool verifies that package names are correct for each package manager by querying their respective APIs and repositories. It supports 15+ package managers and can verify ~1,200+ package-manager pairs.

## Features

- ✅ **Automated Verification**: Checks package existence via official APIs
- 📊 **Multiple Output Formats**: Text, JSON, and Markdown reports
- 💾 **Smart Caching**: 24-hour cache to minimize API calls
- 🎯 **Targeted Verification**: Filter by profile or package manager
- 🔄 **CI Integration**: Exit codes for automated workflows
- 🚀 **Parallel Processing**: Efficient batch verification

## Supported Package Managers

### Tier 1 - Full API Verification (850+ packages)

| Manager | Count | API | Status |
|---------|-------|-----|--------|
| brew | 315 | formulae.brew.sh | ✅ Full catalog |
| apt | 290 | - | ⚠️ Unverifiable (repo-dependent) |
| dnf | 221 | - | ⚠️ Unverifiable (repo-dependent) |
| winget | 170 | GitHub API | ✅ Manifest structure |
| choco | 136 | OData API | ✅ XML query |
| npm | 36 | registry.npmjs.org | ✅ Per-package |
| krew | 19 | krew-index | ✅ GitHub raw |
| pip | 16 | pypi.org | ✅ Per-package |
| brew_cask | 8 | formulae.brew.sh | ✅ Full catalog |
| pacman | 6 | archlinux.org | ✅ JSON API |
| cargo | 3 | crates.io | ✅ API |
| scoop | 2 | GitHub raw | ✅ Bucket check |
| snap | 1 | snapcraft.io | ✅ API |
| macports | 1 | ports.macports.org | ✅ API |
| pipx | 1 | - | ⚠️ Uses PyPI |

### Tier 2 - Limited/Unverifiable

- **apt**: No reliable public API (repository-dependent)
- **dnf**: No reliable public API (repository-dependent)
- **pipx**: Uses PyPI backend

## Installation

### Prerequisites

This project uses [UV](https://docs.astral.sh/uv/) for dependency management.

```bash
# Install UV (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Or with Homebrew
brew install uv

# Or with pipx
pipx install uv
```

UV automatically manages virtual environments and dependencies - no manual setup required!

### Quick Start

```bash
# Verify all packages (UV handles dependencies automatically)
uv run tools/verify_packages.py

# Or run directly (UV shebang)
tools/verify_packages.py

# Verify specific profile
uv run tools/verify_packages.py --profile kubernetes.yaml

# Verify specific package manager
uv run tools/verify_packages.py --manager brew

# Generate JSON report
uv run tools/verify_packages.py --format json > report.json

# Generate Markdown report
uv run tools/verify_packages.py --format markdown > VERIFICATION.md

# CI mode (exit 1 if errors found)
uv run tools/verify_packages.py --ci

# Refresh cache (ignore existing cache)
uv run tools/verify_packages.py --refresh-cache
```

## Usage Examples

### Verify All Packages

```bash
$ python3 tools/verify-packages.py
Found 1226 package-manager pairs in 27 profiles
Starting verification...
Progress: 50/1226 packages verified...
Progress: 100/1226 packages verified...
...

======================================================================
Package Verification Report
======================================================================
Total packages:    1226
Verified:          850 ✓
Not found:         15 ✗
Unverifiable:      361 ?
Errors:            0 ⚠
```

### Verify Specific Profile

```bash
$ python3 tools/verify-packages.py --profile kubernetes.yaml --format markdown
# Package Verification Report

## Summary

| Metric | Count |
|--------|-------|
| Total packages | 87 |
| ✓ Verified | 62 |
| ✗ Not found | 2 |
| ? Unverifiable | 23 |
| ⚠ Errors | 0 |
```

### CI Integration

```bash
# In GitHub Actions or CI pipeline
python3 tools/verify-packages.py --ci --format json > verification-report.json

# Exit code 0 = all packages verified or unverifiable
# Exit code 1 = packages not found or errors occurred
```

## Output Formats

### Text Format (Default)

Human-readable console output with color-coded results.

### JSON Format

```json
{
  "summary": {
    "total": 1226,
    "verified": 850,
    "not_found": 15,
    "unverifiable": 361,
    "errors": 0
  },
  "not_found": [
    {
      "file": "kubernetes.yaml",
      "package": "kubectl-neat",
      "manager": "brew",
      "details": "Not found in Homebrew formulas or casks",
      "suggestion": "Consider using krew manager"
    }
  ]
}
```

### Markdown Format

GitHub-flavored markdown with tables, suitable for documentation or PR comments.

## Caching

The tool uses a 24-hour cache to minimize API calls:

- **Cache Location**: `tools/cache/package_cache.json`
- **Cache TTL**: 24 hours
- **Cache Refresh**: Use `--refresh-cache` flag to force refresh

## API Rate Limits

| Service | Limit | Notes |
|---------|-------|-------|
| GitHub API | 60/hour (unauth)<br>5000/hour (auth) | Affects winget, scoop, krew |
| Homebrew | None | Full catalog download |
| npm | None | Per-package HEAD requests |
| PyPI | None | Per-package HEAD requests |
| crates.io | None | Standard rate limiting |
| Chocolatey | None | OData queries |

**Tip**: Set `GITHUB_TOKEN` environment variable to increase GitHub API rate limit:

```bash
export GITHUB_TOKEN=ghp_your_token_here
python3 tools/verify-packages.py
```

## Architecture

```
tools/
├── verify-packages.py          # Main entry point
├── requirements.txt            # Python dependencies
├── package_validators/         # Validator modules
│   ├── __init__.py
│   ├── base.py                 # Abstract base validator
│   ├── brew_validator.py       # Homebrew (formula + cask)
│   ├── npm_validator.py        # NPM registry
│   ├── pypi_validator.py       # PyPI
│   ├── cargo_validator.py      # crates.io
│   ├── choco_validator.py      # Chocolatey
│   ├── winget_validator.py     # Winget (GitHub)
│   ├── scoop_validator.py      # Scoop (GitHub)
│   ├── krew_validator.py       # Krew (GitHub)
│   ├── pacman_validator.py     # Arch Linux
│   ├── snap_validator.py       # Snap Store
│   ├── macports_validator.py   # MacPorts
│   └── fallback_validator.py   # apt/dnf (unverifiable)
└── cache/
    └── package_cache.json      # Cached results
```

## Adding New Validators

To add support for a new package manager:

1. Create a new validator in `package_validators/`:

```python
from .base import PackageValidator, ValidationResult

class MyManagerValidator(PackageValidator):
    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'mymanager'

    def validate(self, package: str) -> ValidationResult:
        cached = self.get_cached(package)
        if cached:
            return cached

        # Implement validation logic
        # Query API, check existence, etc.

        result = ValidationResult(package, 'mymanager', 'verified')
        self.set_cached(result)
        return result
```

1. Register in `package_validators/__init__.py`
2. Add to `verify-packages.py` validators dict

## CI/CD Integration

### GitHub Actions Workflow

Create `.github/workflows/verify-packages.yml`:

```yaml
name: Package Verification

on:
  pull_request:
    paths:
      - 'config/packages/**'
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install -r tools/requirements.txt

      - name: Verify packages
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: python3 tools/verify-packages.py --ci --format markdown > verification-report.md

      - name: Comment PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v6
        with:
          script: |
            const fs = require('fs');
            const report = fs.readFileSync('verification-report.md', 'utf8');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: report
            });
```

## Troubleshooting

### Rate Limiting Issues

If you encounter GitHub API rate limits:

```bash
# Check current rate limit
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/rate_limit

# Use authentication to increase limit
export GITHUB_TOKEN=your_token
python3 tools/verify-packages.py
```

### Cache Issues

```bash
# Clear cache and re-verify
rm -rf tools/cache/package_cache.json
python3 tools/verify-packages.py --refresh-cache
```

### Package Not Found

If a package shows as "not found" but you know it exists:

1. **Check spelling**: Package names are case-sensitive
2. **Third-party repos**: Some packages require taps/PPAs/repos
3. **Alternative managers**: Try a different package manager
4. **Manual verification**: Check the package manager's website directly

## Limitations

1. **apt/dnf packages**: Cannot be verified via API (repository-dependent)
2. **Third-party repositories**: Homebrew taps, custom PPAs not checked
3. **Rate limits**: GitHub API limited to 60 requests/hour without token
4. **Network dependency**: Requires internet connection for verification

## Contributing

To improve package verification:

1. Add new validators for unsupported managers
2. Improve existing validators with better heuristics
3. Add fuzzy matching for "not found" suggestions
4. Implement parallel verification for faster processing

## License

Part of the remote-script-runner project. See main repository LICENSE.
