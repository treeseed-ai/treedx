import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import YAML from 'yaml';
import { resolveAuthorizationHeader, StaticBearerTokenAuthProvider } from '../../src/treedx/index.js';

describe('auth helpers', () => {
  it('complete SDK verification provisions the real engine and a separate bounded job reader before conformance and always owns teardown', () => {
    const root = path.resolve(import.meta.dirname, '../../../..');
    const job = YAML.parse(fs.readFileSync(path.join(root, '.github/workflows/release-gate.yml'), 'utf8')).jobs['test-typescript-sdk'];
    const start = job.steps.findIndex((step: { run?: string }) => step.run === 'node --import tsx scripts/native-conformance.ts start');
    const worker = job.steps.findIndex((step: { run?: string }) => step.run === 'cargo build -p treedx_git --bin treedx_git_worker');
    const conformance = job.steps.findIndex((step: { run?: string }) => step.run === 'npm run test:treedx-conformance');
    const full = job.steps.findIndex((step: { run?: string }) => step.run === 'npm test');
    const stop = job.steps.findIndex((step: { run?: string }) => step.run === 'node --import tsx scripts/native-conformance.ts stop');
    expect(worker).toBeGreaterThan(-1); expect(start).toBeGreaterThan(worker); expect(conformance).toBeGreaterThan(start); expect(full).toBeGreaterThan(conformance);
    expect(stop).toBeGreaterThan(full); expect(job.steps[stop].if).toBe('always()');
    const python = YAML.parse(fs.readFileSync(path.join(root, '.github/workflows/release-gate.yml'), 'utf8')).jobs['test-python-sdk'];
    const pythonStart = python.steps.findIndex((step: { run?: string }) => step.run === 'node --import tsx scripts/native-conformance.ts start');
    const pythonWorker = python.steps.findIndex((step: { run?: string }) => step.run === 'cargo build -p treedx_git --bin treedx_git_worker');
    const pythonCompile = python.steps.findIndex((step: { run?: string; 'working-directory'?: string }) => step['working-directory'] === 'apps/api' && step.run?.includes('mix compile'));
    const pythonIntegration = python.steps.findIndex((step: { run?: string }) => step.run === 'python -m pytest tests/integration');
    const pythonFull = python.steps.findIndex((step: { run?: string }) => step.run === 'python -m pytest');
    const pythonStop = python.steps.findIndex((step: { run?: string }) => step.run === 'node --import tsx scripts/native-conformance.ts stop');
    expect(pythonWorker).toBeGreaterThan(-1); expect(pythonCompile).toBeGreaterThan(pythonWorker);
    expect(pythonStart).toBeGreaterThan(pythonCompile); expect(pythonIntegration).toBeGreaterThan(pythonStart);
    expect(pythonFull).toBeGreaterThan(pythonIntegration); expect(pythonStop).toBeGreaterThan(pythonFull);
    expect(python.steps[pythonStart]['working-directory']).toBe('packages/ts-sdk');
    expect(python.steps[pythonStop]['working-directory']).toBe('packages/ts-sdk'); expect(python.steps[pythonStop].if).toBe('always()');
    expect(python.strategy.matrix.include.map((entry: { arch: string }) => entry.arch)).toEqual(['amd64', 'arm64']);
    const fixture = fs.readFileSync(path.join(root, 'packages/ts-sdk/scripts/native-conformance.ts'), 'utf8');
    expect(fixture).toContain("refs: [ref]"); expect(fixture).toContain("capabilities: ['graph:query']");
    expect(fixture).toContain('await admin.graph.refresh('); expect(fixture).toContain('await reader.graph.refreshJob(');
    expect(fixture).toContain('Never signal an unowned process');
    const complete = fs.readFileSync(path.join(root, 'scripts/verification/test-sdk-packages.sh'), 'utf8');
    expect(complete).toContain('node --import tsx scripts/native-conformance.ts start');
    expect(complete).toContain('node --import tsx scripts/native-conformance.ts stop');
    expect(complete).toContain('trap cleanup EXIT');
    expect(complete.indexOf('scripts/native-conformance.ts start')).toBeLessThan(complete.indexOf('npm test', complete.indexOf('section "TypeScript SDK"')));
  });
  it('returns static bearer tokens', async () => {
    await expect(Promise.resolve(new StaticBearerTokenAuthProvider('token').getToken())).resolves.toBe('token');
  });

  it('formats authorization headers', async () => {
    await expect(resolveAuthorizationHeader({ token: 'abc' })).resolves.toEqual({ Authorization: 'Bearer abc' });
  });
});
