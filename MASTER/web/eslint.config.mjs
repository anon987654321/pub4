// Airbnb-inspired lint for MASTER web/public vanilla JS.
import js from "@eslint/js";
import globals from "globals";

const browser = {
  languageOptions: {
    ecmaVersion: 2022,
    globals: {
      ...globals.browser,
      MASTER_RUNTIME: "readonly",
      MASTER_ASSET_PATHS: "readonly",
      MASTERVisual: "readonly",
      MASTER_FACE: "readonly",
      ParticleKernel: "readonly",
      Face3DPreview: "readonly",
    },
  },
  rules: {
    "no-var": "error",
    "prefer-const": "error",
    eqeqeq: ["error", "always"],
    curly: ["error", "multi-line"],
    "no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
    semi: ["error", "always"],
    quotes: ["error", "double", { avoidEscape: true }],
    "object-shorthand": "error",
    "prefer-arrow-callback": "error",
  },
};

export default [
  {
    ignores: [
      "public/assets/**",
      "public/three.face.module.js",
      "public/face.runtime.js",
      "public/face.modules.bundle.js",
      "public/face_vision.bundle.js",
    ],
  },
  js.configs.recommended,
  {
    ...browser,
    files: ["public/**/*.js"],
    languageOptions: {
      ...browser.languageOptions,
      sourceType: "script",
    },
  },
  {
    ...browser,
    files: ["public/face3d_*.js"],
    languageOptions: {
      ...browser.languageOptions,
      sourceType: "module",
    },
  },
];
