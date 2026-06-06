import { describe, expect, it } from 'vitest';
import { FilesAdapter } from '../../src/treedx/index.js';
import { MockTransport } from './mock.js';

describe('FilesAdapter', () => {
  it('constructs file endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new FilesAdapter({ transport });
    await adapter.tree('ws');
    await adapter.read('ws', { path: 'a.md' });
    await adapter.write('ws', {});
    await adapter.patch('ws', {});
    await adapter.delete('ws', { path: 'a.md' });
    await adapter.commit('ws', {});
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'GET /api/v1/workspaces/ws/tree',
      'GET /api/v1/workspaces/ws/files',
      'PUT /api/v1/workspaces/ws/files',
      'PATCH /api/v1/workspaces/ws/files',
      'DELETE /api/v1/workspaces/ws/files',
      'POST /api/v1/workspaces/ws/commit'
    ]);
  });
});
