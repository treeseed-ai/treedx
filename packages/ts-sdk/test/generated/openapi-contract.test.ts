import crypto from 'node:crypto';
import fs from 'node:fs';
import { describe, expect, it } from 'vitest';
import { TREEDX_OPENAPI_CONTRACT } from '../../src/treedx/openapi/index.js';
import { TREEDX_OPENAPI_OPERATIONS } from '../../src/treedx/generated/index.js';

const sha256 = (value: string): string =>
  `sha256:${crypto.createHash('sha256').update(value).digest('hex')}`;

describe('authoritative OpenAPI contract', () => {
  it('binds the packaged specification to the generated operation inventory', () => {
    const openapi = fs.readFileSync(new URL('../../openapi.yaml', import.meta.url), 'utf8');
    const operationIds = TREEDX_OPENAPI_OPERATIONS.map((operation) => operation.operationId);

    expect(TREEDX_OPENAPI_CONTRACT.schema).toBe('treedx.openapi-contract/v1');
    expect(TREEDX_OPENAPI_CONTRACT.openapiVersion).toBe('0.11.1');
    expect(TREEDX_OPENAPI_CONTRACT.openapiSha256).toBe(sha256(openapi));
    expect(TREEDX_OPENAPI_CONTRACT.operationCount).toBe(TREEDX_OPENAPI_OPERATIONS.length);
    expect(operationIds.every((operationId) => operationId.length > 0)).toBe(true);
    expect(new Set(operationIds).size).toBe(operationIds.length);
    expect(TREEDX_OPENAPI_OPERATIONS.find((operation) => operation.operationId === 'getHealth')?.requiredCapabilities).toEqual([]);
    expect(TREEDX_OPENAPI_OPERATIONS.find((operation) => operation.operationId === 'createRepository')?.requiredCapabilities).toContain('repos:write');
  });
});
