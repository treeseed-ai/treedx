import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { readFileSync, rmSync } from 'node:fs';
import test from 'node:test';
import { verifyCacheMetrics } from '../../scripts/acceptance/cache-budget.ts';

const require = createRequire(new URL('../../release/package.json', import.meta.url));
const { parse }: { parse(value: string): { services: { treedx: { mem_limit: string; memswap_limit: string; environment: Record<string, string> } }; development: { targets: { id: string; resources: { memoryBytes?: number } }[] } } } = require('yaml');

test('actual governed TreeDX component archive definition contains the confirmed RAM ceiling and finite owning cache budget', () => {
  const target = parse(readFileSync('treeseed.package.yaml', 'utf8')).development.targets.find(target => target.id === 'service');
  assert.equal(target?.resources.memoryBytes, 4 * 1024 ** 3);
  const version = (JSON.parse(readFileSync('release/package.json', 'utf8')) as {version: string}).version;
  try {
    execFileSync(process.execPath, ['release/create-component-release.mjs'], { env: { ...process.env,
      TREESEED_RELEASE: version, TREESEED_SOURCE_COMMIT: 'a'.repeat(40), TREESEED_TREEDX_DIGEST: `sha256:${'b'.repeat(64)}` } });
    const service = parse(readFileSync('release-assets/compose.yml', 'utf8')).services.treedx;
    assert.equal(service.mem_limit, '4g'); assert.equal(service.memswap_limit, '4g');
    assert.equal(service.environment.TREEDX_RUNTIME_MEMORY_BUDGET_MB, '4096');
    const bundle = JSON.parse(readFileSync('release-assets/component-release.json', 'utf8')) as { source: { commit: string }; runtime: { compose: { files: {digest: string}[] } } };
    assert.equal(bundle.source.commit, 'a'.repeat(40)); assert.match(bundle.runtime.compose.files[0]!.digest, /^sha256:[a-f0-9]{64}$/u);
  } finally { rmSync('release-assets', { recursive: true, force: true }); }
});

const metrics = [
  'treedx_runtime_memory_budget_bytes 4294967296',
  'treedx_runtime_cache_budget_bytes 939524096',
  'treedx_native_log_cache_budget_bytes 93952409',
  'treedx_native_log_cache_bytes 128',
  'treedx_cache_approx_bytes{cache="repository_cache"} 128',
  'treedx_cache_approx_bytes{cache="index_cache"} 128',
].join('\n');

test('actual service cache readback requires finite exact budgets and denies missing ambiguous malformed and overflowing observations', () => {
  verifyCacheMetrics(metrics);
  verifyCacheMetrics(metrics.replace('bytes 128', 'bytes 93952409'));
  for (const invalid of [
    '', metrics.replace('4294967296', '0'), metrics.replace('939524096', '0'),
    metrics.replace('93952409', '0'), metrics.replace('bytes 128', 'bytes 93952410'),
    metrics.replace('bytes 128', 'bytes -1'), metrics.replace('bytes 128', 'bytes NaN'),
    metrics.replace('bytes 128', 'bytes '), metrics.replace('bytes 128', 'bytes Infinity'),
    metrics.replace('bytes 128', 'bytes 9007199254740992'), metrics.replace('bytes 128', 'bytes 0.5'), `${metrics}\ntreedx_native_log_cache_bytes 128`,
  ]) assert.throws(() => verifyCacheMetrics(invalid));
  for (const [name, limit] of [['repository_cache', 469_762_048], ['index_cache', 281_857_228]] as const) {
    const original = `treedx_cache_approx_bytes{cache="${name}"} 128`;
    verifyCacheMetrics(metrics.replace(original, original.replace(' 128', ` ${limit}`)));
    for (const replacement of ['', '-1', 'NaN', 'Infinity', '0.5', String(limit + 1)])
      assert.throws(() => verifyCacheMetrics(metrics.replace(original, original.replace('128', replacement))));
    assert.throws(() => verifyCacheMetrics(metrics.replace(original, '')));
    assert.throws(() => verifyCacheMetrics(`${metrics}\n${original}`));
  }
});
