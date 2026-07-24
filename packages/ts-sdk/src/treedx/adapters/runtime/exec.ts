import { jsonRequest, segment, type TreeDxAdapterContext } from './common.js';

export class ExecAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  run(workspaceId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/workspaces/${segment(workspaceId)}/exec`, input); }
}
