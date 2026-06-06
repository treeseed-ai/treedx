import { describe, expect, it } from 'vitest';
import { TreeDxApiError } from '../../src/treedx/index.js';

describe('TreeDxApiError', () => {
  it('preserves response error envelope fields', () => {
    const payload = { error: { code: 'permission_denied', message: 'Denied', details: { scope: 'repo' } } };
    const error = TreeDxApiError.fromResponse(403, payload);
    expect(error.status).toBe(403);
    expect(error.code).toBe('permission_denied');
    expect(error.message).toBe('Denied');
    expect(error.details).toEqual({ scope: 'repo' });
    expect(error.payload).toBe(payload);
  });

  it('wraps network failures consistently', () => {
    const error = TreeDxApiError.network('offline');
    expect(error.status).toBe(0);
    expect(error.code).toBe('network_error');
  });
});
