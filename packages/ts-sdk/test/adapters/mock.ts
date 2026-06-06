import type { Transport, TreeDxRequest, TreeDxResponse } from '../../src/treedx/index.js';

export class MockTransport implements Transport {
  readonly requests: TreeDxRequest[] = [];

  async request<T = unknown>(request: TreeDxRequest): Promise<TreeDxResponse<T>> {
    this.requests.push(request);
    return { status: 200, headers: {}, data: { ok: true } as T };
  }

  last(): TreeDxRequest {
    const request = this.requests.at(-1);
    if (!request) {
      throw new Error('No request recorded');
    }
    return request;
  }
}
