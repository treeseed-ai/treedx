import { jsonRequest, segment, type TreeDxAdapterContext } from '../runtime/common.js';

export class MirrorsAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  list(repoId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/repos/${segment(repoId)}/mirrors`); }
  upsert(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/mirrors`, input); }
  sync(repoId: string, mirrorId: string, input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/mirrors/${segment(mirrorId)}/sync`, input); }
  health(repoId: string, mirrorId: string, input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/mirrors/${segment(mirrorId)}/health`, input); }
  promote(repoId: string, mirrorId: string, input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/mirrors/${segment(mirrorId)}/promote`, input); }
}
