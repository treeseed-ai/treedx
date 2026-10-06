import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import YAML from "yaml";

const root = path.resolve(import.meta.dirname, "..");
const repoRoot = path.resolve(root, "..", "..");
const openapiPath = path.join(repoRoot, "docs", "api", "openapi.yaml");

function readYaml(filePath) {
  return YAML.parse(fs.readFileSync(filePath, "utf8"));
}

function operationKey(method, apiPath) {
  return `${method.toUpperCase()} ${apiPath}`;
}

function fail(message) {
  console.error(`openapi coverage failed: ${message}`);
  process.exitCode = 1;
}

const openapi = readYaml(openapiPath);
const openapiOperations = new Set();

for (const [apiPath, methods] of Object.entries(openapi.paths ?? {})) {
  if (!apiPath.startsWith("/api/v1/")) {
    continue;
  }
  for (const method of Object.keys(methods)) {
    openapiOperations.add(operationKey(method, apiPath));
  }
}

const capabilities = readYaml(path.join(root, "spec", "capabilities.yaml"));
const endpoints = readYaml(path.join(root, "spec", "endpoints.yaml"));
const architecture = readYaml(path.join(root, "spec", "architecture.yaml"));
const coverageExceptions = readYaml(path.join(root, "spec", "openapi-coverage-exceptions.yaml"));
const declaredEndpoints = new Set();
const requiredModules = new Set(architecture.requiredModules ?? []);
const moduleCapabilityCounts = new Map((architecture.requiredModules ?? []).map((moduleName) => [moduleName, 0]));

for (const capability of capabilities.capabilities ?? []) {
  if (capability.required === true) {
    if (!Array.isArray(capability.conformanceScenarios) || capability.conformanceScenarios.length === 0) {
      fail(`required capability ${capability.id} has no conformance scenarios`);
    }

    if (!requiredModules.has(capability.module)) {
      fail(`required capability ${capability.id} uses undeclared module ${capability.module}`);
    }
  }

  if (moduleCapabilityCounts.has(capability.module)) {
    moduleCapabilityCounts.set(capability.module, moduleCapabilityCounts.get(capability.module) + 1);
  }

  for (const endpoint of capability.endpoints ?? []) {
    declaredEndpoints.add(endpoint);
  }
}

for (const [group, groupEndpoints] of Object.entries(endpoints.groups ?? {})) {
  for (const endpoint of groupEndpoints ?? []) {
    declaredEndpoints.add(endpoint);
    if (!openapiOperations.has(endpoint)) {
      fail(`declared endpoint in group ${group} is not in OpenAPI: ${endpoint}`);
    }
  }
}

for (const capability of capabilities.capabilities ?? []) {
  for (const endpoint of capability.endpoints ?? []) {
    if (!openapiOperations.has(endpoint)) {
      fail(`declared endpoint in capability ${capability.id} is not in OpenAPI: ${endpoint}`);
    }
  }
}

const uncovered = [...openapiOperations].filter((endpoint) => !declaredEndpoints.has(endpoint)).sort();
const classifiedExceptions = new Map();

for (const exception of coverageExceptions.exceptions ?? []) {
  const endpoint = String(exception.endpoint ?? "");
  const reason = String(exception.reason ?? "").trim();
  const languages = Array.isArray(exception.languages) ? exception.languages.map(String).sort() : [];
  if (!openapiOperations.has(endpoint)) {
    fail(`coverage exception is not in OpenAPI: ${endpoint}`);
  }
  if (declaredEndpoints.has(endpoint)) {
    fail(`coverage exception is already declared by the SDK spec: ${endpoint}`);
  }
  if (reason.length < 20) {
    fail(`coverage exception requires a specific reviewed reason: ${endpoint}`);
  }
  const expectedLanguages = [...(architecture.languageSdks ?? [])].map(String).sort();
  if (JSON.stringify(languages) !== JSON.stringify(expectedLanguages)) {
    fail(`coverage exception must classify every declared language SDK: ${endpoint}`);
  }
  if (classifiedExceptions.has(endpoint)) {
    fail(`duplicate coverage exception: ${endpoint}`);
  }
  classifiedExceptions.set(endpoint, exception);
}

const unclassified = uncovered.filter((endpoint) => !classifiedExceptions.has(endpoint));
const staleExceptions = [...classifiedExceptions.keys()].filter((endpoint) => !uncovered.includes(endpoint));

for (const endpoint of unclassified) {
  fail(`unclassified public OpenAPI operation: ${endpoint}`);
}
for (const endpoint of staleExceptions) {
  fail(`stale coverage exception: ${endpoint}`);
}

console.log(`Declared SDK endpoint count: ${declaredEndpoints.size}`);
console.log(`OpenAPI operation count: ${openapiOperations.size}`);
console.log(`Classified unavailable OpenAPI operation count: ${uncovered.length}`);
console.log("Required module coverage:");
for (const moduleName of architecture.requiredModules ?? []) {
  const count = moduleCapabilityCounts.get(moduleName) ?? 0;
  console.log(`- ${moduleName}: ${count} ${count === 1 ? "capability" : "capabilities"}`);
}

if (uncovered.length > 0) {
  console.log("Reviewed unavailable OpenAPI operations:");
  for (const endpoint of uncovered) {
    console.log(`- ${endpoint}: ${classifiedExceptions.get(endpoint)?.reason ?? "UNCLASSIFIED"}`);
  }
}

if (!process.exitCode) {
  console.log("openapi coverage check passed");
}
