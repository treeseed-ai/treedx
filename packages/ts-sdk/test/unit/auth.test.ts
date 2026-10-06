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
    const conformance = job.steps.findIndex((step: { run?: string }) => step.run === 'npm run test:treedx-conformance');
    const full = job.steps.findIndex((step: { run?: string }) => step.run === 'npm test');
    const stop = job.steps.findIndex((step: { run?: string }) => step.run === 'node --import tsx scripts/native-conformance.ts stop');
    expect(start).toBeGreaterThan(-1); expect(conformance).toBeGreaterThan(start); expect(full).toBeGreaterThan(conformance);
    expect(stop).toBeGreaterThan(full); expect(job.steps[stop].if).toBe('always()');
    const fixture = fs.readFileSync(path.join(root, 'packages/ts-sdk/scripts/native-conformance.ts'), 'utf8');
    expect(fixture).toContain("refs: [ref]"); expect(fixture).toContain("capabilities: ['graph:query']");
    expect(fixture).toContain('await admin.graph.refresh('); expect(fixture).toContain('await reader.graph.refreshJob(');
    expect(fixture).toContain('Never signal an unowned process');
  });
  it('returns static bearer tokens', async () => {
    await expect(Promise.resolve(new StaticBearerTokenAuthProvider('token').getToken())).resolves.toBe('token');
  });

  it('formats authorization headers', async () => {
    await expect(resolveAuthorizationHeader({ token: 'abc' })).resolves.toEqual({ Authorization: 'Bearer abc' });
  });
});
