import Ajv from "ajv/dist/2020.js";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import YAML from "yaml";

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

export function readYaml(filePath) {
  return YAML.parse(fs.readFileSync(filePath, "utf8"));
}

export function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

export function fail(message) {
  console.error(`sdk-spec validation failed: ${message}`);
  process.exitCode = 1;
}

export function loadSpecDocuments(specDir, schemaDir) {
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
    if (!schemaName) continue;
    const validate = ajv.compile(readJson(path.join(schemaDir, schemaName)));
    if (!validate(data)) {
      fail(`${fileName} does not match ${schemaName}: ${ajv.errorsText(validate.errors, { separator: "\n" })}`);
    }
  }
  return parsedSpecs;
}
