#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = path.resolve(import.meta.dirname, "..");
const version = process.argv[2];

if (!version || version === "-h" || version === "--help") {
  usage(0);
}

if (version.startsWith("v")) {
  fail("Release versions must not include a v prefix.");
}

if (version.includes("+")) {
  fail("Release versions must not include build metadata.");
}

if (!/^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?$/.test(version)) {
  fail(`Unsupported release version: ${version}`);
}

const changed = [];

updateJson("packages/ts-sdk/package.json", (json) => {
  json.version = version;
});

updateJson("packages/ts-sdk/package-lock.json", (json) => {
  json.version = version;
  if (json.packages?.[""]) {
    json.packages[""].version = version;
  }
});

replaceInFile(
  "packages/python-sdk/pyproject.toml",
  /^version = "[^"]+"/m,
  `version = "${version}"`
);

replaceInFile(
  "packages/rust-sdk/Cargo.toml",
  /^version = "[^"]+"/m,
  `version = "${version}"`
);

replaceInFile(
  "packages/rust-sdk/Cargo.lock",
  /(\[\[package\]\]\nname = "treedx"\nversion = ")[^"]+(")/m,
  `$1${version}$2`
);

replaceInFile(
  "packages/elixir-sdk/mix.exs",
  /version: "[^"]+"/,
  `version: "${version}"`
);

for (const manifest of [
  "packages/ts-sdk/sdk-manifest.yaml",
  "packages/python-sdk/sdk-manifest.yaml",
  "packages/rust-sdk/sdk-manifest.yaml",
  "packages/elixir-sdk/sdk-manifest.yaml"
]) {
  replaceInFile(manifest, /^version: .+$/m, `version: ${version}`);
}

replaceInFile(
  "apps/api/mix.exs",
  /version: "[^"]+"/,
  `version: "${version}"`
);

replaceInFile(
  "apps/api/lib/treedx/version.ex",
  /@version "[^"]+"/,
  `@version "${version}"`
);

replaceInFile(
  "apps/api/test/treedx_web/health_controller_test.exs",
  /assert json_response\(conn, 200\)\["version"\] == "[^"]+"/,
  `assert json_response(conn, 200)["version"] == "${version}"`
);

console.log(`Updated release version to ${version}:`);
for (const file of changed) {
  console.log(`- ${file}`);
}

function updateJson(relativePath, update) {
  const absolutePath = path.join(root, relativePath);
  const json = JSON.parse(fs.readFileSync(absolutePath, "utf8"));
  const before = JSON.stringify(json, null, 2) + "\n";
  update(json);
  const after = JSON.stringify(json, null, 2) + "\n";
  writeIfChanged(relativePath, before, after);
}

function replaceInFile(relativePath, pattern, replacement) {
  const absolutePath = path.join(root, relativePath);
  const before = fs.readFileSync(absolutePath, "utf8");

  if (!pattern.test(before)) {
    fail(`Could not find version pattern in ${relativePath}`);
  }

  const after = before.replace(pattern, replacement);
  writeIfChanged(relativePath, before, after);
}

function writeIfChanged(relativePath, before, after) {
  if (before === after) {
    return;
  }

  fs.writeFileSync(path.join(root, relativePath), after);
  changed.push(relativePath);
}

function usage(code) {
  const out = code === 0 ? console.log : console.error;
  out("Usage: scripts/release/bump-release-version.ts VERSION");
  out("");
  out("VERSION must be a semantic version without a v prefix, for example 0.1.2.");
  process.exit(code);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
