import { describe, expect, it } from 'vitest';
import { resolveAuthorizationHeader, StaticBearerTokenAuthProvider } from '../../src/treedx/index.js';

describe('auth helpers', () => {
  it('returns static bearer tokens', async () => {
    await expect(Promise.resolve(new StaticBearerTokenAuthProvider('token').getToken())).resolves.toBe('token');
  });

  it('formats authorization headers', async () => {
    await expect(resolveAuthorizationHeader({ token: 'abc' })).resolves.toEqual({ Authorization: 'Bearer abc' });
  });
});
