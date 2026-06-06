import { describe, expect, it } from 'vitest';
import { TREEDX_OPENAPI_OPERATION_COUNT, TREEDX_OPENAPI_OPERATIONS } from '../../src/treedx/index.js';

describe('generated OpenAPI metadata', () => {
  it('tracks current /api/v1 operation count', () => {
    expect(TREEDX_OPENAPI_OPERATION_COUNT).toBe(113);
    expect(TREEDX_OPENAPI_OPERATIONS).toHaveLength(113);
  });
});
