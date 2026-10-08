import fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import YAML from 'yaml';
import { describe, expect, it } from 'vitest';
import { TreeDxClient, TreeDxConformanceAdapter, type TreeDxConformanceScenario } from '../../src/treedx/index.js';
import { MockTransport } from '../adapters/mock.js';
import { TREEDX_OPENAPI_OPERATIONS } from '../../src/treedx/generated/index.js';

function loadScenarios(): TreeDxConformanceScenario[] {
  const scenariosDir = path.resolve(import.meta.dirname, '../../../sdk-spec/conformance/scenarios');
  return fs.readdirSync(scenariosDir)
    .filter((fileName) => fileName.endsWith('.yaml'))
    .flatMap((fileName) => YAML.parse(fs.readFileSync(path.join(scenariosDir, fileName), 'utf8')).scenarios);
}

describe('TreeDxConformanceAdapter', () => {
  it('workspaces.create_get_close uses declared native scope for exact owner metadata and immutable closed readback', async () => {
    const baseUrl = process.env.TREEDX_BASE_URL, token = process.env.TREEDX_TOKEN;
    const repoId = process.env.TREEDX_CONFORMANCE_REPO_ID, ref = process.env.TREEDX_CONFORMANCE_REF;
    if (!baseUrl || !token || !repoId || !ref) throw new Error('Native workspace conformance bindings are required.');
    const object = (value: unknown): Record<string, unknown> => {
      if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Native workspace response must be an object.');
      return value as Record<string, unknown>;
    };
    const admin = new TreeDxClient({ baseUrl, token }), anonymous = new TreeDxClient({ baseUrl });
    const actorId = `sdk_workspace_reader_${randomUUID().replaceAll('-', '')}`;
    const grant = (capabilities: string[]) => admin.policy.createGrant({ actorId, tenantId: 'tenant_demo',
      repoIds: [repoId], refs: [ref], paths: ['docs/**'], capabilities });
    await grant(['repos:read', 'workspace:create']);
    const actorToken = object(await anonymous.createDevToken({ actorId, tenantId: 'tenant_demo' })).accessToken;
    if (typeof actorToken !== 'string' || !actorToken) throw new Error('Native owning credential is required.');
    const reader = new TreeDxClient({ baseUrl, token: actorToken });
    const created = object(await reader.workspaces.create(repoId, { mode: 'read_only', baseRef: ref, allowedPaths: ['docs/**'] }));
    const workspaceId = created.workspaceId;
    if (typeof workspaceId !== 'string' || !workspaceId) throw new Error('Native allocated workspace identity is required.');
    try {
      await expect(reader.workspaces.get(workspaceId)).rejects.toMatchObject({ status: 403, code: 'permission_denied' });
      const declaration = TREEDX_OPENAPI_OPERATIONS.find(value => value.operationId === 'getWorkspace');
      if (!declaration) throw new Error('Native metadata operation declaration is required.');
      // same_actor is an identity invariant, not a grantable content capability.
      await grant(declaration.requiredCapabilities.filter(value => value !== 'workspace:same_actor'));
      const observed = await reader.workspaces.get(workspaceId).then(value => ({ value: object(value), error: null }),
        error => ({ value: null, error: { code: error.code, status: error.status } }));
      const closed = await reader.workspaces.close(workspaceId).then(value => ({ value: object(value), error: null }),
        error => ({ value: null, error: { code: error.code, status: error.status } }));
      expect(observed.error).toBeNull();
      expect(observed.value).toMatchObject({ workspaceId, repoId, status: created.status });
      expect(closed.error).toBeNull();
      expect(closed.value).toMatchObject({ workspaceId, repoId, status: 'closed' });
      await expect(anonymous.workspaces.get(workspaceId)).rejects.toMatchObject({ status: 401, code: 'authentication_required' });
      await expect(admin.workspaces.get(workspaceId)).rejects.toMatchObject({ status: 403, code: 'permission_denied' });
      await expect(reader.workspaces.get(`${workspaceId}-missing`)).rejects.toMatchObject({ status: 404, code: 'not_found' });
      for (let replay = 0; replay < 2; replay++) await expect(reader.workspaces.get(workspaceId)).resolves.toEqual(closed.value);
    } finally {
      // Close only this allocated resource even after a real denial; never
      // substitute this cleanup grant/read for the observed test result.
      await grant(['files:read']);
      await reader.workspaces.close(workspaceId);
    }
  });
  it('graph.refresh_job_node reads the exact completed native job with bounded nondefault ref authority and immutable replay', async () => {
    const baseUrl = process.env.TREEDX_BASE_URL, token = process.env.TREEDX_CONFORMANCE_JOB_TOKEN;
    const repoId = process.env.TREEDX_CONFORMANCE_REPO_ID, jobId = process.env.TREEDX_CONFORMANCE_JOB_ID;
    const ref = process.env.TREEDX_CONFORMANCE_REF;
    expect(baseUrl, 'Native TreeDX binding is required').toBeTruthy();
    expect(token, 'Authenticated native job reader is required').toBeTruthy();
    expect(repoId, 'Exact native repository is required').toBeTruthy();
    expect(jobId, 'Exact completed native refresh job is required').toBeTruthy();
    expect(ref, 'Exact bounded job ref is required').toBeTruthy();
    if (!baseUrl || !token || !repoId || !jobId || !ref) throw new Error('Native graph job conformance inputs are incomplete.');
    expect(ref).not.toBe('refs/heads/main');
    const client = new TreeDxClient({ baseUrl, token });
    const scope = await client.effectiveScope() as { effectiveScope: { refs: string[] } };
    expect(scope.effectiveScope.refs).toContain(ref);
    for (const forbidden of ['*', '**', 'refs/heads/main']) expect(scope.effectiveScope.refs).not.toContain(forbidden);
    const scenario = loadScenarios().find((entry) => entry.id === 'graph.refresh_job_node');
    expect(scenario?.endpointRefs).toContain('GET /api/v1/repos/{repo_id}/graph/refresh-jobs/{job_id}');
    const before = await client.graph.refreshJob(repoId, jobId) as { job: { jobId: string; repoId: string; ref: string; status: string; graphVersion: string; errorCode: unknown } };
    expect(before.job).toMatchObject({ jobId, repoId, ref, status: 'completed', errorCode: null });
    expect(before.job.graphVersion).toBeTruthy();
    await expect(client.graph.refreshJob(repoId, `${jobId}-missing`)).rejects.toMatchObject({ status: 404, code: 'not_found' });
    const anonymous = new TreeDxClient({ baseUrl });
    await expect(anonymous.graph.refreshJob(repoId, jobId)).rejects.toMatchObject({ status: 401, code: 'authentication_required' });
    await expect(client.graph.refreshJob(repoId, jobId)).resolves.toEqual(before);
  });
  it('loads shared scenario records', () => {
    const scenarios = loadScenarios();
    expect(scenarios.length).toBeGreaterThan(0);
    expect(scenarios.every((scenario) => scenario.id && scenario.capabilityId)).toBe(true);
  });

  it('reports not_configured without a server', async () => {
    const client = new TreeDxClient({ baseUrl: 'http://treedx.test', transport: new MockTransport() });
    const adapter = new TreeDxConformanceAdapter({ client });
    const [scenario] = loadScenarios();
    await expect(adapter.runScenario(scenario)).resolves.toMatchObject({ scenarioId: scenario.id, status: 'not_configured' });
  });
});
