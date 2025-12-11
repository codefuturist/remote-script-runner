# Package Verification System

## Overview

The Package Verification System is an automated tool that validates package names across all YAML profiles in the remote-script-runner project. It verifies that packages exist in their respective package manager repositories by querying official APIs.

## Quick Start

```bash
# Install UV (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Verify all packages (UV handles dependencies automatically)
uv run tools/verify_packages.py

# Verify specific profile
uv run tools/verify_packages.py --profile kubernetes.yaml

# Generate report for CI
uv run tools/verify_packages.py --ci --format json > report.json
```

## Features

- ✅ **15+ Package Managers Supported**: brew, apt, dnf, winget, choco, npm, pip, cargo, and more
- 📊 **Multiple Report Formats**: Text, JSON, and Markdown
- 💾 **Smart Caching**: 24-hour cache to minimize API calls and respect rate limits
- 🎯 **Targeted Verification**: Filter by profile or package manager
- 🔄 **CI/CD Integration**: GitHub Actions workflow included
- 🚀 **Batch Processing**: Efficiently verifies 1,200+ packages

## Architecture

### Validator Hierarchy

```
PackageValidator (base)
├── Tier 1: Full API Verification
│   ├── BrewValidator          # Homebrew formulas
│   ├── BrewCaskValidator      # Homebrew casks
│   ├── NpmValidator           # NPM registry
│   ├── PyPiValidator          # PyPI packages
│   ├── CargoValidator         # crates.io
│   ├── ChocoValidator         # Chocolatey
│   ├── WingetValidator        # Winget (GitHub)
│   ├── ScoopValidator         # Scoop (GitHub)
│   ├── KrewValidator          # Kubectl plugins
│   ├── PacmanValidator        # Arch Linux
│   ├── SnapValidator          # Snap Store
│   └── MacPortsValidator      # MacPorts
└── Tier 2: Limited/Unverifiable
    └── FallbackValidator      # apt, dnf, yum, zypper
```

### Package Distribution

Based on current YAML profiles (~1,284 package-manager pairs):

| Manager | Count | Verification | API Type |
|---------|-------|-------------|----------|
| brew | 315 | ✅ Full | JSON catalog |
| apt | 290 | ⚠️ Unverifiable | Repo-dependent |
| dnf | 221 | ⚠️ Unverifiable | Repo-dependent |
| winget | 170 | ✅ Full | GitHub API |
| choco | 136 | ✅ Full | OData API |
| npm | 36 | ✅ Full | Registry API |
| krew | 19 | ✅ Full | GitHub raw |
| pip | 16 | ✅ Full | PyPI API |
| brew_cask | 8 | ✅ Full | JSON catalog |
| pacman | 6 | ✅ Full | JSON API |
| Others | <5 | Various | Various |

## Usage Examples

### Basic Verification

```bash
# Verify all packages in all profiles
$ python3 tools/verify-packages.py

Found 1284 package-manager pairs in 27 profiles
Starting verification...
Progress: 50/1284 packages verified...
Progress: 100/1284 packages verified...
...

======================================================================
Package Verification Report
======================================================================
Total packages:    1284
Verified:          511 ✓
Not found:         105 ✗
Unverifiable:      570 ?
Errors:            98 ⚠
```

### Profile-Specific Verification

```bash
# Verify only Kubernetes packages
$ python3 tools/verify-packages.py --profile kubernetes.yaml --format markdown

# Package Verification Report

## Summary

| Metric | Count |
|--------|-------|
| Total packages | 120 |
| ✓ Verified | 74 |
| ✗ Not found | 19 |
| ? Unverifiable | 14 |
| ⚠ Errors | 13 |
```

### Manager-Specific Verification

```bash
# Verify only Homebrew packages
$ python3 tools/verify-packages.py --manager brew

# Verify only NPM packages
$ python3 tools/verify-packages.py --manager npm
```

### CI/CD Integration

```bash
# CI mode: exits 1 if any packages not found or errors
$ python3 tools/verify-packages.py --ci

# Generate JSON report for processing
$ python3 tools/verify-packages.py --format json > verification.json

# Generate Markdown for PR comments
$ python3 tools/verify-packages.py --format markdown > verification.md
```

### Cache Management

```bash
# Force refresh cache (ignore existing)
$ python3 tools/verify-packages.py --refresh-cache

# View cache location
$ ls -lh tools/cache/package_cache.json

# Clear cache
$ rm -f tools/cache/package_cache.json
```

## Output Formats

### 1. Text Format (Default)

Human-readable console output with summary and detailed errors:

```
======================================================================
Package Verification Report
======================================================================
Total packages:    1284
Verified:          511 ✓
Not found:         105 ✗
Unverifiable:      570 ?
Errors:            98 ⚠

----------------------------------------------------------------------
NOT FOUND PACKAGES:
----------------------------------------------------------------------
  [brew] kubectl
    File: kubernetes.yaml
    Details: Not found in Homebrew formulas or casks
    Suggestion: Use krew manager instead

  [choco] minikube
    File: kubernetes.yaml
    Details: Not found in Chocolatey repository
```

### 2. JSON Format

Machine-readable format for CI/CD processing:

```json
{
  "summary": {
    "total": 1284,
    "verified": 511,
    "not_found": 105,
    "unverifiable": 570,
    "errors": 98
  },
  "verified": [...],
  "not_found": [
    {
      "file": "kubernetes.yaml",
      "package": "kubectl",
      "manager": "brew",
      "details": "Not found in Homebrew formulas or casks",
      "suggestion": "Use krew manager instead"
    }
  ],
  "unverifiable": [...],
  "errors": [...]
}
```

### 3. Markdown Format

GitHub-flavored markdown for documentation or PR comments:

```markdown
# Package Verification Report

## Summary

| Metric | Count |
|--------|-------|
| Total packages | 1284 |
| ✓ Verified | 511 |
| ✗ Not found | 105 |
| ? Unverifiable | 570 |
| ⚠ Errors | 98 |

## Not Found Packages

| Package | Manager | Profile | Details |
|---------|---------|---------|---------|
| `kubectl` | brew | kubernetes.yaml | Not found (suggestion: Use krew) |
```

## Common Issues and Solutions

### Issue: GitHub API Rate Limiting

**Symptom**: HTTP 403 errors for winget, scoop, or krew packages

**Solution**: Set GitHub token for higher rate limit (60/hr → 5000/hr)

```bash
# Get token from https://github.com/settings/tokens
export GITHUB_TOKEN=ghp_your_token_here

# Run verification with token
python3 tools/verify-packages.py
```

### Issue: Package Marked as "Not Found" But Exists

**Possible Causes**:

1. **Typo in package name**: Check spelling and case sensitivity
2. **Third-party repository**: Package in a tap/PPA not checked by API
3. **Recently added**: Cache may be stale, use `--refresh-cache`
4. **Different manager**: Package available in different manager

**Example**:

```yaml
# ❌ Wrong
brew: kubectl

# ✅ Correct
krew: kubectl
```

### Issue: High "Unverifiable" Count

**Explanation**: Normal for apt/dnf packages (no public API)

These managers depend on repository configuration:
- `apt`: Requires specific PPAs or sources
- `dnf`: Requires Fedora/RHEL repositories
- `yum`: Legacy, repo-dependent

**Impact**: Marked as "unverifiable", not failures

### Issue: Slow Verification

**Causes**:
- First run downloads full Homebrew catalog (~8,000 formulas)
- Network latency for API calls
- Rate limiting throttling

**Solutions**:
- Cache is saved after first run (faster subsequent runs)
- Use `--manager` flag to verify specific manager only
- Run during off-peak hours for better API performance

## GitHub Actions Workflow

The included workflow (`.github/workflows/verify-packages.yml`) automatically:

1. ✅ Runs on PR changes to `config/packages/**`
2. 📅 Runs weekly on Sunday at midnight UTC
3. 💬 Posts verification report as PR comment
4. ⚠️ Fails CI if packages not found or errors
5. 📦 Uploads report artifacts

### Triggering Manually

```bash
# Via GitHub web interface
# Actions → Package Verification → Run workflow

# Via GitHub CLI
gh workflow run verify-packages.yml
```

## Best Practices

### 1. Run Before Committing Package Changes

```bash
# After modifying YAML profiles
python3 tools/verify-packages.py --profile your-profile.yaml

# If verification passes, commit
git add config/packages/your-profile.yaml
git commit -m "feat: add new packages to profile"
```

### 2. Use Appropriate Package Managers

```yaml
# ✅ Good: Use manager-specific packages
packages:
  - name: kubectl
    brew: kubernetes-cli
    krew: kubectl
    apt: kubectl
    dnf: kubectl

# ❌ Bad: Wrong manager for package
packages:
  - name: kubectl
    brew: kubectl  # Not available as 'kubectl' in brew
```

### 3. Handle Unverifiable Packages

For apt/dnf packages, add comments explaining repository requirements:

```yaml
packages:
  - name: docker-ce
    apt: docker-ce  # Requires Docker's official apt repository
    dnf: docker-ce  # Requires Docker's official dnf repository
```

### 4. Review Verification Reports

Weekly verification helps catch:
- Deprecated packages
- Renamed packages
- Moved packages (e.g., formula → cask)

## API Rate Limits

| Service | Unauthenticated | Authenticated | Notes |
|---------|----------------|---------------|-------|
| GitHub API | 60/hour | 5,000/hour | Use GITHUB_TOKEN |
| Homebrew | Unlimited | Unlimited | Full catalog download |
| NPM | Unlimited | Unlimited | Per-package HEAD |
| PyPI | Unlimited | Unlimited | Per-package HEAD |
| crates.io | Standard | Standard | Generous limits |
| Chocolatey | Unlimited | Unlimited | OData queries |
| Others | Varies | Varies | See docs |

### Handling Rate Limits

The tool automatically:
1. Caches results for 24 hours
2. Detects rate limiting (HTTP 403/429)
3. Marks subsequent packages as "unverifiable"
4. Saves cache for next run

## Extending the Tool

### Adding a New Validator

1. Create validator file in `tools/package_validators/`:

```python
# tools/package_validators/my_manager_validator.py
from .base import PackageValidator, ValidationResult
import requests

class MyManagerValidator(PackageValidator):
    def __init__(self, cache=None):
        super().__init__(cache)
        self.manager_name = 'mymanager'

    def validate(self, package: str) -> ValidationResult:
        cached = self.get_cached(package)
        if cached:
            return cached

        try:
            # Implement validation logic
            url = f"https://api.mymanager.com/packages/{package}"
            response = requests.get(url, timeout=15)

            if response.status_code == 200:
                status = 'verified'
            elif response.status_code == 404:
                status = 'not_found'
            else:
                status = 'error'

            result = ValidationResult(package, 'mymanager', status)
            self.set_cached(result)
            return result

        except Exception as e:
            result = ValidationResult(package, 'mymanager', 'error',
                                     details=str(e))
            self.set_cached(result)
            return result
```

2. Register in `__init__.py`:

```python
from .my_manager_validator import MyManagerValidator

__all__ = [..., 'MyManagerValidator']
```

3. Add to `verify-packages.py`:

```python
def _init_validators(self):
    return {
        ...,
        'mymanager': MyManagerValidator(self.cache),
    }
```

## Troubleshooting

### Debug Mode

```bash
# Increase verbosity (add to verify-packages.py)
python3 -u tools/verify-packages.py 2>&1 | tee verification.log
```

### Test Single Package

```bash
# Create test script
python3 << 'EOF'
import sys
sys.path.insert(0, 'tools')
from package_validators import BrewValidator

validator = BrewValidator()
result = validator.validate('kubectl')
print(f"Status: {result.status}")
print(f"Details: {result.details}")
EOF
```

### Check Cache

```bash
# View cache contents
cat tools/cache/package_cache.json | jq '.'

# Count cached entries
cat tools/cache/package_cache.json | jq 'length'

# Find specific package
cat tools/cache/package_cache.json | jq '.["brew:kubectl"]'
```

## Performance

- **Initial run**: ~3-5 minutes (downloads catalogs, makes API calls)
- **Cached run**: ~30-60 seconds (uses cache)
- **Profile-specific**: ~10-30 seconds
- **Manager-specific**: ~20-90 seconds

## Contributing

To improve the verification system:

1. Add validators for new package managers
2. Improve existing validators with better heuristics
3. Add fuzzy matching for "not found" suggestions
4. Implement parallel verification for faster processing
5. Add package metadata extraction (version, description)

## License

Part of the remote-script-runner project.
