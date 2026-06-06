import type { AuthProvider, TreeDxClientConfig } from '../types/index.js';

export class StaticBearerTokenAuthProvider implements AuthProvider {
  constructor(private readonly token: string) {}

  getToken(): string {
    return this.token;
  }
}

export function createAuthProvider(tokenOrProvider?: string | AuthProvider): AuthProvider | undefined {
  if (!tokenOrProvider) {
    return undefined;
  }
  if (typeof tokenOrProvider === 'string') {
    return new StaticBearerTokenAuthProvider(tokenOrProvider);
  }
  return tokenOrProvider;
}

export async function resolveAuthorizationHeader(config: Pick<TreeDxClientConfig, 'token' | 'authProvider'>): Promise<Record<string, string>> {
  const provider = config.authProvider ?? createAuthProvider(config.token);
  if (!provider) {
    return {};
  }

  const token = await provider.getToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}
