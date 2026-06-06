import { describe, expect, it } from 'vitest';
import { FederationAdapter } from '../../src/treedx/index.js';
import { MockTransport } from './mock.js';

describe('FederationAdapter', () => {
  it('constructs federation endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new FederationAdapter({ transport });
    await adapter.plan({});
    await adapter.search({});
    await adapter.query({});
    await adapter.contextBuild({});
    await adapter.graphQuery({});
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'POST /api/v1/federation/query/plan',
      'POST /api/v1/search',
      'POST /api/v1/query',
      'POST /api/v1/context/build',
      'POST /api/v1/graph/query'
    ]);
  });
});
