import { describe, expect, it } from 'vitest';
import { FetchTransport, TreeDxApiError } from '../../src/treedx/index.js';

describe('FetchTransport', () => {
  it('builds URL, headers, and JSON body', async () => {
    const calls: RequestInfo[] = [];
    const initCalls: RequestInit[] = [];
    const fetchImpl = (async (input: RequestInfo, init?: RequestInit) => {
      calls.push(input);
      initCalls.push(init ?? {});
      return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'content-type': 'application/json' } });
    }) as typeof fetch;

    const transport = new FetchTransport({ baseUrl: 'http://treedx.test', token: 't', fetchImpl });
    const response = await transport.request({ method: 'POST', path: '/api/v1/query', query: { limit: 1 }, body: { q: 'x' } });
    expect(String(calls[0])).toBe('http://treedx.test/api/v1/query?limit=1');
    expect(initCalls[0]?.headers).toMatchObject({ Authorization: 'Bearer t', 'Content-Type': 'application/json' });
    expect(response.data).toEqual({ ok: true });
  });

  it('throws TreeDxApiError for non-2xx responses', async () => {
    const fetchImpl = (async () => new Response(JSON.stringify({ error: { code: 'invalid_token', message: 'Bad token' } }), { status: 401, headers: { 'content-type': 'application/json' } })) as typeof fetch;
    const transport = new FetchTransport({ baseUrl: 'http://treedx.test', fetchImpl });
    await expect(transport.request({ method: 'GET', path: '/api/v1/auth/whoami' })).rejects.toBeInstanceOf(TreeDxApiError);
  });

  it('propagates request identity, trace, and idempotency headers', async () => {
    let observed: RequestInit | undefined;
    const fetchImpl = (async (_input: RequestInfo, init?: RequestInit) => {
      observed = init;
      return new Response('{}', { status: 200, headers: { 'content-type': 'application/json' } });
    }) as typeof fetch;
    const transport = new FetchTransport({ baseUrl: 'http://treedx.test', fetchImpl });

    await transport.request({
      method: 'POST',
      path: '/api/v1/query',
      requestId: 'request-1',
      traceparent: '00-11111111111111111111111111111111-2222222222222222-01',
      idempotencyKey: 'idem-1'
    });

    expect(observed?.headers).toMatchObject({
      'X-Request-ID': 'request-1',
      traceparent: '00-11111111111111111111111111111111-2222222222222222-01',
      'Idempotency-Key': 'idem-1'
    });
  });

  it('normalizes cancellation and timeouts', async () => {
    const fetchImpl = ((_input: RequestInfo, init?: RequestInit) =>
      new Promise((_resolve, reject) => init?.signal?.addEventListener('abort', () => reject(init.signal?.reason), { once: true }))) as typeof fetch;
    const transport = new FetchTransport({ baseUrl: 'http://treedx.test', timeoutMs: 5, fetchImpl });

    await expect(transport.request({ method: 'GET', path: '/api/v1/health' })).rejects.toMatchObject({
      code: 'request_cancelled'
    });
  });
});
