import { jsonRequest, segment, type TreeDbAdapterContext } from './common.js';

export class GraphAdapter {
  constructor(private readonly context: TreeDbAdapterContext) {}
  refresh(repoId: string, input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/graph/refresh`, input); }
  query(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/graph/query`, input); }
  refreshJob(repoId: string, jobId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/repos/${segment(repoId)}/graph/refresh-jobs/${segment(jobId)}`); }
  node(repoId: string, nodeId: string, query?: Record<string, string | number | boolean | undefined>): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/repos/${segment(repoId)}/graph/nodes/${segment(nodeId)}`, undefined, query); }
  related(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/graph/related`, input); }
  subgraph(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/graph/subgraph`, input); }
  searchFiles(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/graph/search-files`, input); }
  searchSections(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/graph/search-sections`, input); }
  searchEntities(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/graph/search-entities`, input); }
}
