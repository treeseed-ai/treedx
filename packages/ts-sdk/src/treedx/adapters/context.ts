import { jsonRequest, segment, type TreeDxAdapterContext } from './common.js';

export class ContextAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  build(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/context/build`, input); }
  parse(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/context/parse-ctx`, input); }
}
