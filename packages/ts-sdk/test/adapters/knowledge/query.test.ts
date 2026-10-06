import { describe, expect, it } from 'vitest';
import { QueryAdapter } from '../../../src/treedx/index.js';
import { MockTransport } from '../mock.js';

describe('QueryAdapter', () => {
  it('constructs query endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new QueryAdapter({ transport });
    await adapter.readFile('repo', {});
    await adapter.listPaths('repo', {});
    await adapter.searchFiles('repo', {});
    await adapter.repository('repo', {});
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'POST /api/v1/repos/repo/files/read',
      'POST /api/v1/repos/repo/paths/list',
      'POST /api/v1/repos/repo/files/search',
      'POST /api/v1/repos/repo/query'
    ]);
  });
});
