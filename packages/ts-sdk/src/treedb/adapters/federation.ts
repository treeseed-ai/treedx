import { jsonRequest, segment, type TreeDbAdapterContext } from './common.js';

export class FederationAdapter {
  constructor(private readonly context: TreeDbAdapterContext) {}
  plan(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/federation/query/plan', input); }
  search(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/search', input); }
  query(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/query', input); }
  contextBuild(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/context/build', input); }
  graphQuery(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/graph/query', input); }
  catalog(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/federation/catalog'); }
  pushCatalog(input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/federation/catalog/push', input); }
  syncCatalog(input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/federation/catalog/sync', input); }
  peers(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/federation/peers'); }
  peer(nodeId: string): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', `/api/v1/federation/peers/${segment(nodeId)}`); }
  registerNode(input: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', '/api/v1/federation/nodes/register', input); }
  trustPeer(nodeId: string, input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/federation/peers/${segment(nodeId)}/trust`, input); }
  revokePeer(nodeId: string, input?: unknown): Promise<unknown> { return jsonRequest(this.context.transport, 'POST', `/api/v1/federation/peers/${segment(nodeId)}/revoke`, input); }
  routes(): Promise<unknown> { return jsonRequest(this.context.transport, 'GET', '/api/v1/federation/routes'); }
}


export { segment };
