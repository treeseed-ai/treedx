import { describe, expect, it } from 'vitest';
import { WorkspacesAdapter } from '../../../src/treedx/index.js';
import { MockTransport } from '../mock.js';

describe('WorkspacesAdapter', () => {
  it('constructs workspace endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new WorkspacesAdapter({ transport });
    await adapter.create('repo', {});
    await adapter.get('ws');
    await adapter.close('ws');
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'POST /api/v1/repos/repo/workspaces',
      'GET /api/v1/workspaces/ws',
      'POST /api/v1/workspaces/ws/close'
    ]);
  });
});
