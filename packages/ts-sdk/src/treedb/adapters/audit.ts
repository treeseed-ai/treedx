import { jsonRequest, type TreeDbAdapterContext } from './common.js';

export class AuditAdapter {
  constructor(private readonly context: TreeDbAdapterContext) {}
  events(query?: Record<string, string | number | boolean | undefined>): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/audit/events', undefined, query); }
}
