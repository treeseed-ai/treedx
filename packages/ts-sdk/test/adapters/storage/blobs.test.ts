import { describe, expect, it } from 'vitest';
import { BlobsAdapter } from '../../../src/treedx/index.js';
import { MockTransport } from '../mock.js';

describe('BlobsAdapter', () => {
  it('constructs blob and multipart endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new BlobsAdapter({ transport });
    await adapter.read('repo', {});
    await adapter.write('ws', {});
    await adapter.download('ws');
    await adapter.upload('ws', new Uint8Array([1]));
    await adapter.createMultipartUpload('ws', {});
    await adapter.uploadPart('ws', 'up', 1, new Uint8Array([1]));
    await adapter.completeMultipartUpload('ws', 'up', {});
    await adapter.abortMultipartUpload('ws', 'up');
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'POST /api/v1/repos/repo/blobs/read',
      'POST /api/v1/workspaces/ws/blobs/write',
      'GET /api/v1/workspaces/ws/blobs/download',
      'PUT /api/v1/workspaces/ws/blobs/upload',
      'POST /api/v1/workspaces/ws/blobs/uploads',
      'PUT /api/v1/workspaces/ws/blobs/uploads/up/parts/1',
      'POST /api/v1/workspaces/ws/blobs/uploads/up/complete',
      'DELETE /api/v1/workspaces/ws/blobs/uploads/up'
    ]);
  });
});
