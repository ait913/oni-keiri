import { existsSync, readFileSync } from "node:fs";
import { defineConfig } from "vitest/config";

if (existsSync(".env.test")) {
  for (const line of readFileSync(".env.test", "utf8").split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)\s*$/);
    if (match) process.env[match[1]] = match[2];
  }
}

export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
    projects: [
      {
        test: {
          name: "unit",
          include: ["tests/unit/**/*.test.ts"],
        },
      },
      {
        test: {
          name: "api",
          include: ["tests/api/**/*.test.ts"],
          globalSetup: ["tests/setup/global.ts"],
        },
      },
    ],
  },
});
