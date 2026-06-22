import fs from "node:fs";
import path from "node:path";
import YAML from "yaml";

const root = path.resolve(import.meta.dirname, "..");
const capabilities = YAML.parse(fs.readFileSync(path.join(root, "spec", "capabilities.yaml"), "utf8"));
const manifestPaths = {
  typescript: path.resolve(root, "..", "ts-sdk", "sdk-manifest.yaml"),
  python: path.resolve(root, "..", "python-sdk", "sdk-manifest.yaml"),
  rust: path.resolve(root, "..", "rust-sdk", "sdk-manifest.yaml"),
  elixir: path.resolve(root, "..", "elixir-sdk", "sdk-manifest.yaml")
};

const manifests = new Map();

for (const [language, manifestPath] of Object.entries(manifestPaths)) {
  if (fs.existsSync(manifestPath)) {
    manifests.set(language, YAML.parse(fs.readFileSync(manifestPath, "utf8")));
  }
}

function cell(value) {
  if (Array.isArray(value)) {
    return value.join("<br>");
  }
  return String(value ?? "");
}

function capabilityStatus(language, capabilityId) {
  const manifest = manifests.get(language);
  if (!manifest) {
    return "not_configured";
  }
  return manifest.capabilities?.[capabilityId] ?? "missing";
}

console.log("| Capability | Module | Type | Required | TypeScript | Python | Rust | Elixir | Conformance |");
console.log("| --- | --- | --- | --- | --- | --- | --- | --- | --- |");

for (const capability of capabilities.capabilities ?? []) {
  console.log(
    `| ${cell(capability.id)} | ${cell(capability.module)} | ${cell(capability.type)} | ${cell(capability.required)} | ${cell(capabilityStatus("typescript", capability.id))} | ${cell(capabilityStatus("python", capability.id))} | ${cell(capabilityStatus("rust", capability.id))} | ${cell(capabilityStatus("elixir", capability.id))} | ${cell(capability.conformanceScenarios)} |`
  );
}
