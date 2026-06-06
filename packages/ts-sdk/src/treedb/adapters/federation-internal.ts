import { jsonRequest, segment, type TreeDbAdapterContext } from './common.js';

export class FederationInternalAdapter {
  constructor(private readonly context: TreeDbAdapterContext) {}
  health(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/internal/federation/health'); }
  proxy(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/internal/federation/proxy', input); }
  exportMirror(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/internal/federation/repos/${segment(repoId)}/mirror/export`, input); }
  importMirror(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/internal/federation/repos/${segment(repoId)}/mirror/import`, input); }
}
