import { describe, expect, it } from 'vitest';
import { ObservabilityAdapter } from '../../../src/treedx/index.js';
import { MockTransport } from '../mock.js';

describe('ObservabilityAdapter', () => {
  it('constructs observability endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new ObservabilityAdapter({ transport });
    await adapter.health();
    await adapter.ready();
    await adapter.deepHealth();
    await adapter.metrics();
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'GET /api/v1/health',
      'GET /api/v1/ready',
      'GET /api/v1/health/deep',
      'GET /api/v1/metrics'
    ]);
  });
});
