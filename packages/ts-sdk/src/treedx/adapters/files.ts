import { jsonRequest, segment, type TreeDxAdapterContext } from './common.js';

export class FilesAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  tree(workspaceId: string, query?: Record<string, string | number | boolean | undefined>): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/workspaces/${segment(workspaceId)}/tree`, undefined, query); }
  read(workspaceId: string, query?: Record<string, string | number | boolean | undefined>): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/workspaces/${segment(workspaceId)}/files`, undefined, query); }
  write(workspaceId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'PUT', `/api/v1/workspaces/${segment(workspaceId)}/files`, input); }
  patch(workspaceId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'PATCH', `/api/v1/workspaces/${segment(workspaceId)}/files`, input); }
  delete(workspaceId: string, query?: Record<string, string | number | boolean | undefined>): Promise<unknown> { return jsonRequest(this.context.transport, 'DELETE', `/api/v1/workspaces/${segment(workspaceId)}/files`, undefined, query); }
  search(workspaceId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/workspaces/${segment(workspaceId)}/search`, input); }
  status(workspaceId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/workspaces/${segment(workspaceId)}/status`); }
  diff(workspaceId: string, query?: Record<string, string | number | boolean | undefined>): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/workspaces/${segment(workspaceId)}/diff`, undefined, query); }
  commit(workspaceId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/workspaces/${segment(workspaceId)}/commit`, input); }
}
