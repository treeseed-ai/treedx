import fs from 'node:fs';
import path from 'node:path';
import YAML from 'yaml';
import { describe, expect, it } from 'vitest';
import { TREEDX_OPENAPI_OPERATIONS } from '../../src/treedx/index.js';

describe('OpenAPI endpoint coverage metadata', () => {
  it('includes every endpoint declared by sdk-spec', () => {
    const endpointsPath = path.resolve(import.meta.dirname, '../../../sdk-spec/spec/endpoints.yaml');
    const endpoints = YAML.parse(fs.readFileSync(endpointsPath, 'utf8'));
    const generated = new Set(TREEDX_OPENAPI_OPERATIONS.map((operation) => `${operation.method} ${operation.path}`));

    for (const groupEndpoints of Object.values<string[]>(endpoints.groups)) {
      for (const endpoint of groupEndpoints) {
        expect(generated.has(endpoint), endpoint).toBe(true);
      }
    }
  });
});
