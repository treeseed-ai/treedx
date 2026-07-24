import { describe, expect, it } from 'vitest';
import { GraphAdapter } from '../../../src/treedx/index.js';
import { MockTransport } from '../mock.js';

describe('GraphAdapter', () => {
  it('constructs graph endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new GraphAdapter({ transport });
    await adapter.refresh('repo');
    await adapter.query('repo', {});
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'POST /api/v1/repos/repo/graph/refresh',
      'POST /api/v1/repos/repo/graph/query'
    ]);
  });
});
