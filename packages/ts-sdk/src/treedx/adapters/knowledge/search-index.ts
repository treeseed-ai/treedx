import { jsonRequest, segment, type TreeDxAdapterContext } from '../runtime/common.js';

export class SearchIndexAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  status(repoId: string, query?: Record<string, string | number | boolean | undefined>): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/repos/${segment(repoId)}/search/index/status`, undefined, query); }
  refresh(repoId: string, input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/search/index/refresh`, input); }
  compact(repoId: string, input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/search/index/compact`, input); }
}
