import { describe, expect, it } from 'vitest';
import { RegistryAdapter } from '../../src/treedx/index.js';
import { MockTransport } from './mock.js';

describe('RegistryAdapter', () => {
  it('constructs registry endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new RegistryAdapter({ transport });
    await adapter.localNode();
    await adapter.nodes();
    await adapter.getPlacement('repo');
    await adapter.setPlacement('repo', {});
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'GET /api/v1/node',
      'GET /api/v1/registry/nodes',
      'GET /api/v1/registry/repos/repo/placement',
      'POST /api/v1/registry/repos/repo/placement'
    ]);
  });
});
