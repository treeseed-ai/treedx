import { jsonRequest, segment, type TreeDxAdapterContext } from '../runtime/common.js';

export class ArtifactsAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  export(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/artifacts/export`, input); }
  list(repoId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/repos/${segment(repoId)}/artifacts`); }
  get(repoId: string, artifactId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/repos/${segment(repoId)}/artifacts/${segment(artifactId)}`); }
  delete(repoId: string, artifactId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'DELETE', `/api/v1/repos/${segment(repoId)}/artifacts/${segment(artifactId)}`); }
}
