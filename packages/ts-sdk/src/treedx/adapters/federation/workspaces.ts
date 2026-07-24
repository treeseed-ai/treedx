import { jsonRequest, segment, type TreeDxAdapterContext } from '../runtime/common.js';

export class WorkspacesAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  create(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/workspaces`, input); }
  get(workspaceId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/workspaces/${segment(workspaceId)}`); }
  close(workspaceId: string, input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/workspaces/${segment(workspaceId)}/close`, input); }
}
