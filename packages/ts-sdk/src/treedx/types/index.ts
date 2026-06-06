export type TreeDxJson =
  | null
  | boolean
  | number
  | string
  | TreeDxJson[]
  | { [key: string]: TreeDxJson };

export interface TreeDxClientConfig {
  baseUrl: string;
  token?: string;
  authProvider?: AuthProvider;
  transport?: Transport;
  defaultHeaders?: Record<string, string>;
}

export interface TreeDxRequest {
  method: TreeDxHttpMethod;
  path: string;
  query?: Record<string, string | number | boolean | undefined>;
  headers?: Record<string, string>;
  body?: unknown;
  binaryBody?: BinaryBody;
}

export interface TreeDxResponse<T = unknown> {
  status: number;
  headers: Record<string, string>;
  data: T;
}

export type TreeDxHttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';

export interface TreeDxPage<T> {
  items: T[];
  nextCursor?: string;
  hasMore?: boolean;
  cursor?: string;
  limit?: number;
}

export type TreeDxCursor = string;

export type BinaryBody =
  | Uint8Array
  | ArrayBuffer
  | Buffer
  | ReadableStream<Uint8Array>;

export interface MultipartUpload {
  uploadId: string;
  completedParts?: Array<{ partNumber: number; etag?: string }>;
}

export interface TreeDxApiErrorPayload {
  error?: {
    code?: string;
    message?: string;
    details?: unknown;
  };
  [key: string]: unknown;
}

export interface AuthProvider {
  getToken(): string | Promise<string>;
}

export interface Transport {
  request<T = unknown>(request: TreeDxRequest): Promise<TreeDxResponse<T>>;
}

export type TreeDxRecord = Record<string, unknown>;
