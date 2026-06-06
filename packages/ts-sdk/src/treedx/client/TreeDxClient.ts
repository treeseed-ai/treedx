import { AdminAdapter, ArtifactsAdapter, AuditAdapter, BlobsAdapter, ContextAdapter, ExecAdapter, FederationAdapter, FederationInternalAdapter, FilesAdapter, GraphAdapter, MigrationsAdapter, MirrorsAdapter, ObservabilityAdapter, PolicyAdapter, QueryAdapter, RegistryAdapter, RepositoriesAdapter, SearchIndexAdapter, SnapshotsAdapter, WorkspacesAdapter } from '../adapters/index.js';
import { TREEDX_OPENAPI_OPERATIONS, type TreeDxOpenApiMethod, type TreeDxOpenApiPath } from '../generated/index.js';
import type { BinaryBody, TreeDxClientConfig, Transport } from '../types/index.js';
import { FetchTransport } from './transport.js';

export class TreeDxClient {
  readonly transport: Transport;
  readonly repositories: RepositoriesAdapter;
  readonly workspaces: WorkspacesAdapter;
  readonly files: FilesAdapter;
  readonly blobs: BlobsAdapter;
  readonly query: QueryAdapter;
  readonly graph: GraphAdapter;
  readonly context: ContextAdapter;
  readonly federation: FederationAdapter;
  readonly registry: RegistryAdapter;
  readonly snapshots: SnapshotsAdapter;
  readonly artifacts: ArtifactsAdapter;
  readonly mirrors: MirrorsAdapter;
  readonly migrations: MigrationsAdapter;
  readonly exec: ExecAdapter;
  readonly observability: ObservabilityAdapter;
  readonly admin: AdminAdapter;
  readonly audit: AuditAdapter;
  readonly policy: PolicyAdapter;
  readonly searchIndex: SearchIndexAdapter;
  readonly federationInternal: FederationInternalAdapter;

  constructor(readonly config: TreeDxClientConfig) {
    this.transport = config.transport ?? new FetchTransport(config);
    const adapterContext = { transport: this.transport };
    this.repositories = new RepositoriesAdapter(adapterContext);
    this.workspaces = new WorkspacesAdapter(adapterContext);
    this.files = new FilesAdapter(adapterContext);
    this.blobs = new BlobsAdapter(adapterContext);
    this.query = new QueryAdapter(adapterContext);
    this.graph = new GraphAdapter(adapterContext);
    this.context = new ContextAdapter(adapterContext);
    this.federation = new FederationAdapter(adapterContext);
    this.registry = new RegistryAdapter(adapterContext);
    this.snapshots = new SnapshotsAdapter(adapterContext);
    this.artifacts = new ArtifactsAdapter(adapterContext);
    this.mirrors = new MirrorsAdapter(adapterContext);
    this.migrations = new MigrationsAdapter(adapterContext);
    this.exec = new ExecAdapter(adapterContext);
    this.observability = new ObservabilityAdapter(adapterContext);
    this.admin = new AdminAdapter(adapterContext);
    this.audit = new AuditAdapter(adapterContext);
    this.policy = new PolicyAdapter(adapterContext);
    this.searchIndex = new SearchIndexAdapter(adapterContext);
    this.federationInternal = new FederationInternalAdapter(adapterContext);
  }

  health(): Promise<unknown> {
    return this.observability.health();
  }

  version(): Promise<unknown> {
    return this.transport.request({ method: 'GET', path: '/api/v1/version' }).then((response) => response.data);
  }

  whoami(): Promise<unknown> {
    return this.transport.request({ method: 'GET', path: '/api/v1/auth/whoami' }).then((response) => response.data);
  }

  effectiveScope(): Promise<unknown> {
    return this.transport.request({ method: 'GET', path: '/api/v1/policy/effective-scope' }).then((response) => response.data);
  }

  authMode(): Promise<unknown> {
    return this.transport.request({ method: 'GET', path: '/api/v1/auth/mode' }).then((response) => response.data);
  }

  createDevToken(input?: unknown): Promise<unknown> {
    return this.transport.request({ method: 'POST', path: '/api/v1/auth/dev-token', body: input }).then((response) => response.data);
  }

  operation<T = unknown>(
    method: TreeDxOpenApiMethod,
    path: TreeDxOpenApiPath,
    options: {
      pathParams?: Record<string, string | number>;
      query?: Record<string, string | number | boolean | undefined>;
      body?: unknown;
      binaryBody?: BinaryBody;
      headers?: Record<string, string>;
    } = {}
  ): Promise<T> {
    if (!TREEDX_OPENAPI_OPERATIONS.some((operation) => operation.method === method && operation.path === path)) {
      throw new Error(`Unknown TreeDX OpenAPI operation: ${method} ${path}`);
    }
    const resolvedPath = path.replace(/\{([^}]+)\}/g, (_match, key: string) => {
      const value = options.pathParams?.[key];
      if (value === undefined) {
        throw new Error(`Missing path parameter ${key} for ${method} ${path}`);
      }
      return encodeURIComponent(String(value));
    });
    return this.transport.request<T>({ method, path: resolvedPath, query: options.query, body: options.body, binaryBody: options.binaryBody, headers: options.headers }).then((response) => response.data);
  }
}
