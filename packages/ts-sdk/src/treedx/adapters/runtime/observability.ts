import { jsonRequest, type TreeDxAdapterContext } from './common.js';

export class ObservabilityAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  health(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/health'); }
  ready(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/ready'); }
  deepHealth(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/health/deep'); }
  metrics(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/metrics'); }
}
