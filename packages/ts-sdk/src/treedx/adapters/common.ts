import type { BinaryBody, Transport, TreeDxHttpMethod } from '../types/index.js';

export interface TreeDxAdapterContext {
  transport: Transport;
}

export function segment(value: string): string {
  return encodeURIComponent(value);
}

export async function jsonRequest<T>(
  transport: Transport,
  method: TreeDxHttpMethod,
  path: string,
  body?: unknown,
  query?: Record<string, string | number | boolean | undefined>
): Promise<T> {
  const response = await transport.request<T>({ method, path, body, query });
  return response.data;
}

export async function binaryRequest<T>(
  transport: Transport,
  method: TreeDxHttpMethod,
  path: string,
  binaryBody: BinaryBody,
  query?: Record<string, string | number | boolean | undefined>
): Promise<T> {
  const response = await transport.request<T>({ method, path, binaryBody, query });
  return response.data;
}
