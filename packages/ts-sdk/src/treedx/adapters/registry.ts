import { jsonRequest, segment, type TreeDxAdapterContext } from './common.js';

export class RegistryAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  localNode(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/node'); }
  nodes(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/registry/nodes'); }
  getPlacement(repoId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/registry/repos/${segment(repoId)}/placement`); }
  setPlacement(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/registry/repos/${segment(repoId)}/placement`, input); }
}
