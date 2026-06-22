import fs from "node:fs";
import path from "node:path";
import { renderOpenApiTypes } from "./generate_treedx_openapi_types.ts";

const packageRoot = path.resolve(import.meta.dirname, "..");
const outputPath = path.join(packageRoot, "src", "generated", "openapi_types.rs");
const expected = renderOpenApiTypes();
const actual = fs.existsSync(outputPath) ? fs.readFileSync(outputPath, "utf8") : "";

if (actual !== expected) {
  console.error("TreeDX generated OpenAPI metadata is stale. Run tsx scripts/generate_treedx_openapi_types.ts.");
  process.exit(1);
}

console.log("TreeDX generated OpenAPI metadata is fresh");
