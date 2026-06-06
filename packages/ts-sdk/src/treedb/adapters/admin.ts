import { jsonRequest, type TreeDbAdapterContext } from './common.js';

export class AdminAdapter {
  constructor(private readonly context: TreeDbAdapterContext) {}
  deepHealth(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/admin/health/deep'); }
  storageHealth(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/admin/storage/health'); }
  storageCheck(input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/admin/storage/check', input); }
  storageRecover(input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/admin/storage/recover', input); }
  storageCompact(input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/admin/storage/compact', input); }
  storageBackup(input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/admin/storage/backup', input); }
  storageMigrations(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/admin/storage/migrations'); }
  storageMigrationPlan(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/admin/storage/migrations/plan', input); }
  storageMigrationApply(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/admin/storage/migrations/apply', input); }
  storageMigrationRollback(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/admin/storage/migrations/rollback', input); }
  storageRestoreVerify(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/admin/storage/restore/verify', input); }
  storageRestore(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/admin/storage/restore', input); }
  quarantinedWorkspaces(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/admin/workspaces/quarantined'); }
  cleanupArtifacts(input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/admin/artifacts/cleanup', input); }
  importLocalRepo(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/admin/repos/import-local', input); }
}
