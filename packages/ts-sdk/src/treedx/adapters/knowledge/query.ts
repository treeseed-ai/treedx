import { jsonRequest, segment, type TreeDxAdapterContext } from '../runtime/common.js';

export class QueryAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  readFile(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/files/read`, input); }
  listPaths(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/paths/list`, input); }
  searchFiles(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/files/search`, input); }
  repository(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/query`, input); }
}
