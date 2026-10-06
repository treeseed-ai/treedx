import { describe, expect, it } from 'vitest';
import { ArtifactsAdapter } from '../../../src/treedx/index.js';
import { MockTransport } from '../mock.js';

describe('ArtifactsAdapter', () => {
  it('constructs artifact endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new ArtifactsAdapter({ transport });
    await adapter.export('repo', {});
    await adapter.list('repo');
    await adapter.get('repo', 'artifact');
    await adapter.delete('repo', 'artifact');
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'POST /api/v1/repos/repo/artifacts/export',
      'GET /api/v1/repos/repo/artifacts',
      'GET /api/v1/repos/repo/artifacts/artifact',
      'DELETE /api/v1/repos/repo/artifacts/artifact'
    ]);
  });
});
