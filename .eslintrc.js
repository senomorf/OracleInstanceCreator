// Legacy ESLint configuration for super-linter compatibility
// This file is required for older linting tools that don't support flat config
module.exports = {
  env: {
    browser: true,
    es2022: true
  },
  parserOptions: {
    ecmaVersion: 2022,
    sourceType: 'script'
  },
  globals: {
    Chart: 'readonly',
    dateFns: 'readonly'
  },
  rules: {
    // Error prevention
    'no-unused-vars': 'warn',
    'no-undef': 'error',
    'no-console': 'off', // Allow console for debugging

    // Best practices
    eqeqeq: 'warn',
    'no-eval': 'error',
    'no-implied-eval': 'error',
    'no-new-func': 'error',

    // Code quality
    'prefer-const': 'warn',
    'no-var': 'warn',
    curly: 'warn',

    // Async/await
    'require-await': 'warn',
    'no-async-promise-executor': 'error'
  }
};