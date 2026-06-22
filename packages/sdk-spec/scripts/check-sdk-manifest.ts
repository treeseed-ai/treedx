import Ajv from "ajv/dist/2020.js";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import YAML from "yaml";

const root = path.resolve(import.meta.dirname, "..");
const manifestPaths = [
  path.resolve(root, "..", "ts-sdk", "sdk-manifest.yaml"),
  path.resolve(root, "..", "python-sdk", "sdk-manifest.yaml"),
  path.resolve(root, "..", "rust-sdk", "sdk-manifest.yaml"),
  path.resolve(root, "..", "elixir-sdk", "sdk-manifest.yaml")
];

const existingManifests = manifestPaths.filter((manifestPath) => fs.existsSync(manifestPath));

if (existingManifests.length === 0) {
  console.log("sdk manifest check not configured: no language SDK manifests found");
  process.exit(0);
}

const schema = JSON.parse(fs.readFileSync(path.join(root, "schemas", "sdk-manifest.schema.json"), "utf8"));
const architecture = YAML.parse(fs.readFileSync(path.join(root, "spec", "architecture.yaml"), "utf8"));
const testing = YAML.parse(fs.readFileSync(path.join(root, "spec", "testing.yaml"), "utf8"));
const capabilities = YAML.parse(fs.readFileSync(path.join(root, "spec", "capabilities.yaml"), "utf8"));
const requiredModules = architecture.requiredModules ?? [];
const validTestStatuses = new Set(testing.manifestRequirements?.testLayout?.validStatuses ?? []);
const allowedModuleStatuses = new Set(["implemented", "partial", "planned", "not_applicable"]);
const allowedCapabilityStatuses = new Set(["implemented", "partial", "planned", "not_applicable"]);
const requiredCapabilities = (capabilities.capabilities ?? []).filter((capability) => capability.required === true);
const ajv = new Ajv({ allErrors: true, strict: false });
const validate = ajv.compile(schema);

function hasNonGitkeepFile(directoryPath) {
  if (!fs.existsSync(directoryPath) || !fs.statSync(directoryPath).isDirectory()) {
    return false;
  }

  for (const entry of fs.readdirSync(directoryPath, { withFileTypes: true })) {
    const entryPath = path.join(directoryPath, entry.name);
    if (entry.isDirectory()) {
      if (hasNonGitkeepFile(entryPath)) {
        return true;
      }
    } else if (entry.isFile() && entry.name !== ".gitkeep") {
      return true;
    }
  }

  return false;
}

for (const manifestPath of existingManifests) {
  const manifest = YAML.parse(fs.readFileSync(manifestPath, "utf8"));
  const packageRoot = path.dirname(manifestPath);
  if (!validate(manifest)) {
    console.error(`${path.relative(root, manifestPath)} does not match sdk-manifest.schema.json`);
    console.error(ajv.errorsText(validate.errors, { separator: "\n" }));
    process.exitCode = 1;
  }

  for (const moduleName of requiredModules) {
    if (!manifest.modules || !Object.hasOwn(manifest.modules, moduleName)) {
      console.error(`${path.relative(root, manifestPath)} is missing module status for ${moduleName}`);
      process.exitCode = 1;
      continue;
    }

    if (!allowedModuleStatuses.has(manifest.modules[moduleName])) {
      console.error(`${path.relative(root, manifestPath)} has invalid module status for ${moduleName}: ${manifest.modules[moduleName]}`);
      process.exitCode = 1;
    }
  }

  for (const capability of requiredCapabilities) {
    if (!manifest.capabilities || !Object.hasOwn(manifest.capabilities, capability.id)) {
      console.error(`${path.relative(root, manifestPath)} is missing capability status for ${capability.id}`);
      process.exitCode = 1;
      continue;
    }

    const capabilityStatus = manifest.capabilities[capability.id];
    if (!allowedCapabilityStatuses.has(capabilityStatus)) {
      console.error(`${path.relative(root, manifestPath)} has invalid capability status for ${capability.id}: ${capabilityStatus}`);
      process.exitCode = 1;
      continue;
    }

    const moduleStatus = manifest.modules?.[capability.module];
    if (capabilityStatus === "implemented" && moduleStatus !== "implemented" && moduleStatus !== "partial") {
      console.error(`${path.relative(root, manifestPath)} marks capability ${capability.id} implemented but module ${capability.module} is ${moduleStatus}`);
      process.exitCode = 1;
    }

    if (moduleStatus === "not_applicable" && capabilityStatus === "implemented") {
      console.error(`${path.relative(root, manifestPath)} marks module ${capability.module} not_applicable but required capability ${capability.id} implemented`);
      process.exitCode = 1;
    }
  }

  const layout = testing.targetLayouts?.[manifest.language];
  if (!layout) {
    console.error(`${path.relative(root, manifestPath)} has no target layout for language ${manifest.language}`);
    process.exitCode = 1;
    continue;
  }

  for (const rootName of testing.manifestRequirements?.testLayout?.requiredRoots ?? []) {
    if (!manifest.testLayout || !Object.hasOwn(manifest.testLayout, rootName)) {
      console.error(`${path.relative(root, manifestPath)} is missing testLayout status for ${rootName}`);
      process.exitCode = 1;
      continue;
    }

    const status = manifest.testLayout[rootName];
    if (!validTestStatuses.has(status)) {
      console.error(`${path.relative(root, manifestPath)} has invalid testLayout status for ${rootName}: ${status}`);
      process.exitCode = 1;
      continue;
    }

    const rootPath = path.join(packageRoot, layout.root, rootName);
    if (status === "implemented") {
      if (!fs.existsSync(rootPath) || !fs.statSync(rootPath).isDirectory()) {
        console.error(`${path.relative(root, manifestPath)} marks ${rootName} implemented but ${path.relative(packageRoot, rootPath)} does not exist`);
        process.exitCode = 1;
      } else if (!hasNonGitkeepFile(rootPath)) {
        console.error(`${path.relative(root, manifestPath)} marks ${rootName} implemented but ${path.relative(packageRoot, rootPath)} has no test files`);
        process.exitCode = 1;
      }
    }

    if (status === "partial" && (!fs.existsSync(rootPath) || !fs.statSync(rootPath).isDirectory())) {
      console.error(`${path.relative(root, manifestPath)} marks ${rootName} partial but ${path.relative(packageRoot, rootPath)} does not exist`);
      process.exitCode = 1;
    }
  }

  for (const rootName of testing.manifestRequirements?.testLayout?.optionalRoots ?? []) {
    if (!manifest.testLayout || !Object.hasOwn(manifest.testLayout, rootName)) {
      continue;
    }

    const status = manifest.testLayout[rootName];
    if (!validTestStatuses.has(status)) {
      console.error(`${path.relative(root, manifestPath)} has invalid optional testLayout status for ${rootName}: ${status}`);
      process.exitCode = 1;
    }

    if (rootName === "compatibility" && status === "implemented") {
      console.warn(`${path.relative(root, manifestPath)} declares implemented compatibility tests; compatibility is downstream-specific and must not define TreeDX SDK architecture`);
    }
  }
}

if (!process.exitCode) {
  console.log(`sdk manifest check passed for ${existingManifests.length} manifest(s)`);
}
