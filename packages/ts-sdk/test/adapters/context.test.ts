import { describe, expect, it } from 'vitest';
import { ContextAdapter } from '../../src/treedx/index.js';
import { MockTransport } from './mock.js';

describe('ContextAdapter', () => {
  it('constructs context endpoints', async () => {
    const transport = new MockTransport();
    const adapter = new ContextAdapter({ transport });
    await adapter.build('repo', {});
    await adapter.parse('repo', {});
    expect(transport.requests.map((r) => `${r.method} ${r.path}`)).toEqual([
      'POST /api/v1/repos/repo/context/build',
      'POST /api/v1/repos/repo/context/parse-ctx'
    ]);
  });
});
