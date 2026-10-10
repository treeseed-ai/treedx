import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export function verifyCacheMetrics(metrics: string): void {
  function gauge(name: string): number {
    const lines = metrics.split('\n').filter(line => line.startsWith(`${name} `));
    assert.equal(lines.length, 1, `missing or ambiguous ${name}`);
    const raw = lines[0]!.slice(name.length + 1);
    assert.match(raw, /^\d+$/u, `invalid ${name}`);
    const value = Number(raw);
    assert.ok(Number.isSafeInteger(value) && value >= 0, `invalid ${name}`);
    return value;
  }
  assert.equal(gauge('treedx_runtime_memory_budget_bytes'), 4_294_967_296);
  assert.equal(gauge('treedx_runtime_cache_budget_bytes'), 939_524_096);
  const budget = gauge('treedx_native_log_cache_budget_bytes');
  assert.equal(budget, 93_952_409);
  assert.ok(gauge('treedx_native_log_cache_bytes') <= budget, 'native cache exceeds its RAM share');
  assert.ok(gauge('treedx_cache_approx_bytes{cache="repository_cache"}') <= 469_762_048,
    'repository cache exceeds its RAM share');
  assert.ok(gauge('treedx_cache_approx_bytes{cache="index_cache"}') <= 281_857_228,
    'graph cache exceeds its RAM share');
}

async function verifyContainer(container: string, url: string): Promise<void> {
  assert.match(container, /^[a-f0-9]{12,64}$/u);
  const docker = (args: string[]) => execFileSync('docker', args, { encoding: 'utf8', timeout: 10_000 });
  const state = JSON.parse(docker(['inspect', container])) as { HostConfig: { Memory: number; MemorySwap: number }; State: { Running: boolean; OOMKilled: boolean } }[];
  assert.equal(state.length, 1);
  assert.equal(state[0]!.HostConfig.Memory, 4_294_967_296);
  assert.equal(state[0]!.HostConfig.MemorySwap, 4_294_967_296);
  assert.equal(state[0]!.State.Running, true);
  assert.equal(state[0]!.State.OOMKilled, false);
  // Inspect the actual cgroup as well as Docker's requested configuration.
  const limit = docker(['exec', container, 'sh', '-c', 'if test -f /sys/fs/cgroup/memory.max; then cat /sys/fs/cgroup/memory.max; else cat /sys/fs/cgroup/memory/memory.limit_in_bytes; fi']);
  assert.equal(Number(limit.trim()), 4_294_967_296);
  const response = await fetch(new URL('/metrics', url), { signal: AbortSignal.timeout(10_000) });
  assert.equal(response.status, 200);
  verifyCacheMetrics(await response.text());
  console.log('TreeDX actual container ceiling=4294967296 cache pool=939524096; native, repository and graph caches fit their shares');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.equal(process.argv.length, 4, 'expected container ID and service URL');
  await verifyContainer(process.argv[2]!, process.argv[3]!);
}
