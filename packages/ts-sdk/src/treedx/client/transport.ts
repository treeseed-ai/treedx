import { resolveAuthorizationHeader } from './auth.js';
import { TreeDxApiError } from './errors.js';
import type { BinaryBody, TreeDxClientConfig, TreeDxRequest, TreeDxResponse, Transport } from '../types/index.js';

export type TreeDxFetch = typeof fetch;

export interface FetchTransportOptions {
  baseUrl: string;
  defaultHeaders?: Record<string, string>;
  token?: string;
  authProvider?: TreeDxClientConfig['authProvider'];
  fetchImpl?: TreeDxFetch;
  timeoutMs?: number;
}

export class FetchTransport implements Transport {
  private readonly fetchImpl: TreeDxFetch;

  constructor(private readonly options: FetchTransportOptions) {
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async request<T = unknown>(request: TreeDxRequest): Promise<TreeDxResponse<T>> {
    const url = new URL(request.path, this.options.baseUrl);
    for (const [key, value] of Object.entries(request.query ?? {})) {
      if (value !== undefined) {
        url.searchParams.set(key, String(value));
      }
    }

    const authHeaders = await resolveAuthorizationHeader(this.options);
    const headers: Record<string, string> = {
      ...this.options.defaultHeaders,
      ...authHeaders,
      ...request.headers
    };
    if (request.requestId) headers['X-Request-ID'] = request.requestId;
    if (request.traceparent) headers.traceparent = request.traceparent;
    if (request.idempotencyKey) headers['Idempotency-Key'] = request.idempotencyKey;

    let body: BodyInit | undefined;
    if (request.binaryBody) {
      body = request.binaryBody as BinaryBody as BodyInit;
    } else if (request.body !== undefined) {
      headers['Content-Type'] ??= 'application/json';
      body = JSON.stringify(request.body);
    }

    let response: Response;
    const controller = new AbortController();
    const timeoutMs = request.timeoutMs ?? this.options.timeoutMs;
    const timeout = timeoutMs === undefined
      ? undefined
      : setTimeout(() => controller.abort(new Error('TreeDX request timed out')), timeoutMs);
    const abort = () => controller.abort(request.signal?.reason);
    request.signal?.addEventListener('abort', abort, { once: true });
    try {
      response = await this.fetchImpl(url, { method: request.method, headers, body, signal: controller.signal });
    } catch (error) {
      if (controller.signal.aborted) {
        throw TreeDxApiError.cancelled(
          timeoutMs === undefined ? undefined : `TreeDX request exceeded ${timeoutMs}ms or was cancelled`,
          error
        );
      }
      throw TreeDxApiError.network('TreeDX network request failed', error);
    } finally {
      if (timeout !== undefined) clearTimeout(timeout);
      request.signal?.removeEventListener('abort', abort);
    }

    const data = await parseResponseBody(response);
    if (!response.ok) {
      throw TreeDxApiError.fromResponse(response.status, data);
    }

    return {
      status: response.status,
      headers: Object.fromEntries(response.headers.entries()),
      data: data as T
    };
  }
}

async function parseResponseBody(response: Response): Promise<unknown> {
  if (response.status === 204) {
    return undefined;
  }

  const contentType = response.headers.get('content-type') ?? '';
  if (contentType.includes('application/json')) {
    return response.json();
  }
  if (contentType.startsWith('text/')) {
    return response.text();
  }
  return response.arrayBuffer();
}
