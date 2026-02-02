// =============================================================================
// ESLint Configuration (Flat Config)
// =============================================================================
// https://eslint.org/docs/latest/use/configure/configuration-files-new
// =============================================================================

import js from "@eslint/js";
import globals from "globals";


/** @type {import('eslint').Linter.Config[]} */
export default [
  // Ignore patterns
  {
    ignores: [
      "node_modules/**",
      "dist/**",
      "build/**",
      "coverage/**",
      "*.min.js",
    ],
  },

  // Base JS config
  js.configs.recommended,

  // Custom rules for all files
  {
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: {
        ...globals.node,
        ...globals.browser,
      },
    },
    rules: {
      // Error prevention
      "no-unused-vars": ["warn", { argsIgnorePattern: "^_" }],
      "no-console": "off",
      
      // Best practices
      "eqeqeq": ["error", "always"],
      "curly": ["error", "multi-line"],
      "no-var": "error",
      "prefer-const": "warn",
    },
  },
];
