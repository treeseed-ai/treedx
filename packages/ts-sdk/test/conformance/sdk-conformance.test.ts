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
