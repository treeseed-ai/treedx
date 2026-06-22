import Ajv from "ajv/dist/2020.js";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import YAML from "yaml";

const root = path.resolve(import.meta.dirname, "..");
const specDir = path.join(root, "spec");
const schemaDir = path.join(root, "schemas");
const conformanceScenarioDir = path.join(root, "conformance", "scenarios");

const schemaBySpec = new Map([
  ["architecture.yaml", "architecture.schema.json"],
  ["auth.yaml", "auth.schema.json"],
  ["binary.yaml", "binary.schema.json"],
  ["capabilities.yaml", "capability.schema.json"],
  ["endpoints.yaml", "endpoint.schema.json"],
  ["errors.yaml", "error.schema.json"],
  ["pagination.yaml", "pagination.schema.json"],
  ["testing.yaml", "testing.schema.json"],
  ["conformance.yaml", "scenario.schema.json"]
]);

function readYaml(filePath) {
  const source = fs.readFileSync(filePath, "utf8");
  return YAML.parse(source);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function fail(message) {
  console.error(`sdk-spec validation failed: ${message}`);
  process.exitCode = 1;
}

const ajv = new Ajv({ allErrors: true, strict: false });
const parsedSpecs = new Map();

for (const fileName of fs.readdirSync(specDir).filter((name) => name.endsWith(".yaml")).sort()) {
  const specPath = path.join(specDir, fileName);
  let data;

  try {
    data = readYaml(specPath);
    parsedSpecs.set(fileName, data);
  } catch (error) {
    fail(`${fileName} does not parse as YAML: ${error.message}`);
    continue;
  }

  const schemaName = schemaBySpec.get(fileName);
  if (!schemaName) {
    continue;
  }

  const schema = readJson(path.join(schemaDir, schemaName));
  const validate = ajv.compile(schema);
  if (!validate(data)) {
    fail(`${fileName} does not match ${schemaName}: ${ajv.errorsText(validate.errors, { separator: "\n" })}`);
  }
}

const architecture = parsedSpecs.get("architecture.yaml");
const auth = parsedSpecs.get("auth.yaml");
const binary = parsedSpecs.get("binary.yaml");
const capabilities = parsedSpecs.get("capabilities.yaml");
const endpoints = parsedSpecs.get("endpoints.yaml");
const errors = parsedSpecs.get("errors.yaml");
const pagination = parsedSpecs.get("pagination.yaml");
const testing = parsedSpecs.get("testing.yaml");
const conformance = parsedSpecs.get("conformance.yaml");
const openapi = readYaml(path.resolve(root, "..", "..", "docs", "api", "openapi.yaml"));

const sharedEndpointAllowlist = new Set([
  "GET /api/v1/health",
  "POST /api/v1/context/build",
  "POST /api/v1/graph/query"
]);

const requiredModules = new Set(architecture?.requiredModules ?? []);
const moduleRecords = new Map((architecture?.modules ?? []).map((module) => [module.name, module]));
const requiredPorts = new Set(architecture?.requiredPorts ?? []);
const portRecords = new Map((architecture?.ports ?? []).map((port) => [port.id, port]));
const requiredCoreConcepts = new Set(architecture?.requiredCoreConcepts ?? []);
const coreConceptRecords = new Map((architecture?.coreConcepts ?? []).map((concept) => [concept.name, concept]));
const capabilityRecords = new Map();
const capabilityEndpoints = new Map();
const endpointGroupRecords = new Set();

for (const groupEndpoints of Object.values(endpoints?.groups ?? {})) {
  for (const endpoint of groupEndpoints ?? []) {
    endpointGroupRecords.add(endpoint);
  }
}

if (capabilities?.capabilities) {
  const seenCapabilityIds = new Set();

  for (const capability of capabilities.capabilities) {
    if (seenCapabilityIds.has(capability.id)) {
      fail(`duplicate capability id: ${capability.id}`);
    }
    seenCapabilityIds.add(capability.id);
    capabilityRecords.set(capability.id, capability);

    if (!requiredModules.has(capability.module)) {
      fail(`capability ${capability.id} uses undeclared module ${capability.module}`);
    }

    if (capability.status === "required" && capability.required !== true) {
      fail(`capability ${capability.id} has status required but required is not true`);
    }

    if (capability.required === true && (!Array.isArray(capability.conformanceScenarios) || capability.conformanceScenarios.length === 0)) {
      fail(`required capability ${capability.id} has no conformance scenarios`);
    }

    for (const endpoint of capability.endpoints ?? []) {
      if (!endpointGroupRecords.has(endpoint)) {
        fail(`capability ${capability.id} endpoint is missing from endpoints.yaml: ${endpoint}`);
      }

      const owners = capabilityEndpoints.get(endpoint) ?? [];
      owners.push(capability.id);
      capabilityEndpoints.set(endpoint, owners);
    }
  }
}

for (const [endpoint, owners] of capabilityEndpoints.entries()) {
  if (owners.length > 1 && !sharedEndpointAllowlist.has(endpoint)) {
    fail(`endpoint ${endpoint} is referenced by multiple capabilities: ${owners.join(", ")}`);
  }
}

for (const endpoint of endpointGroupRecords) {
  if (!capabilityEndpoints.has(endpoint)) {
    fail(`endpoint ${endpoint} from endpoints.yaml is not referenced by any capability`);
  }
}

if (errors) {
  const openapiErrorCodes = new Set(openapi?.components?.schemas?.TreeDxErrorCode?.enum ?? []);
  const stableCodes = new Set(errors.stableCodes ?? []);
  const requiredErrorFields = ["status", "code", "message", "details", "payload"];

  for (const code of stableCodes) {
    if (!openapiErrorCodes.has(code)) {
      fail(`errors.yaml stable code is missing from OpenAPI TreeDxErrorCode enum: ${code}`);
    }
  }

  for (const code of openapiErrorCodes) {
    if (!stableCodes.has(code)) {
      fail(`OpenAPI TreeDxErrorCode enum is missing from errors.yaml stableCodes: ${code}`);
    }
  }

  if (errors.networkError?.code !== "network_error") {
    fail("errors.networkError.code must be network_error");
  }

  if (!stableCodes.has("network_error")) {
    fail("errors.stableCodes must include network_error");
  }

  for (const fieldName of requiredErrorFields) {
    if (!Object.hasOwn(errors.fields ?? {}, fieldName)) {
      fail(`errors.fields is missing required field ${fieldName}`);
    }
  }
}

if (auth) {
  const authCapability = capabilityRecords.get("auth.whoami");
  const effectiveScope = auth.auth?.effectiveScope;

  if (effectiveScope?.capabilityId !== "auth.whoami") {
    fail("auth.effectiveScope.capabilityId must be auth.whoami");
  }

  if (!authCapability?.endpoints?.includes(effectiveScope?.endpoint)) {
    fail(`auth.effectiveScope.endpoint must be listed by capability auth.whoami: ${effectiveScope?.endpoint}`);
  }

  if (auth.auth?.bearerToken?.header !== "Authorization") {
    fail("auth.bearerToken.header must be Authorization");
  }

  if (auth.auth?.bearerToken?.scheme !== "Bearer") {
    fail("auth.bearerToken.scheme must be Bearer");
  }

  if (auth.auth?.productionIdentity?.requestJsonAllowed !== false) {
    fail("auth.productionIdentity.requestJsonAllowed must be false");
  }
}

if (pagination) {
  const pageFields = new Set(pagination.pageFields ?? []);

  if (pagination.concepts?.TreeDxCursor?.encoding !== "opaque") {
    fail("pagination TreeDxCursor.encoding must be opaque");
  }

  for (const fieldName of ["items", "nextCursor", "hasMore"]) {
    if (!pageFields.has(fieldName)) {
      fail(`pagination.pageFields must include ${fieldName}`);
    }
  }

  if (!capabilityRecords.get("query.repository")?.conformanceScenarios?.includes("query.pagination")) {
    fail("query.repository must include query.pagination conformance scenario");
  }
}

if (binary) {
  const binaryModes = new Set(binary.binaryModes ?? []);
  const multipartEndpoints = new Set(binary.operations?.multipartUpload?.endpoints ?? []);
  const requiredMultipartEndpoints = [
    "POST /api/v1/workspaces/{workspace_id}/blobs/uploads",
    "PUT /api/v1/workspaces/{workspace_id}/blobs/uploads/{upload_id}/parts/{part_number}",
    "POST /api/v1/workspaces/{workspace_id}/blobs/uploads/{upload_id}/complete",
    "DELETE /api/v1/workspaces/{workspace_id}/blobs/uploads/{upload_id}"
  ];

  if (!binaryModes.has("multipart")) {
    fail("binary.binaryModes must include multipart");
  }

  for (const [operationName, operation] of Object.entries(binary.operations ?? {})) {
    const capability = capabilityRecords.get(operation.capabilityId);
    if (!capability) {
      fail(`binary operation ${operationName} references missing capability ${operation.capabilityId}`);
      continue;
    }

    for (const endpoint of operation.endpoints ?? []) {
      if (!capability.endpoints?.includes(endpoint)) {
        fail(`binary operation ${operationName} endpoint is missing from capability ${operation.capabilityId}: ${endpoint}`);
      }
    }
  }

  if (!capabilityRecords.get("blobs.binary")?.conformanceScenarios?.includes("blobs.read_write_download_upload")) {
    fail("blobs.binary must include blobs.read_write_download_upload conformance scenario");
  }

  if (!capabilityRecords.get("blobs.multipart")?.conformanceScenarios?.includes("blobs.multipart_upload")) {
    fail("blobs.multipart must include blobs.multipart_upload conformance scenario");
  }

  for (const endpoint of requiredMultipartEndpoints) {
    if (!multipartEndpoints.has(endpoint)) {
      fail(`binary multipartUpload operation is missing endpoint ${endpoint}`);
    }
  }
}

for (const moduleName of requiredModules) {
  if (!moduleRecords.has(moduleName)) {
    fail(`required module ${moduleName} is missing from architecture.modules`);
  }

  const hasCapability = [...capabilityRecords.values()].some((capability) => capability.module === moduleName);
  if (!hasCapability) {
    fail(`required module ${moduleName} has no direct capability entry`);
  }
}

for (const moduleRecord of moduleRecords.values()) {
  if (!requiredModules.has(moduleRecord.name)) {
    fail(`architecture.modules contains non-required module ${moduleRecord.name}`);
  }

  for (const capabilityId of moduleRecord.capabilityIds ?? []) {
    if (!capabilityRecords.has(capabilityId)) {
      fail(`module ${moduleRecord.name} references missing capability ${capabilityId}`);
    }
  }

  for (const portId of moduleRecord.ownsPorts ?? []) {
    if (!requiredPorts.has(portId)) {
      fail(`module ${moduleRecord.name} owns undeclared port ${portId}`);
    }
  }
}

const moduleCapabilityOwners = new Map();
for (const moduleRecord of moduleRecords.values()) {
  for (const capabilityId of moduleRecord.capabilityIds ?? []) {
    const owner = moduleCapabilityOwners.get(capabilityId);
    if (owner) {
      fail(`capability ${capabilityId} is owned by multiple modules: ${owner}, ${moduleRecord.name}`);
    }
    moduleCapabilityOwners.set(capabilityId, moduleRecord.name);
  }
}

for (const capabilityId of capabilityRecords.keys()) {
  if (!moduleCapabilityOwners.has(capabilityId)) {
    fail(`capability ${capabilityId} is not owned by any architecture module`);
  }
}

for (const moduleRecord of moduleRecords.values()) {
  const declaredCapabilityIds = [...(moduleRecord.capabilityIds ?? [])].sort();
  const actualCapabilityIds = [...capabilityRecords.values()]
    .filter((capability) => capability.module === moduleRecord.name)
    .map((capability) => capability.id)
    .sort();

  if (declaredCapabilityIds.join("\0") !== actualCapabilityIds.join("\0")) {
    fail(
      `module ${moduleRecord.name} capabilityIds must exactly match capabilities.yaml ownership: declared ${declaredCapabilityIds.join(", ") || "(none)"}, actual ${actualCapabilityIds.join(", ") || "(none)"}`
    );
  }
}

for (const portId of requiredPorts) {
  const portRecord = portRecords.get(portId);
  if (!portRecord) {
    fail(`required port ${portId} is missing from architecture.ports`);
    continue;
  }

  if (!Array.isArray(portRecord.ownerModules) || portRecord.ownerModules.length === 0) {
    fail(`required port ${portId} has no owner modules`);
  }

  for (const ownerModule of portRecord.ownerModules ?? []) {
    if (!requiredModules.has(ownerModule)) {
      fail(`port ${portId} has invalid owner module ${ownerModule}`);
    }
  }
}

for (const portId of portRecords.keys()) {
  if (!requiredPorts.has(portId)) {
    fail(`architecture.ports contains non-required port ${portId}`);
  }
}

for (const conceptName of requiredCoreConcepts) {
  const conceptRecord = coreConceptRecords.get(conceptName);
  if (!conceptRecord) {
    fail(`required core concept ${conceptName} is missing from architecture.coreConcepts`);
    continue;
  }

  if (!requiredModules.has(conceptRecord.ownerModule)) {
    fail(`core concept ${conceptName} has invalid owner module ${conceptRecord.ownerModule}`);
  }
}

for (const conceptRecord of coreConceptRecords.values()) {
  if (!requiredModules.has(conceptRecord.ownerModule)) {
    fail(`core concept ${conceptRecord.name} has invalid owner module ${conceptRecord.ownerModule}`);
  }
}

if (testing?.sharedTestRoots && testing?.requiredTestCategories) {
  for (const rootName of testing.sharedTestRoots) {
    if (!Object.hasOwn(testing.requiredTestCategories, rootName)) {
      fail(`shared test root ${rootName} is missing from requiredTestCategories`);
    }
  }
}

if (testing) {
  const sharedTestRoots = new Set(testing.sharedTestRoots ?? []);
  const optionalTestRoots = new Set(testing.optionalTestRoots ?? []);
  const requiredCategories = testing.requiredTestCategories ?? {};
  const manifestTestLayout = testing.manifestRequirements?.testLayout ?? {};
  const languageRoots = testing.languageRoots ?? {};
  const targetLayouts = testing.targetLayouts ?? {};

  for (const rootName of manifestTestLayout.requiredRoots ?? []) {
    if (!sharedTestRoots.has(rootName)) {
      fail(`manifest required test root ${rootName} is missing from sharedTestRoots`);
    }
  }

  for (const rootName of manifestTestLayout.optionalRoots ?? []) {
    if (!optionalTestRoots.has(rootName)) {
      fail(`manifest optional test root ${rootName} is missing from optionalTestRoots`);
    }
  }

  for (const language of architecture?.languageSdks ?? []) {
    if (!Object.hasOwn(languageRoots, language)) {
      fail(`language ${language} is missing from testing.languageRoots`);
      continue;
    }

    const layout = targetLayouts[language];
    if (!layout) {
      fail(`language ${language} is missing from testing.targetLayouts`);
      continue;
    }

    if (layout.root !== languageRoots[language]) {
      fail(`target layout root for ${language} (${layout.root}) does not match languageRoots (${languageRoots[language]})`);
    }

    for (const requiredRoot of layout.requiredRoots ?? []) {
      const prefix = `${layout.root}/`;
      if (!requiredRoot.startsWith(prefix)) {
        fail(`target layout root ${requiredRoot} for ${language} must start with ${prefix}`);
      }
    }
  }

  for (const [categoryName, category] of Object.entries(requiredCategories)) {
    if (!category.minimumExpectation) {
      fail(`test category ${categoryName} is missing minimumExpectation`);
    }
  }

  if (!optionalTestRoots.has("compatibility")) {
    fail("compatibility must be listed in optionalTestRoots");
  }

  if (sharedTestRoots.has("compatibility")) {
    fail("compatibility must not be listed in sharedTestRoots");
  }

  if (testing.testRootPolicy?.compatibility?.requiredForTreeDxLanguageSdks !== false) {
    fail("compatibility must not be required for TreeDX language SDKs");
  }

  if (requiredCategories.conformance?.fixtureSource !== "packages/sdk-spec/conformance") {
    fail("conformance fixtureSource must be packages/sdk-spec/conformance");
  }

  if (requiredCategories.generated?.fixtureSource !== "docs/api/openapi.yaml") {
    fail("generated fixtureSource must be docs/api/openapi.yaml");
  }
}

const seenScenarioIds = new Set();
const definedScenarioIds = new Set();
const scenarioSchema = readJson(path.join(schemaDir, "scenario.schema.json"));
const validateScenarioFile = ajv.compile(scenarioSchema);

function validateScenarioMetadata(scenario, sourceName) {
  if (!scenario?.id) {
    fail(`${sourceName} contains a scenario without an id`);
    return;
  }

  if (seenScenarioIds.has(scenario.id)) {
    fail(`duplicate scenario id: ${scenario.id}`);
  }
  seenScenarioIds.add(scenario.id);
  definedScenarioIds.add(scenario.id);

  const capability = capabilityRecords.get(scenario.capabilityId);
  if (!capability) {
    fail(`${sourceName} scenario ${scenario.id} references missing capability ${scenario.capabilityId}`);
    return;
  }

  if (!capability.conformanceScenarios?.includes(scenario.id)) {
    fail(`${sourceName} scenario ${scenario.id} is not listed by capability ${scenario.capabilityId}`);
  }

  for (const endpoint of scenario.endpointRefs ?? []) {
    if (!capability.endpoints?.includes(endpoint)) {
      fail(`${sourceName} scenario ${scenario.id} references endpoint outside capability ${scenario.capabilityId}: ${endpoint}`);
    }
  }

  if (scenario.required === true) {
    if (!Array.isArray(scenario.steps) || scenario.steps.length === 0) {
      fail(`${sourceName} scenario ${scenario.id} is required but has no steps`);
    }

    if (!Array.isArray(scenario.assertions) || scenario.assertions.length === 0) {
      fail(`${sourceName} scenario ${scenario.id} is required but has no assertions`);
    }
  }

  for (const [fixtureType, allowedRoot] of Object.entries({
    repos: "conformance/fixtures/repos",
    requests: "conformance/fixtures/requests",
    expected: "conformance/fixtures/expected"
  })) {
    for (const fixtureRef of scenario.fixtures?.[fixtureType] ?? []) {
      const parts = fixtureRef.split(/[\\/]+/);
      if (path.isAbsolute(fixtureRef) || parts.includes("..") || (!fixtureRef.startsWith(`${allowedRoot}/`) && fixtureRef !== allowedRoot)) {
        fail(`${sourceName} scenario ${scenario.id} has invalid ${fixtureType} fixture reference: ${fixtureRef}`);
      }
    }
  }
}

for (const scenario of conformance?.scenarios ?? []) {
  validateScenarioMetadata(scenario, "conformance.yaml");
}

if (fs.existsSync(conformanceScenarioDir)) {
  for (const fileName of fs.readdirSync(conformanceScenarioDir).filter((name) => name.endsWith(".yaml")).sort()) {
    const scenarioPath = path.join(conformanceScenarioDir, fileName);
    const scenarioFile = readYaml(scenarioPath);
    if (!validateScenarioFile(scenarioFile)) {
      fail(`${fileName} does not match scenario.schema.json: ${ajv.errorsText(validateScenarioFile.errors, { separator: "\n" })}`);
    }
    const scenarios = Array.isArray(scenarioFile?.scenarios) ? scenarioFile.scenarios : [scenarioFile];

    for (const scenario of scenarios) {
      validateScenarioMetadata(scenario, fileName);
    }
  }
}

for (const capability of capabilityRecords.values()) {
  for (const scenarioId of capability.conformanceScenarios ?? []) {
    if (!definedScenarioIds.has(scenarioId)) {
      fail(`capability ${capability.id} references undefined conformance scenario ${scenarioId}`);
    }
  }
}

if (!process.exitCode) {
  console.log("sdk-spec validation passed");
}
