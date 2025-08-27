export default [
  {
    files: ["**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "script",
      globals: {
        window: "readonly",
        document: "readonly",
        console: "readonly",
        Chart: "readonly",
        localStorage: "readonly",
        fetch: "readonly",
        URL: "readonly",
        Blob: "readonly",
        setTimeout: "readonly",
        clearTimeout: "readonly",
        setInterval: "readonly",
        clearInterval: "readonly",
        dateFns: "readonly",
        navigator: "readonly",
      },
    },
    rules: {
      // Error prevention
      "no-unused-vars": "warn",
      "no-undef": "error",
      "no-console": "off", // Allow console for debugging

      // Best practices
      eqeqeq: "warn",
      "no-eval": "error",
      "no-implied-eval": "error",
      "no-new-func": "error",

      // Code quality
      "prefer-const": "warn",
      "no-var": "warn",
      curly: "warn",

      // Async/await
      "require-await": "warn",
      "no-async-promise-executor": "error",
    },
  },
];
