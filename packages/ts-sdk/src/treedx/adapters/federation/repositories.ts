import { jsonRequest, segment, type TreeDxAdapterContext } from '../runtime/common.js';

export class RepositoriesAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  register(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/repos/register', input); }
  list(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/repos'); }
  create(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/repos', input); }
  get(repoId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/repos/${segment(repoId)}`); }
  status(repoId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/repos/${segment(repoId)}/status`); }
  refs(repoId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/repos/${segment(repoId)}/refs`); }
  remotes(repoId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/repos/${segment(repoId)}/remotes`); }
  push(repoId: string, input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/push`, input); }
  sync(repoId: string, input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/sync`, input); }
}
