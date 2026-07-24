import { describe, expect, it } from 'vitest';
import { ExecAdapter } from '../../../src/treedx/index.js';
import { MockTransport } from '../mock.js';

describe('ExecAdapter', () => {
  it('constructs exec endpoint', async () => {
    const transport = new MockTransport();
    const adapter = new ExecAdapter({ transport });
    await adapter.run('ws', {});
    expect(transport.last()).toMatchObject({ method: 'POST', path: '/api/v1/workspaces/ws/exec' });
  });
});
