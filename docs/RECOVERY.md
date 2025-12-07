# 🆘 Recovery Guide

If your `rsr` installation becomes broken or non-functional, use this guide to recover.

## Quick Recovery

The fastest way to recover is using our automated recovery script:

```bash
curl -fsSL https://codefuturist.github.io/remote-script-runner/recover.sh | sh
```

Or with wget:

```bash
wget -qO- https://codefuturist.github.io/remote-script-runner/recover.sh | sh
```

## Recovery Options

The recovery script provides several options:

### 1. Restore from Backup (Recommended)
If a backup exists from your last update, you can instantly restore it:

```bash
# Automatic (via recovery script)
curl -fsSL https://codefuturist.github.io/remote-script-runner/recover.sh | sh
# Choose option 1

# Manual
mv ~/.local/bin/rsr.backup ~/.local/bin/rsr
chmod +x ~/.local/bin/rsr
```

### 2. Download Fresh Copy
Get a clean installation from GitHub:

```bash
# Automatic (via recovery script)
curl -fsSL https://codefuturist.github.io/remote-script-runner/recover.sh | sh
# Choose option 2

# Manual
curl -fsSL https://codefuturist.github.io/remote-script-runner/rsr -o ~/.local/bin/rsr
chmod +x ~/.local/bin/rsr
```

### 3. Fresh Install
Completely reinstall rsr:

```bash
curl -fsSL https://codefuturist.github.io/remote-script-runner/install.sh | bash
```

## Common Scenarios

### Scenario 1: "command not found: rsr"

**Cause:** rsr was deleted or path is incorrect

**Solution:**
```bash
# Fresh install
curl -fsSL https://codefuturist.github.io/remote-script-runner/install.sh | bash
```

### Scenario 2: "syntax error" when running rsr

**Cause:** File got corrupted or bad update

**Solution:**
```bash
# Restore from backup
mv ~/.local/bin/rsr.backup ~/.local/bin/rsr

# Or download fresh copy
curl -fsSL https://codefuturist.github.io/remote-script-runner/rsr -o ~/.local/bin/rsr
chmod +x ~/.local/bin/rsr
```

### Scenario 3: rsr runs but all commands fail

**Cause:** Broken internal logic

**Solution:**
```bash
# Use recovery script
curl -fsSL https://codefuturist.github.io/remote-script-runner/recover.sh | sh
# Choose option 1 (restore backup) or option 2 (fresh download)
```

### Scenario 4: Update failed, now rsr is broken

**Cause:** Bad update or network interruption

**Solution:**
```bash
# Backup should exist automatically
mv ~/.local/bin/rsr.backup ~/.local/bin/rsr

# Verify it works
rsr --version
```

## Manual Recovery Steps

If automated recovery doesn't work, here are the manual steps:

### Step 1: Check Installation Location

Common locations:
- `~/.local/bin/rsr`
- `/usr/local/bin/rsr`
- Custom: `$(which rsr)`

### Step 2: Check for Backup

```bash
ls -la ~/.local/bin/rsr*
```

You should see:
- `rsr` (current - possibly broken)
- `rsr.backup` (previous working version)

### Step 3: Restore or Replace

**If backup exists:**
```bash
cp ~/.local/bin/rsr.backup ~/.local/bin/rsr
chmod +x ~/.local/bin/rsr
```

**If no backup:**
```bash
curl -fsSL https://codefuturist.github.io/remote-script-runner/rsr -o ~/.local/bin/rsr
chmod +x ~/.local/bin/rsr
```

### Step 4: Test

```bash
rsr --version
rsr health -a
```

## Prevention

To minimize the chance of issues:

1. **Test updates in dry-run mode:**
   ```bash
   rsr self-update --check
   ```

2. **Always keep backups:**
   - Automatic backups are created during updates
   - Located at: `~/.local/bin/rsr.backup`
   - Never delete until confirming new version works

3. **Verify after update:**
   ```bash
   rsr --version
   rsr list
   ```

## Built-in Safeguards

rsr includes multiple layers of protection:

### During Update:
1. ✅ **Download Validation** - Verifies file before replacing
2. ✅ **Automatic Backup** - Creates backup before update
3. ✅ **Syntax Check** - Tests new version with `--version`
4. ✅ **Auto Rollback** - Restores backup if validation fails
5. ✅ **Atomic Operations** - Uses `mv` for safe replacement

### Error Messages Include Recovery Instructions:
```
✗ New version failed validation test!
▸ Rolling back to previous version...
✓ Rollback successful
✗ Update failed - stayed on v1.0.0
```

## Emergency Contacts

If you're still having issues:

1. **GitHub Issues:** https://github.com/codefuturist/remote-script-runner/issues
2. **Documentation:** https://codefuturist.github.io/remote-script-runner
3. **Recovery Script:** https://codefuturist.github.io/remote-script-runner/recover.sh

## Recovery Script Features

The `recover.sh` script provides:

- 🔍 **Auto-detection** of installation path
- 📋 **Interactive menu** with clear options
- ✅ **Backup restoration** with one command
- 🔄 **Fresh download** capability
- 🧪 **Installation testing** to verify health
- 🎨 **User-friendly** interface with progress feedback

## Testing Recovery (for developers)

To test the recovery process:

```bash
# Break the installation intentionally
echo "#!/bin/sh\necho broken" > ~/.local/bin/rsr

# Try to run rsr (should fail)
rsr --version

# Use recovery script
curl -fsSL https://codefuturist.github.io/remote-script-runner/recover.sh | sh

# Verify recovery worked
rsr --version
```

## Summary

**Quick Recovery:** Use the automated recovery script
```bash
curl -fsSL https://codefuturist.github.io/remote-script-runner/recover.sh | sh
```

**Manual Recovery:** Restore backup or download fresh
```bash
# Restore backup
mv ~/.local/bin/rsr.backup ~/.local/bin/rsr

# Or download fresh
curl -fsSL https://codefuturist.github.io/remote-script-runner/rsr -o ~/.local/bin/rsr
chmod +x ~/.local/bin/rsr
```

**Prevention:** Always check before updating
```bash
rsr self-update --check
```

---

💡 **Remember:** You can never be truly locked out - the recovery script is always available via curl!
