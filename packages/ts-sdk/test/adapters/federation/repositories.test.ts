import { describe, expect, it } from 'vitest';
import { RepositoriesAdapter } from '../../../src/treedx/index.js';
import { MockTransport } from '../mock.js';

describe('RepositoriesAdapter', () => {
  it('constructs repository endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new RepositoriesAdapter({ transport });
    await adapter.register({});
    await adapter.get('repo/a');
    await adapter.refs('repo/a');
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'POST /api/v1/repos/register',
      'GET /api/v1/repos/repo%2Fa',
      'GET /api/v1/repos/repo%2Fa/refs'
    ]);
  });
});
