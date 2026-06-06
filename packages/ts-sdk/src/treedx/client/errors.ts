import type { TreeDxApiErrorPayload } from '../types/index.js';

export class TreeDxApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details?: unknown;
  readonly payload?: unknown;
  readonly cause?: unknown;

  constructor(input: { status: number; code: string; message: string; details?: unknown; payload?: unknown; cause?: unknown }) {
    super(input.message);
    this.name = 'TreeDxApiError';
    this.status = input.status;
    this.code = input.code;
    this.details = input.details;
    this.payload = input.payload;
    this.cause = input.cause;
  }

  static fromResponse(status: number, payload: unknown): TreeDxApiError {
    const envelope = payload as TreeDxApiErrorPayload | undefined;
    const error = envelope?.error;
    return new TreeDxApiError({
      status,
      code: error?.code ?? 'internal_error',
      message: error?.message ?? `TreeDX request failed with status ${status}`,
      details: error?.details,
      payload
    });
  }

  static network(message: string, cause?: unknown): TreeDxApiError {
    return new TreeDxApiError({
      status: 0,
      code: 'network_error',
      message,
      cause
    });
  }
}
