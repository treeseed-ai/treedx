import { describe, expect, it } from 'vitest';
import { MirrorsAdapter } from '../../src/treedx/index.js';
import { MockTransport } from './mock.js';

describe('MirrorsAdapter', () => {
  it('constructs mirror endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new MirrorsAdapter({ transport });
    await adapter.list('repo');
    await adapter.upsert('repo', {});
    await adapter.sync('repo', 'mirror');
    await adapter.health('repo', 'mirror');
    await adapter.promote('repo', 'mirror');
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'GET /api/v1/repos/repo/mirrors',
      'POST /api/v1/repos/repo/mirrors',
      'POST /api/v1/repos/repo/mirrors/mirror/sync',
      'POST /api/v1/repos/repo/mirrors/mirror/health',
      'POST /api/v1/repos/repo/mirrors/mirror/promote'
    ]);
  });
});
