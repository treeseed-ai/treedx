import type { BinaryBody } from '../types/index.js';

export function isBinaryBody(value: unknown): value is BinaryBody {
  return (
    value instanceof Uint8Array ||
    value instanceof ArrayBuffer ||
    Buffer.isBuffer(value) ||
    (typeof ReadableStream !== 'undefined' && value instanceof ReadableStream)
  );
}

export function assertBinaryBody(value: unknown): asserts value is BinaryBody {
  if (!isBinaryBody(value)) {
    throw new TypeError('Expected a binary-safe body value');
  }
}

export async function toUint8Array(value: BinaryBody): Promise<Uint8Array> {
  if (value instanceof Uint8Array) {
    return value;
  }
  if (value instanceof ArrayBuffer) {
    return new Uint8Array(value);
  }
  if (Buffer.isBuffer(value)) {
    return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  }

  const chunks: Uint8Array[] = [];
  const reader = value.getReader();
  while (true) {
    const result = await reader.read();
    if (result.done) {
      break;
    }
    chunks.push(result.value);
  }

  const total = chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0);
  const combined = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    combined.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return combined;
}
