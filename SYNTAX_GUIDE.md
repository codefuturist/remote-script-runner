# Remote Script Execution Syntax Guide

## 🎯 Three Main Patterns for Remote Script Execution

Based on extensive testing and analysis, here are the three primary patterns for running remote scripts with arguments:

| # | Pattern | Example | Best For |
|---|---------|---------|----------|
| 1 | **Pipe Form** | `curl -fsSL URL \| bash -s -- <args>` | Most readable, conventional one-liner |
| 2 | **bash -c with dummy $0** | `bash -c "$(curl URL)" -- <dummy-$0> <args>` | Pipe-free environments |
| 3 | **Original "quirky" variant** | `/bin/bash -c "$(curl URL)" -s 103 111` | Legacy compatibility |

## 📊 Comprehensive Pattern Comparison

### Pattern 1: Pipe Form ✨ (RECOMMENDED)

```bash
curl -fsSL https://example.com/script.sh | bash -s -- -u admin -p production
```

**👍 Pros:**
- **Straightforward** – everybody recognizes the classic "curl | bash" one-liner
- **Simplest quoting**: after `--`, everything is `$1 $2...` in the remote script; no need to think about `$0`
- **Retains pipeline context** – because the script runs on bash's stdin, it's in the same process group as the caller, so a single tee, redirection or ctrl-c stops the whole thing
- **Works inside a heredoc**: easy to embed in CI YAMLs or docs

**👎 Cons:**
- **Requires a pipe** – some locked-down environments (certain sudoers rules, SELinux policies, or SSH ForceCommand) disallow unapproved pipes
- **No chance to checksum first** unless you split it into two commands or sub-shell it (which starts to defeat the simplicity)
- **`$0` is "bash"** – the downloaded script sees `$0` as bash, so if it relies on its own filename it has to derive it some other way

### Pattern 2: bash -c with dummy $0

```bash
bash -c "$(curl -fsSL https://example.com/script.sh)" -- script-name -u admin -p production
```

**👍 Pros:**
- **Pipe-free** – nothing after the URL needs a pipe, which can sidestep locked-down shells or awkward copy-and-paste situations where the pipe char gets mangled
- **You control `$0`** – supply a meaningful label (or leave it blank) so logging inside the remote script shows what you want
- **Can be wrapped in `$( ... )`** inside another command because it's just an argument to bash

**👎 Cons:**
- **Quoting discipline** – the embedded script lives inside a double-quoted string, so any embedded `$`, back-ticks or `\` must be escaped properly
- **Less obvious to casual readers** why the `--` is there and how `$0` ends up being the next word
- **Long command line in ps/top**: the entire script body ends up in `/proc/<pid>/cmdline`, which can look messy and may exceed ARG_MAX for very large scripts

### Pattern 3: Original "Quirky" Variant

```bash
/bin/bash -c "$(curl -fsSL https://example.com/script.sh)" -s 103 111
```

**👍 Pros:**
- **Works today** – if you already deployed it, nothing is wrong with it functionally
- **Shorter than pattern 2** when you only need positional args (`$1`, `$2`...) and don't care about `$0`

**👎 Cons:**
- **Confusing semantics** – the `-s` after the script string is not an option to your remote script but becomes `$0`; real parameters start at `$1`. People reading logs will wonder why `$0` is "-s"
- **Hard to scale** – add one more flag and suddenly you need to remember where to shift things
- **Easy to break** if the remote script relies on `$0` being a path or meaningful label
- **Still has the quoting drawbacks** of pattern 2 but without its clarity around `$0`

## 🎯 Quick Decision Guide

| If you... | Pick |
|-----------|------|
| Want the most readable, conventional one-liner and the host allows pipes | **Pattern 1** |
| Need to run under sudo with a NOPASSWD: /bin/bash whitelist that forbids pipes, or in an environment that strips \| | **Pattern 2** |
| Already shipped the original variant and must stay backward-compatible for a while | Keep **Pattern 3** but schedule time to migrate |

## 🚀 Real-World Examples

### Pattern 1: Pipe Form (Recommended for Most Cases)

```bash
# System health check
curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/system-health-check.sh | bash -s -- -v -s cpu memory -t 5

# Server setup with dry run
curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/server-setup.sh | bash -s -- -d -u admin -p production nginx docker

# In a cron job with logging
*/5 * * * * curl -fsSL https://example.com/health-check.sh | bash -s -- -a >> /var/log/health.log 2>&1

# With error handling
curl -fsSL https://example.com/setup.sh | bash -s -- -u admin || echo "Setup failed"
```

### Pattern 2: bash -c Form (For Restricted Environments)

```bash
# When pipes are restricted
sudo /bin/bash -c "$(curl -fsSL https://example.com/script.sh)" -- health-check -s cpu memory

# With meaningful $0 for logging
/bin/bash -c "$(curl -fsSL https://example.com/deploy.sh)" -- deploy-prod -e production -v

# Embedded in another command
watch -n 60 '/bin/bash -c "$(curl -fsSL https://example.com/monitor.sh)" -- monitor -q'
```

### Pattern 3: Original Form (Legacy Compatibility)

```bash
# Original ProxmoxVE style
/bin/bash -c "$(curl -fsSL https://example.com/update-lxcs.sh)" -s 103 111 >> /var/log/update.log 2>/dev/null

# Our scripts with this pattern
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/system-health-check.sh)" -s uptime

# Note: -s becomes $0, real args start at $1
/bin/bash -c "$(curl -fsSL https://example.com/script.sh)" dummy-$0 arg1 arg2
```

## 🛡️ Security Considerations

### Safe Execution Pattern

```bash
# 1. Download and review first
SCRIPT_URL="https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/script.sh"
curl -fsSL "$SCRIPT_URL" > /tmp/script.sh
less /tmp/script.sh  # Review the script

# 2. If satisfied, execute
chmod +x /tmp/script.sh
/tmp/script.sh -- -u admin -p production

# Or execute directly after review
/bin/bash /tmp/script.sh -- -u admin -p production
```

### Version Pinning

```bash
# Pin to specific commit for production
COMMIT="d943416"  # Replace with actual commit hash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/${COMMIT}/script.sh)" -- -u admin
```

### Checksum Verification

```bash
# Verify script integrity
SCRIPT_URL="https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/script.sh"
EXPECTED_SHA256="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# Download and verify
curl -fsSL "$SCRIPT_URL" > /tmp/script.sh
echo "$EXPECTED_SHA256  /tmp/script.sh" | sha256sum -c -
if [ $? -eq 0 ]; then
    /bin/bash /tmp/script.sh -- -u admin
else
    echo "Checksum verification failed!"
    exit 1
fi
```

## 📝 Script Design Guidelines

When creating scripts for remote execution, follow these patterns:

### 1. **Argument Parsing**

```bash
#!/bin/bash
# Use simple argument parsing that works everywhere
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--username)
            USERNAME="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            # Handle positional arguments
            ARGS+=("$1")
            shift
            ;;
    esac
done
```

### 2. **Help Integration**

```bash
# Always provide help with remote execution examples
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Remote execution:
  /bin/bash -c "\$(curl -fsSL https://example.com/script.sh)" -- [OPTIONS]

OPTIONS:
  -h, --help      Show this help message
  -v, --verbose   Enable verbose output
EOF
}
```

### 3. **Error Handling**

```bash
# Fail fast and provide clear errors
set -euo pipefail

# Validate required arguments
if [[ -z "${USERNAME:-}" ]]; then
    echo "Error: Username is required. Use -u or --username" >&2
    exit 1
fi
```

## 🐚 Cross-Shell Compatibility

### zsh (macOS Default Shell)

All patterns work seamlessly with zsh (the default shell on macOS):

```bash
# Pattern 1: Pipe Form with zsh
curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/system-health-check.sh | zsh -s -- -v -s cpu memory

# Pattern 2: zsh -c Form
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/system-health-check.sh)" -- -s uptime

# Pattern 3: Original form works identically
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/system-health-check.sh)" -s uptime
```

### Cross-Shell Examples

```bash
# Explicitly use bash (works everywhere)
curl -fsSL https://example.com/script.sh | bash -s -- -u admin

# Use system default shell
curl -fsSL https://example.com/script.sh | sh -s -- -u admin

# Use zsh explicitly (macOS/Linux with zsh installed)
curl -fsSL https://example.com/script.sh | zsh -s -- -u admin

# Auto-detect and use appropriate shell
curl -fsSL https://example.com/script.sh | "$SHELL" -s -- -u admin
```

### Shell-Specific Considerations

| Shell | Pipe Form | bash -c Form | Notes |
|-------|-----------|-------------|-------|
| **bash** | ✅ `bash -s --` | ✅ `bash -c "$(...)"` | Universal compatibility |
| **zsh** | ✅ `zsh -s --` | ✅ `zsh -c "$(...)"` | macOS default, identical syntax |
| **sh** | ✅ `sh -s --` | ✅ `sh -c "$(...)"` | POSIX compliant |
| **fish** | ⚠️ Different syntax | ⚠️ Different syntax | Requires fish-specific patterns |

## 🔧 Advanced Patterns

### Using with SSH

```bash
# Execute on remote server
ssh user@server '/bin/bash -c "$(curl -fsSL https://example.com/script.sh)" -- -u admin'

# Multiple servers
for server in server1 server2 server3; do
    ssh "user@$server" '/bin/bash -c "$(curl -fsSL https://example.com/script.sh)" -- -a'
done
```

### Conditional Execution

```bash
# Only run if certain conditions are met
if [[ "$(uname -s)" == "Linux" ]]; then
    /bin/bash -c "$(curl -fsSL https://example.com/linux-setup.sh)" -- -u admin
fi
```

### With Docker

```bash
# Run inside a container
docker run --rm ubuntu:latest /bin/bash -c "$(curl -fsSL https://example.com/script.sh)" -- -u admin

# With volume mounting
docker run --rm -v /local/path:/data ubuntu:latest \
    /bin/bash -c "$(curl -fsSL https://example.com/script.sh)" -- -p /data
```

## 📌 Summary & Recommendations

### ✅ **Recommended: Pattern 1 (Pipe Form)**

```bash
curl -fsSL https://example.com/script.sh | bash -s -- [ARGUMENTS]
```

This is the most readable and conventional approach for most use cases.

### 🔄 **Alternative: Pattern 2 (For Restricted Environments)**

```bash
/bin/bash -c "$(curl -fsSL https://example.com/script.sh)" -- dummy-$0 [ARGUMENTS]
```

Use when pipes are restricted or forbidden.

### 💡 **Tip: Hybrid Approach for Security**

Whichever style you choose, you can still add an integrity check:

```bash
curl -fsSL https://example.com/script.sh -o /tmp/x && \
  echo "7e9d...  /tmp/x" | sha256sum -c - && \
  bash /tmp/x --options
rm /tmp/x
```

This hybrid gives you the security of an on-disk checksum with the ephemeral behaviour you like, because you delete the file right after execution.

### 🎯 **Key Takeaways**

1. **Use Pattern 1** (pipe form) for most cases - it's the most recognizable
2. **Use Pattern 2** when pipes are restricted or in sudo environments
3. **Avoid Pattern 3** unless maintaining legacy compatibility
4. **Always use `--`** to separate script arguments (except in Pattern 3)
5. **Consider security** - add checksums for production use
6. **Document your chosen pattern** in your README
7. **Test thoroughly** with various argument combinations

The pipe form (`curl | bash -s --`) provides the best balance of readability, convention, and ease of use for remote script execution.
