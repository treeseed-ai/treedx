import { describe, expect, it } from 'vitest';
import { TreeDxClient } from '../../src/treedx/index.js';
import { MockTransport } from '../adapters/mock.js';

describe('TreeDxClient', () => {
  it('creates all generic module adapters', () => {
    const client = new TreeDxClient({ baseUrl: 'http://treedx.test', transport: new MockTransport() });
    expect(client.repositories).toBeDefined();
    expect(client.workspaces).toBeDefined();
    expect(client.files).toBeDefined();
    expect(client.blobs).toBeDefined();
    expect(client.query).toBeDefined();
    expect(client.graph).toBeDefined();
    expect(client.context).toBeDefined();
    expect(client.federation).toBeDefined();
    expect(client.registry).toBeDefined();
    expect(client.snapshots).toBeDefined();
    expect(client.artifacts).toBeDefined();
    expect(client.mirrors).toBeDefined();
    expect(client.migrations).toBeDefined();
    expect(client.exec).toBeDefined();
    expect(client.observability).toBeDefined();
  });

  it('uses custom transport for convenience methods', async () => {
    const transport = new MockTransport();
    const client = new TreeDxClient({ baseUrl: 'http://treedx.test', transport });
    await client.version();
    expect(transport.last()).toMatchObject({ method: 'GET', path: '/api/v1/version' });
  });
});
