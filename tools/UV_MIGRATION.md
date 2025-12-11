# UV Migration Guide

This project has been migrated to use [UV](https://docs.astral.sh/uv/) for Python dependency management.

## What Changed?

### ✅ Benefits of UV

- **10-100x faster** than pip
- **Automatic virtual environment** management
- **Lockfile** for reproducible builds (uv.lock)
- **Drop-in replacement** for pip, pip-tools, and virtualenv
- **Single tool** for all Python project needs

### 📦 New Files

- `pyproject.toml` - Project metadata and dependencies
- `uv.lock` - Locked dependencies for reproducibility
- `.python-version` - Python version specification (3.11+)
- `.venv/` - Auto-managed virtual environment

### 🗑️ Deprecated (but kept for compatibility)

- `requirements.txt` - Still present but UV uses pyproject.toml

## Installation

### Install UV

```bash
# macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Or with Homebrew
brew install uv

# Or with pipx
pipx install uv

# Windows
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
```

That's it! No need to install Python or create virtual environments manually.

## Usage

### Running the Verifier

```bash
# Old way (deprecated)
python3 tools/verify_packages.py --help

# New way with UV (recommended)
uv run tools/verify_packages.py --help

# Or directly with UV shebang
./tools/verify_packages.py --help
```

UV automatically:
1. Creates a virtual environment (`.venv/`)
2. Installs dependencies from `pyproject.toml`
3. Runs the script in the isolated environment

### Common Commands

```bash
# Run the verifier
uv run tools/verify_packages.py

# Run with specific profile
uv run tools/verify_packages.py --profile kubernetes.yaml

# Run in CI mode
uv run tools/verify_packages.py --ci

# Update dependencies
cd tools && uv lock --upgrade

# Add a new dependency
cd tools && uv add new-package

# Remove a dependency
cd tools && uv remove package-name

# Sync dependencies (install from lockfile)
cd tools && uv sync
```

### CI/CD Integration

The GitHub Actions workflow has been updated to use UV:

```yaml
- name: Install UV
  uses: astral-sh/setup-uv@v4
  with:
    enable-cache: true

- name: Run verifier
  run: uv run tools/verify_packages.py --ci
```

No need to install Python or dependencies separately!

## Migration Details

### Before (pip)

```bash
# Install dependencies
pip install -r tools/requirements.txt

# Run script
python3 tools/verify_packages.py
```

### After (UV)

```bash
# Everything in one command
uv run tools/verify_packages.py
```

UV handles:
- ✅ Virtual environment creation
- ✅ Dependency installation
- ✅ Python version management
- ✅ Script execution

## Project Structure

```
tools/
├── pyproject.toml          # Project metadata & dependencies
├── uv.lock                 # Locked dependencies
├── .python-version         # Python version (3.11+)
├── .venv/                  # Auto-managed virtual environment
├── verify_packages.py      # Main script (UV shebang)
├── package_validators/     # Validator modules
└── requirements.txt        # Legacy (for compatibility)
```

## Troubleshooting

### Issue: "uv: command not found"

**Solution**: Install UV first
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Issue: "No Python interpreter found"

**Solution**: UV will automatically download and install Python
```bash
uv python install 3.11
```

### Issue: Dependencies not found

**Solution**: Sync dependencies from lockfile
```bash
cd tools && uv sync
```

### Issue: Need to use legacy pip workflow

**Solution**: requirements.txt still works
```bash
pip install -r tools/requirements.txt
python3 tools/verify_packages.py
```

## Why UV?

### Performance

| Operation | pip | UV | Speedup |
|-----------|-----|-----|---------|
| Install requests | 2.5s | 0.1s | **25x faster** |
| Cold cache | 10s | 0.5s | **20x faster** |
| Warm cache | 5s | 0.05s | **100x faster** |

### Features

- **Parallel downloads**: Installs packages concurrently
- **Copy-on-write**: Efficient disk usage
- **Global cache**: Share packages across projects
- **Workspace support**: Monorepo-friendly
- **Built-in tools**: Replaces pip, venv, pip-tools

### Developer Experience

```bash
# Old workflow
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python script.py

# New workflow
uv run script.py
```

## Resources

- [UV Documentation](https://docs.astral.sh/uv/)
- [UV GitHub](https://github.com/astral-sh/uv)
- [Migration Guide](https://docs.astral.sh/uv/guides/migration/)
- [UV vs pip](https://docs.astral.sh/uv/pip/compatibility/)

## Backwards Compatibility

For users who prefer the old workflow:

```bash
# Still works (but slower)
pip install -r tools/requirements.txt
python3 tools/verify_packages.py
```

However, we strongly recommend migrating to UV for:
- ⚡ Faster dependency resolution
- 🔒 Reproducible builds (lockfile)
- 🎯 Automatic environment management
- 🚀 Better developer experience

## Migration Checklist

- [x] Install UV
- [x] Create pyproject.toml
- [x] Generate uv.lock
- [x] Update shebang to use UV
- [x] Update documentation
- [x] Update GitHub Actions workflow
- [x] Test all commands
- [x] Verify CI/CD integration

---

**Migration Date**: December 11, 2024
**UV Version**: 0.9.0
**Status**: ✅ Complete
