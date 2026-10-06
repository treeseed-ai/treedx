import { describe, expect, it } from 'vitest';
import { SnapshotsAdapter } from '../../../src/treedx/index.js';
import { MockTransport } from '../mock.js';

describe('SnapshotsAdapter', () => {
  it('constructs snapshot endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new SnapshotsAdapter({ transport });
    await adapter.build('repo', {});
    await adapter.get('repo', 'snap');
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'POST /api/v1/repos/repo/snapshots/build',
      'GET /api/v1/repos/repo/snapshots/snap'
    ]);
  });
});
