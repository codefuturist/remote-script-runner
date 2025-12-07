// Commitlint configuration
// https://commitlint.js.org/
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // Type must be one of these
    'type-enum': [
      2,
      'always',
      [
        'feat',     // New feature
        'fix',      // Bug fix
        'docs',     // Documentation only
        'style',    // Formatting, no code change
        'refactor', // Code change without feature/fix
        'test',     // Adding/updating tests
        'chore',    // Maintenance tasks
        'ci',       // CI/CD changes
        'perf',     // Performance improvement
        'revert',   // Revert previous commit
        'build',    // Build system changes
      ],
    ],
    // Scope is optional but if provided, should be one of these
    'scope-enum': [
      1, // Warning only
      'always',
      [
        'scripts',  // Script files
        'rsr',      // Main rsr command
        'lib',      // Library files
        'test',     // Test files
        'ci',       // CI configuration
        'docs',     // Documentation
        'deps',     // Dependencies
        'config',   // Configuration files
      ],
    ],
    // Subject (description) rules
    'subject-case': [2, 'always', 'lower-case'],
    'subject-empty': [2, 'never'],
    'subject-max-length': [2, 'always', 72],
    // Header rules
    'header-max-length': [2, 'always', 100],
    // Body rules
    'body-max-line-length': [1, 'always', 100], // Warning only
  },
};

