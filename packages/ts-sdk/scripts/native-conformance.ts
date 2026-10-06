import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { appendFile, mkdtemp, mkdir, open, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { TreeDxClient } from '../src/treedx/index.js';

// Disposable native test provisioning only. The original SDK/engine own all calls.
const [action] = process.argv.slice(2), prefix = join(tmpdir(), 'treedx-sdk-native-');
const engine = resolve(import.meta.dirname, '../../../apps/api');
function record(value: unknown): Record<string, unknown> {
  assert.ok(value && typeof value === 'object' && !Array.isArray(value));
  return value as Record<string, unknown>;
}
function text(value: unknown): string { assert.ok(typeof value === 'string' && value.length); return value; }

async function exportBindings(values: Record<string, string>) {
  const destination = process.env.GITHUB_ENV;
  assert.ok(destination, 'Native setup needs an explicit environment output file');
  for (const [key, value] of Object.entries(values)) {
    assert.match(key, /^[A-Z_]+$/u); assert.match(value, /^[A-Za-z0-9_./:-]+$/u);
    if (key.endsWith('TOKEN') && process.env.GITHUB_ACTIONS === 'true') process.stdout.write(`::add-mask::${value}\n`);
    await appendFile(destination, `${key}=${value}\n`, { mode: 0o600 });
  }
}

async function stop(root: string) {
  assert.equal(await realpath(root), root); assert.ok(root.startsWith(prefix) && root !== prefix);
  let pid: number;
  try { pid = Number(await readFile(join(root, 'engine.pid'), 'utf8')); }
  catch (error) { if (error instanceof Error && 'code' in error && error.code === 'ENOENT') return; throw error; }
  assert.ok(Number.isInteger(pid) && pid > 1);
  try {
    const environment = await readFile(`/proc/${pid}/environ`, 'utf8');
    assert.ok(environment.split('\0').includes(`TREEDX_SDK_NATIVE_ROOT=${root}`), 'Never signal an unowned process');
    process.kill(-pid, 'SIGTERM');
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) { try { process.kill(-pid, 0); } catch { return; } await delay(25); }
    process.kill(-pid, 'SIGKILL'); throw new Error('Native SDK fixture required forced cleanup');
  } catch (error) {
    if (!(error instanceof Error && 'code' in error && ['ENOENT', 'ESRCH'].includes(String(error.code)))) throw error;
  }
}

if (action === 'start') {
  const root = await mkdtemp(prefix); await exportBindings({ TREEDX_SDK_NATIVE_ROOT: root });
  try {
    const reservation = createServer(); await new Promise<void>(accept => reservation.listen(0, '127.0.0.1', accept));
    const address = reservation.address(); assert.ok(address && typeof address !== 'string');
    const port = address.port; await new Promise<void>(accept => reservation.close(() => accept()));
    const environment: NodeJS.ProcessEnv = { ...process.env };
    // A disposable engine must not inherit another engine's legacy aliases or credentials.
    for (const name of Object.keys(environment)) if (name.startsWith('TREEDX_') || name.startsWith('TREESEED_TREEDX_')) delete environment[name];
    Object.assign(environment, { MIX_ENV: 'dev', PORT: String(port), PHX_SERVER: 'true',
      TREESEED_TREEDX_ENV: 'dev', TREESEED_TREEDX_AUTH_MODE: 'dev', TREESEED_TREEDX_DATA_DIR: join(root, 'data'),
      TREEDX_DEV_ACTOR_ID: 'actor_demo', TREEDX_DEV_TENANT_ID: 'tenant_demo', TREEDX_SDK_NATIVE_ROOT: root });
    delete environment.GITHUB_TOKEN; delete environment.GH_TOKEN;
    const log = await open(join(root, 'engine.log'), 'a', 0o600);
    try {
      const child = spawn('mix', ['phx.server', '--no-compile', '--no-deps-check'], {
        cwd: engine, env: environment, detached: true, stdio: ['ignore', log.fd, log.fd] });
      await new Promise<void>((accept, reject) => { child.once('spawn', accept); child.once('error', reject); });
      assert.ok(child.pid); await writeFile(join(root, 'engine.pid'), String(child.pid)); child.unref();
    } finally { await log.close(); }
    const baseUrl = `http://127.0.0.1:${port}`;
    let ready = false;
    for (let attempt = 0; attempt < 120; attempt++) {
      try { ready = (await fetch(`${baseUrl}/api/v1/health`, { signal: AbortSignal.timeout(1000) })).ok; } catch { ready = false; }
      if (ready) break; await delay(1000);
    }
    assert.ok(ready, 'Native SDK engine did not become healthy');
    const anonymous = new TreeDxClient({ baseUrl });
    const token = text(record(await anonymous.createDevToken()).accessToken);
    const admin = new TreeDxClient({ baseUrl, token });
    const name = 'sdk-native-job', path = join(root, 'data/repos/bare', name), ref = 'refs/heads/staging';
    await mkdir(join(path, 'docs'), { recursive: true });
    const git = (...args: string[]) => execFileSync('git', args, { cwd: path, stdio: 'pipe' });
    git('init', '-b', 'main'); git('config', 'user.name', 'Native SDK fixture'); git('config', 'user.email', 'sdk-fixture@example.invalid');
    await writeFile(join(path, 'docs/readme.md'), '# Native graph job\n');
    git('add', '.'); git('commit', '-m', 'Native job input'); git('branch', 'staging');
    const repoId = text(record(record(await admin.repositories.register({ name, localPath: path })).repo).repoId);
    const jobId = text(record(await admin.graph.refresh(repoId, { ref, paths: ['docs/**'] })).jobId);
    const actorId = 'sdk_native_job_reader';
    await admin.policy.createGrant({ actorId, tenantId: 'tenant_demo', repoIds: [repoId], refs: [ref],
      paths: ['docs/**'], capabilities: ['graph:query'] });
    const readerToken = text(record(await anonymous.createDevToken({ actorId, tenantId: 'tenant_demo' })).accessToken);
    const reader = new TreeDxClient({ baseUrl, token: readerToken });
    const scope = record(record(await reader.effectiveScope()).effectiveScope);
    assert.deepEqual(scope.refs, [ref]); assert.deepEqual(scope.repoIds, [repoId]);
    const job = record(record(await reader.graph.refreshJob(repoId, jobId)).job);
    assert.equal(job.status, 'completed'); assert.equal(job.ref, ref); assert.equal(job.jobId, jobId);
    await exportBindings({ TREEDX_BASE_URL: baseUrl, TREEDX_TOKEN: token, TREEDX_CONFORMANCE_JOB_TOKEN: readerToken,
      TREEDX_CONFORMANCE_REPO_ID: repoId, TREEDX_CONFORMANCE_JOB_ID: jobId, TREEDX_CONFORMANCE_REF: ref,
      TREEDX_CONFORMANCE_TMP: root, TREEDX_CONFORMANCE_ALLOW_ADMIN: '1', TREEDX_CONFORMANCE_ALLOW_INTERNAL: '1',
      TREEDX_CONFORMANCE_ALLOW_DESTRUCTIVE: '1' });
  } catch (error) { await stop(root); throw error; }
} else if (action === 'stop') {
  const root = process.env.TREEDX_SDK_NATIVE_ROOT;
  if (root) { await stop(root); await rm(root, { recursive: true }); }
} else throw new Error('Native SDK fixture requires start or stop');
