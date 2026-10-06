import { describe, expect, it } from 'vitest';
import { MigrationsAdapter } from '../../../src/treedx/index.js';
import { MockTransport } from '../mock.js';

describe('MigrationsAdapter', () => {
  it('constructs migration endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new MigrationsAdapter({ transport });
    await adapter.create('repo', {});
    await adapter.get('repo', 'migration');
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'POST /api/v1/repos/repo/migrations',
      'GET /api/v1/repos/repo/migrations/migration'
    ]);
  });
});
