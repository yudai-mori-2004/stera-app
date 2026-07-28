import { defineConfig } from "oxlint";
import core from "ultracite/oxlint/core";

export default defineConfig({
  extends: [core],
  ignorePatterns: [
    ...core.ignorePatterns,
    "apps/mobile/**",
    "**/dist/**",
    "**/migrations/**",
  ],
  rules: {
    // Spotty house style.
    "sort-keys": "off",
    "typescript/consistent-type-definitions": ["error", "type"],

    // Intentional deviations for this codebase:
    // - schema/types barrels are required by the monorepo contract
    // - R2 ListParts pagination must be sequential (marker depends on prior page)
    // - UUIDv5 clientUploadId normalization needs bitwise version/variant bits
    "oxc/no-barrel-file": "off",
    "eslint/no-await-in-loop": "off",
    "eslint/no-bitwise": "off",
    "eslint/no-plusplus": "off",
    "eslint/require-unicode-regexp": "off",
    "unicorn/prefer-string-replace-all": "off",
    "unicorn/text-encoding-identifier-case": "off",
    "node/callback-return": "off",
  },
});
