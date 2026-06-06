import { describe, expect, it } from 'vitest';
import { TreeDxApiError, TreeDxClient, TreeDxConformanceAdapter, TREEDX_OPENAPI_OPERATION_COUNT } from '../../src/treedx/index.js';

describe('public exports', () => {
  it('exports client, errors, generated metadata, and conformance adapter', () => {
    expect(TreeDxClient).toBeDefined();
    expect(TreeDxApiError).toBeDefined();
    expect(TreeDxConformanceAdapter).toBeDefined();
    expect(TREEDX_OPENAPI_OPERATION_COUNT).toBe(113);
  });
});
