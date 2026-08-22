import fs from "node:fs";
import path from "node:path";
import { renderOpenApiContractArtifacts, renderOpenApiTypes } from "./generate-treedx-openapi-types.ts";

const packageRoot = path.resolve(import.meta.dirname, "..");
const artifacts = renderOpenApiContractArtifacts();
const expectedFiles = new Map([
  [path.join(packageRoot, "src", "treedx", "generated", "openapi-types.ts"), renderOpenApiTypes()],
  [path.join(packageRoot, "src", "treedx", "openapi", "contract.ts"), artifacts.contractTypescript],
  [path.join(packageRoot, "openapi.yaml"), artifacts.openapiSource],
  [path.join(packageRoot, "openapi-contract.json"), artifacts.contractJson],
]);

for (const [filePath, expected] of expectedFiles) {
  const actual = fs.existsSync(filePath) ? fs.readFileSync(filePath, "utf8") : "";
  if (actual !== expected) {
    console.error(`TreeDX generated OpenAPI artifact is stale: ${path.relative(packageRoot, filePath)}. Run npm run treedx:generate.`);
    process.exit(1);
  }
}

console.log("TreeDX generated OpenAPI artifacts are fresh");
