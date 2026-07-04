import type { TreeDxClient } from '../client/TreeDxClient.js';

export interface TreeDxConformanceAdapterOptions {
  client: TreeDxClient;
  serverConfigured?: boolean;
}

export interface TreeDxConformanceScenario {
  id: string;
  capabilityId: string;
  title: string;
  required: boolean;
  endpointRefs: string[];
  steps: Array<{ name: string; action: string; description: string }>;
  assertions: string[];
}

export interface TreeDxConformanceResult {
  scenarioId: string;
  status: 'passed' | 'failed' | 'not_configured';
  message?: string;
}

export class TreeDxConformanceAdapter {
  constructor(private readonly options: TreeDxConformanceAdapterOptions) {}

  async runScenario(scenario: TreeDxConformanceScenario): Promise<TreeDxConformanceResult> {
    if (!this.options.serverConfigured) {
      return {
        scenarioId: scenario.id,
        status: 'not_configured',
        message: 'TreeDX server is not configured for TypeScript conformance execution'
      };
    }

    try {
      for (const endpointRef of scenario.endpointRefs) {
        const [method, path] = endpointRef.split(' ', 2) as [Parameters<TreeDxClient['operation']>[0], Parameters<TreeDxClient['operation']>[1]];
        await this.options.client.operation(method, path, {
          pathParams: {
            repo_id: process.env.TREEDX_CONFORMANCE_REPO_ID ?? 'repo_conformance',
            workspace_id: process.env.TREEDX_CONFORMANCE_WORKSPACE_ID ?? 'workspace_conformance',
            node_id: process.env.TREEDX_CONFORMANCE_NODE_ID ?? 'node_conformance',
            job_id: process.env.TREEDX_CONFORMANCE_JOB_ID ?? 'job_conformance',
            snapshot_id: process.env.TREEDX_CONFORMANCE_SNAPSHOT_ID ?? 'snapshot_conformance',
            artifact_id: process.env.TREEDX_CONFORMANCE_ARTIFACT_ID ?? 'artifact_conformance',
            mirror_id: process.env.TREEDX_CONFORMANCE_MIRROR_ID ?? 'mirror_conformance',
            migration_id: process.env.TREEDX_CONFORMANCE_MIGRATION_ID ?? 'migration_conformance',
            upload_id: process.env.TREEDX_CONFORMANCE_UPLOAD_ID ?? 'upload_conformance',
            part_number: process.env.TREEDX_CONFORMANCE_PART_NUMBER ?? 1
          },
          body: method === 'GET' || method === 'DELETE' ? undefined : { planOnly: true }
        });
      }
      return { scenarioId: scenario.id, status: 'passed' };
    } catch (error) {
      return {
        scenarioId: scenario.id,
        status: 'failed',
        message: error instanceof Error ? error.message : 'TreeDX conformance scenario failed'
      };
    }
  }
}
