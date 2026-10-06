import fs from 'node:fs';
import path from 'node:path';
import YAML from 'yaml';
import { describe, expect, it } from 'vitest';
import { TreeDxClient, TreeDxConformanceAdapter, type TreeDxConformanceScenario } from '../../src/treedx/index.js';
import { MockTransport } from '../adapters/mock.js';

function loadScenarios(): TreeDxConformanceScenario[] {
  const scenariosDir = path.resolve(import.meta.dirname, '../../../sdk-spec/conformance/scenarios');
  return fs.readdirSync(scenariosDir)
    .filter((fileName) => fileName.endsWith('.yaml'))
    .flatMap((fileName) => YAML.parse(fs.readFileSync(path.join(scenariosDir, fileName), 'utf8')).scenarios);
}

describe('TreeDxConformanceAdapter', () => {
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
