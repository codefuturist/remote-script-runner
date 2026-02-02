// =============================================================================
// Commitlint Configuration
// =============================================================================
// Enforces Conventional Commits format for consistent commit history.
// https://www.conventionalcommits.org/
// =============================================================================

/** @type {import('@commitlint/types').UserConfig} */
export default {
  extends: ["@commitlint/config-conventional"],

  rules: {
    // Allow longer subjects for descriptive commits
    "header-max-length": [2, "always", 100],

    // Allow any case for subject
    "subject-case": [0],

    // Enforce type to be one of these
    "type-enum": [
      2,
      "always",
      [
        "feat",     // New feature
        "fix",      // Bug fix
        "docs",     // Documentation
        "style",    // Formatting
        "refactor", // Code restructuring
        "perf",     // Performance improvement
        "test",     // Tests
        "build",    // Build system
        "ci",       // CI/CD
        "chore",    // Maintenance
        "revert",   // Reverting
        "wip",      // Work in progress
      ],
    ],
  },

  ignores: [
    (message) => message.startsWith("Merge"),
    (message) => message.startsWith("Revert"),
    (message) => message.startsWith("Initial commit"),
  ],
};
