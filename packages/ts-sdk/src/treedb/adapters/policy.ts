import { jsonRequest, type TreeDbAdapterContext } from './common.js';

export class PolicyAdapter {
  constructor(private readonly context: TreeDbAdapterContext) {}
  capabilities(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/policy/capabilities'); }
  grants(query?: Record<string, string | number | boolean | undefined>): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/policy/grants', undefined, query); }
  createGrant(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/policy/grants', input); }
  refresh(input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/policy/refresh', input); }
}
