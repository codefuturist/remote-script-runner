// =============================================================================
// lint-staged Configuration
// =============================================================================
// Runs formatters, linters, and security checks on staged files.
// Supports all major languages with graceful fallback when tools aren't installed.
// https://github.com/lint-staged/lint-staged
// =============================================================================

/**
 * Helper: Run command only if tool is installed
 * @param {string} tool - Tool name to check
 * @param {string} cmd - Command to run if tool exists
 * @param {string} [msg] - Info message if tool not found
 */
const ifInstalled = (tool, cmd, msg = "") =>
  `sh -c 'command -v ${tool} >/dev/null 2>&1 && ${cmd} || ${msg ? `echo "${msg}"` : "true"}'`;

/** @type {import('lint-staged').Configuration} */
export default {
  // ═══════════════════════════════════════════════════════════════════════════
  // Security Checks
  // ═══════════════════════════════════════════════════════════════════════════
  "!(**/node_modules/**)": [
    // Block commits containing private keys
    (files) =>
      files
        .filter((f) => !f.endsWith(".mjs") && !f.endsWith(".js"))
        .map((f) => `sh -c 'grep -l "PRIVATE KEY" "${f}" 2>/dev/null && echo "❌ Private key in: ${f}" && exit 1 || true'`),
  ],

  // ═══════════════════════════════════════════════════════════════════════════
  // JavaScript / TypeScript
  // ═══════════════════════════════════════════════════════════════════════════
  "*.{js,mjs,cjs,jsx,ts,tsx}": [
    "pnpm exec prettier --write",
    "pnpm exec eslint --fix --max-warnings=0",
  ],

  // ═══════════════════════════════════════════════════════════════════════════
  // Python (ruff preferred, fallback to black)
  // ═══════════════════════════════════════════════════════════════════════════
  "*.py": (files) => {
    const fileArgs = files.join(" ");
    return [
      ifInstalled("ruff", `ruff format ${fileArgs}`),
      ifInstalled("ruff", `ruff check --fix ${fileArgs}`),
    ];
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // Go
  // ═══════════════════════════════════════════════════════════════════════════
  "*.go": (files) => {
    const fileArgs = files.join(" ");
    return [
      ifInstalled("gofmt", `gofmt -w ${fileArgs}`),
      ifInstalled("goimports", `goimports -w ${fileArgs}`),
    ];
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // Rust
  // ═══════════════════════════════════════════════════════════════════════════
  "*.rs": (files) => {
    const fileArgs = files.join(" ");
    return [ifInstalled("rustfmt", `rustfmt --edition 2021 ${fileArgs}`)];
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // Swift
  // ═══════════════════════════════════════════════════════════════════════════
  "*.swift": (files) => {
    const fileArgs = files.join(" ");
    return [
      ifInstalled("swiftformat", `swiftformat ${fileArgs}`),
      ifInstalled("swiftlint", `swiftlint lint --fix --quiet ${fileArgs} || true`),
    ];
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // Shell
  // ═══════════════════════════════════════════════════════════════════════════
  "*.sh": (files) => {
    const fileArgs = files.join(" ");
    return [
      ifInstalled("shfmt", `shfmt -i 2 -ci -sr -w ${fileArgs}`),
      ifInstalled("shellcheck", `shellcheck -x ${fileArgs} 2>/dev/null || true`),
    ];
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // Data/Config Files
  // ═══════════════════════════════════════════════════════════════════════════
  "*.{json,jsonc,json5}": ["pnpm exec prettier --write"],
  "*.{yaml,yml}": ["pnpm exec prettier --write"],
  "*.{md,mdx}": ["pnpm exec prettier --write"],
};
