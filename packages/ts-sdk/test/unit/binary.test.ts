import { describe, expect, it } from 'vitest';
import { assertBinaryBody, isBinaryBody, toUint8Array } from '../../src/treedx/index.js';

describe('binary helpers', () => {
  it('accepts binary-safe values', async () => {
    expect(isBinaryBody(new Uint8Array([1]))).toBe(true);
    expect(isBinaryBody(new ArrayBuffer(1))).toBe(true);
    expect(isBinaryBody(Buffer.from([1]))).toBe(true);
    await expect(toUint8Array(Buffer.from([1, 2])).then((bytes) => Array.from(bytes))).resolves.toEqual([1, 2]);
  });

  it('rejects text strings', () => {
    expect(() => assertBinaryBody('not binary')).toThrow(TypeError);
  });
});
