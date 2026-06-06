import { binaryRequest, jsonRequest, segment, type TreeDxAdapterContext } from './common.js';
import type { BinaryBody } from '../types/index.js';

export class BlobsAdapter {
  constructor(private readonly context: TreeDxAdapterContext) {}
  read(repoId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/repos/${segment(repoId)}/blobs/read`, input); }
  write(workspaceId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/workspaces/${segment(workspaceId)}/blobs/write`, input); }
  delete(workspaceId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/workspaces/${segment(workspaceId)}/blobs/delete`, input); }
  download(workspaceId: string, query?: Record<string, string | number | boolean | undefined>): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/workspaces/${segment(workspaceId)}/blobs/download`, undefined, query); }
  upload(workspaceId: string, body: BinaryBody, query?: Record<string, string | number | boolean | undefined>): Promise<unknown> { return binaryRequest(this.context.transport, 'PUT', `/api/v1/workspaces/${segment(workspaceId)}/blobs/upload`, body, query); }
  createMultipartUpload(workspaceId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/workspaces/${segment(workspaceId)}/blobs/uploads`, input); }
  uploadPart(workspaceId: string, uploadId: string, partNumber: number, body: BinaryBody): Promise<unknown> { return binaryRequest(this.context.transport, 'PUT', `/api/v1/workspaces/${segment(workspaceId)}/blobs/uploads/${segment(uploadId)}/parts/${partNumber}`, body); }
  completeMultipartUpload(workspaceId: string, uploadId: string, input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/workspaces/${segment(workspaceId)}/blobs/uploads/${segment(uploadId)}/complete`, input); }
  abortMultipartUpload(workspaceId: string, uploadId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'DELETE', `/api/v1/workspaces/${segment(workspaceId)}/blobs/uploads/${segment(uploadId)}`); }
}
