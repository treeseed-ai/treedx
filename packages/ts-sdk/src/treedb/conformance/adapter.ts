import type { TreeDbClient } from '../client/TreeDbClient.js';

export interface TreeDbConformanceAdapterOptions {
  client: TreeDbClient;
  serverConfigured?: boolean;
}

export interface TreeDbConformanceScenario {
  id: string;
  capabilityId: string;
  title: string;
  required: boolean;
  endpointRefs: string[];
  steps: Array<{ name: string; action: string; description: string }>;
  assertions: string[];
}

export interface TreeDbConformanceResult {
  scenarioId: string;
  status: 'passed' | 'failed' | 'not_configured';
  message?: string;
}

export class TreeDbConformanceAdapter {
  constructor(private readonly options: TreeDbConformanceAdapterOptions) {}

  async runScenario(scenario: TreeDbConformanceScenario): Promise<TreeDbConformanceResult> {
    if (!this.options.serverConfigured) {
      return {
        scenarioId: scenario.id,
        status: 'not_configured',
        message: 'TreeDB server is not configured for TypeScript conformance execution'
      };
    }

    try {
      for (const endpointRef of scenario.endpointRefs) {
        const [method, path] = endpointRef.split(' ', 2) as [Parameters<TreeDbClient['operation']>[0], Parameters<TreeDbClient['operation']>[1]];
        await this.options.client.operation(method, path, {
          pathParams: {
            repo_id: process.env.TREEDB_CONFORMANCE_REPO_ID ?? 'repo_conformance',
            workspace_id: process.env.TREEDB_CONFORMANCE_WORKSPACE_ID ?? 'workspace_conformance',
            node_id: process.env.TREEDB_CONFORMANCE_NODE_ID ?? 'node_conformance',
            job_id: process.env.TREEDB_CONFORMANCE_JOB_ID ?? 'job_conformance',
            snapshot_id: process.env.TREEDB_CONFORMANCE_SNAPSHOT_ID ?? 'snapshot_conformance',
            artifact_id: process.env.TREEDB_CONFORMANCE_ARTIFACT_ID ?? 'artifact_conformance',
            mirror_id: process.env.TREEDB_CONFORMANCE_MIRROR_ID ?? 'mirror_conformance',
            migration_id: process.env.TREEDB_CONFORMANCE_MIGRATION_ID ?? 'migration_conformance',
            upload_id: process.env.TREEDB_CONFORMANCE_UPLOAD_ID ?? 'upload_conformance',
            part_number: process.env.TREEDB_CONFORMANCE_PART_NUMBER ?? 1
          },
          body: method === 'GET' || method === 'DELETE' ? undefined : { dryRun: true }
        });
      }
      return { scenarioId: scenario.id, status: 'passed' };
    } catch (error) {
      return {
        scenarioId: scenario.id,
        status: 'failed',
        message: error instanceof Error ? error.message : 'TreeDB conformance scenario failed'
      };
    }
  }
}
