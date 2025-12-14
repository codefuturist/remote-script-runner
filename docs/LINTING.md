# Linting and Code Quality

This document describes the linting and code quality tools configured for Remote Script Runner.

## Quick Start

```bash
# Run all linters
make lint

# Auto-fix issues where possible
make lint-fix

# Run specific linters
make lint-shell
make lint-powershell
make lint-javascript
make lint-markdown
make lint-yaml

# Format code
make format
```

## Configured Linters

### 📜 Shell Scripts (Bash/sh)

#### ShellCheck

**Purpose:** Static analysis for shell scripts
**Configuration:** `.shellcheckrc`
**Run:** `make lint-shellcheck` or `shellcheck scripts/**/*.sh`

**Key Rules:**

- SC2034: Unused variables (disabled for sourced files)
- SC1090/SC1091: Source file following (disabled)
- SC2155: Declare and assign separately
- Enabled checks: deprecate-which, quote-safe-variables

**Install:**

```bash
# macOS
brew install shellcheck

# Ubuntu/Debian
sudo apt-get install shellcheck

# Windows
scoop install shellcheck
```

#### shfmt

**Purpose:** Shell script formatter
**Configuration:** `.editorconfig` + pre-commit
**Run:** `make format` or `shfmt -i 4 -ci -bn -sr -w scripts/**/*.sh`

**Format Style:**

- 4-space indentation
- Case indent
- Binary ops at start of line
- Space after redirect off
- Simplify code

**Install:**

```bash
# macOS
brew install shfmt

# Go
go install mvdan.cc/sh/v3/cmd/shfmt@latest
```

---

### 💻 PowerShell Scripts

#### PSScriptAnalyzer

**Purpose:** PowerShell code quality and style
**Configuration:** `.psscriptanalyzer/PSScriptAnalyzerSettings.psd1`
**Run:** `make lint-powershell` or `tools/lint-powershell.sh`

**Key Rules:**

- Consistent indentation (4 spaces)
- Brace placement (same line)
- Consistent whitespace
- Correct casing (cmdlet names)
- Comment-based help
- Avoid using aliases
- Alignment of assignment statements

**Install:**

```powershell
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
```

---

### 🟨 JavaScript

#### ESLint

**Purpose:** JavaScript linting
**Configuration:** `.eslintrc.json`
**Run:** `npm run lint:js` or `make lint-javascript`

**Key Rules:**

- 2-space indentation
- Single quotes (with escape exceptions)
- Semicolons required
- No unused variables (prefixed with `_` allowed)
- Prefer const over let/var
- Max line length: 120 characters

**Install:**

```bash
npm install
```

---

### 📝 Markdown

#### markdownlint

**Purpose:** Markdown style and best practices
**Configuration:** `.markdownlint.json`
**Run:** `npm run lint:md` or `make lint-markdown`

**Key Rules:**

- ATX-style headers (#, ##, ###)
- Fenced code blocks
- No hard tabs
- Consistent whitespace
- MD013 (line length) disabled for flexibility
- MD033 (inline HTML) allowed
- MD041 (first line heading) disabled

**Install:**

```bash
npm install
# or
npm install -g markdownlint-cli
```

---

### 📄 YAML

#### yamllint

**Purpose:** YAML syntax and style
**Configuration:** `.yamllint.yml`
**Run:** `make lint-yaml` or `yamllint .`

**Key Rules:**

- 2-space indentation
- Max line length: 120 (warning)
- Consistent comments
- No key duplicates
- Trailing spaces not allowed
- Document start not required

**Install:**

```bash
# pip
pip install yamllint

# macOS
brew install yamllint
```

---

### 🔒 Security Scanning

#### detect-secrets

**Purpose:** Prevent committing secrets
**Configuration:** `.secrets.baseline`
**Run:** Automatic via pre-commit hooks

**Features:**

- Scans for passwords, API keys, tokens
- Maintains baseline of known false positives
- Runs on every commit

**Install:**

```bash
pip install detect-secrets
```

#### gitleaks

**Purpose:** Fast secret detection
**Configuration:** Pre-commit hook
**Run:** Automatic via pre-commit hooks

**Install:**

```bash
brew install gitleaks
```

---

### 🔍 Additional Checks

#### pre-commit hooks

**Purpose:** Run multiple checks before commit
**Configuration:** `.pre-commit-config.yaml`
**Install:** `make setup-hooks` or `pre-commit install`

**Hooks:**

- Trailing whitespace
- End-of-file fixer
- YAML/JSON validation
- Large file check
- Merge conflict detection
- Executable shebangs
- ShellCheck
- shfmt
- detect-secrets
- gitleaks
- semgrep (shell best practices)
- markdownlint
- yamllint

#### commitlint

**Purpose:** Conventional commit messages
**Configuration:** `commitlint.config.js`
**Run:** Automatic via husky hooks

**Format:**

```
type(scope): subject

Examples:
  feat(ssh): add key management
  fix(backup): correct rsync flags
  docs(readme): update installation steps
```

---

## EditorConfig

**Purpose:** Consistent coding styles across editors
**Configuration:** `.editorconfig`
**Supported:** VS Code, IntelliJ, Sublime, Vim, etc.

**Settings:**

- UTF-8 encoding
- LF line endings
- Trim trailing whitespace
- Insert final newline
- Language-specific indentation

**VS Code:** Install "EditorConfig for VS Code" extension

---

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make lint` | Run all linters |
| `make lint-shellcheck` | Shell script linting |
| `make lint-powershell` | PowerShell linting |
| `make lint-javascript` | JavaScript linting |
| `make lint-markdown` | Markdown linting |
| `make lint-yaml` | YAML linting |
| `make lint-json` | JSON validation |
| `make lint-fix` | Auto-fix issues |
| `make format` | Format shell scripts |
| `make format-check` | Check formatting |

---

## npm Scripts

| Script | Description |
|--------|-------------|
| `npm run lint` | Run all JS/MD/YAML linters |
| `npm run lint:js` | ESLint |
| `npm run lint:md` | markdownlint |
| `npm run lint:yaml` | yamllint |
| `npm run lint:shell` | ShellCheck via npm |
| `npm run lint:powershell` | PSScriptAnalyzer via npm |
| `npm run lint:fix` | Auto-fix JS and MD |
| `npm run format` | Format all code |

---

## Pre-commit Workflow

1. Make changes to files
2. Stage changes: `git add .`
3. Commit: `git commit -m "feat: add new feature"`
4. Pre-commit hooks run automatically:
   - Trailing whitespace removal
   - File formatting
   - Linting
   - Secret scanning
5. If all checks pass, commit succeeds
6. If checks fail, fix issues and re-commit

---

## CI/CD Integration

### GitHub Actions

```yaml
- name: Lint Shell Scripts
  run: make lint-shellcheck

- name: Lint PowerShell
  run: make lint-powershell

- name: Lint JavaScript
  run: npm run lint:js

- name: Lint Markdown
  run: npm run lint:md

- name: Lint YAML
  run: make lint-yaml
```

### Make Target

```bash
make ci  # Runs lint + test + validate
```

---

## Disabling Rules

### ShellCheck

```bash
# Inline disable
# shellcheck disable=SC2086
variable_expansion="$unquoted"

# File-level disable
# shellcheck disable=SC2034
source ./common.sh
```

### PSScriptAnalyzer

```powershell
# Suppress specific rule
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
param()
```

### ESLint

```javascript
// Inline disable
// eslint-disable-next-line no-console
console.log('Debug message');

// File-level disable
/* eslint-disable no-console */
```

### markdownlint

```markdown
<!-- markdownlint-disable MD013 -->
This is a very long line that exceeds the usual limit.
<!-- markdownlint-enable MD013 -->
```

---

## Best Practices

1. **Run linters before committing**

   ```bash
   make lint
   ```

2. **Fix issues automatically when possible**

   ```bash
   make lint-fix
   make format
   ```

3. **Install pre-commit hooks**

   ```bash
   make setup-hooks
   ```

4. **Check formatting without changes**

   ```bash
   make format-check
   ```

5. **Use editor integration**
   - Install ShellCheck, ESLint, markdownlint plugins
   - Enable EditorConfig support
   - Configure auto-format on save

6. **Document rule exceptions**
   - Use inline comments for suppressions
   - Explain why the rule is disabled
   - Keep suppressions minimal

---

## Troubleshooting

### "Command not found: shellcheck"

Install ShellCheck:

```bash
brew install shellcheck          # macOS
sudo apt-get install shellcheck  # Ubuntu/Debian
```

### "PSScriptAnalyzer module not found"

Install the module:

```powershell
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
```

### "npm ERR! Missing script: lint:js"

Install dependencies:

```bash
npm install
```

### Pre-commit hooks not running

Install hooks:

```bash
pre-commit install
```

### EditorConfig not working

Install extension for your editor:

- VS Code: "EditorConfig for VS Code"
- IntelliJ: Built-in support
- Sublime: "EditorConfig"
- Vim: "editorconfig-vim"

---

## Summary

| File Type | Linter | Config File | Auto-Fix |
|-----------|--------|-------------|----------|
| Shell | ShellCheck | `.shellcheckrc` | No |
| Shell | shfmt | `.editorconfig` | Yes |
| PowerShell | PSScriptAnalyzer | `.psscriptanalyzer/` | Partial |
| JavaScript | ESLint | `.eslintrc.json` | Yes |
| Markdown | markdownlint | `.markdownlint.json` | Yes |
| YAML | yamllint | `.yamllint.yml` | No |
| JSON | python json.tool | - | No |
| Secrets | detect-secrets | `.secrets.baseline` | No |
| Secrets | gitleaks | Pre-commit | No |
| Commits | commitlint | `commitlint.config.js` | No |

**All linters:** `make lint`
**Auto-fix:** `make lint-fix && make format`
