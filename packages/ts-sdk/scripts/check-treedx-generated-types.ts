import fs from "node:fs";
import path from "node:path";
import { renderOpenApiTypes } from "./generate-treedx-openapi-types.ts";

const packageRoot = path.resolve(import.meta.dirname, "..");
const outputPath = path.join(packageRoot, "src", "treedx", "generated", "openapi-types.ts");
const expected = renderOpenApiTypes();
const actual = fs.existsSync(outputPath) ? fs.readFileSync(outputPath, "utf8") : "";

if (actual !== expected) {
  console.error("TreeDX generated OpenAPI metadata is stale. Run npm run treedx:generate.");
  process.exit(1);
}

console.log("TreeDX generated OpenAPI metadata is fresh");
