import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, rmSync } from 'node:fs';
import test from 'node:test';

const digest = `sha256:${'b'.repeat(64)}`;
const releaseVersion = JSON.parse(readFileSync('release/package.json', 'utf8')).version;
test.afterEach(() => rmSync('release-assets', { recursive: true, force: true }));

test('materializes an SDK-validated immutable production bundle', () => {
  execFileSync(process.execPath, ['release/create-component-release.mjs'], {
    env: { ...process.env, TREESEED_RELEASE: releaseVersion, TREESEED_SOURCE_COMMIT: 'a'.repeat(40), TREESEED_TREEDX_DIGEST: digest },
  });
  const compose = readFileSync('release-assets/compose.yml', 'utf8');
  const bundle = JSON.parse(readFileSync('release-assets/component-release.json', 'utf8'));
  assert.doesNotMatch(compose, /\bbuild\s*:/u);
  assert.doesNotMatch(compose, /^\s+ports:/mu);
  assert.doesNotMatch(compose, /docker\.sock/u);
  assert.match(compose, new RegExp(`treeseed/treedx@${digest}`));
  assert.match(compose, /test: \["CMD", "\/app\/bin\/treedx_healthcheck"\]/u);
  assert.match(readFileSync('Dockerfile', 'utf8'), /_build\/prod\/rel\/treedx\/bin\/treedx_healthcheck/u);
  assert.equal(bundle.componentId, 'treedx');
  assert.equal(bundle.track, 'development');
  assert.equal(bundle.stableBase.catalogDigest, null);
  assert.equal(bundle.release, `${releaseVersion.replace(/-rc\.(\d+)$/u, '~rc$1')}-1`);
  assert.equal(bundle.revision, 1);
  assert.match(bundle.runtime.compose.files[0].digest, /^sha256:[a-f0-9]{64}$/u);
  assert.equal(bundle.runtime.dependencies[0].id, 'control-plane');
  assert.doesNotMatch(compose, /http:\/\/api:/u);
  const publicInputs = bundle.runtime.configuration.environment.map(({ name }) => name).sort();
  const secretInputs = bundle.runtime.configuration.secretEnvironment.map(({ name }) => name).sort();
  assert.deepEqual(publicInputs, [
    'TREEDX_BOOTSTRAP_TRUST_ACTOR_ID', 'TREEDX_BOOTSTRAP_TRUST_TENANT_ID',
    'TREEDX_GIT_ALLOWED_HOSTS', 'TREEDX_JWT_ALLOWED_ALGS', 'TREEDX_JWT_AUDIENCE', 'TREEDX_JWT_ISSUER',
    'TREEDX_REMOTE_CREDENTIAL_BROKER_SERVICE_ID',
  ]);
  assert.deepEqual(secretInputs, ['TREEDX_REMOTE_CREDENTIAL_BROKER_ASSERTION', 'TREEDX_SECRET_KEY_BASE']);
  for (const name of [...publicInputs, ...secretInputs]) assert.ok(compose.includes(`${name}: ` + '${' + `${name}:?`));
  const publicDeclarations = Object.fromEntries(bundle.runtime.configuration.environment.map((input) => [input.name, input]));
  assert.equal(publicDeclarations.TREEDX_BOOTSTRAP_TRUST_ACTOR_ID.default, 'treeseed-api');
  assert.equal(publicDeclarations.TREEDX_BOOTSTRAP_TRUST_TENANT_ID.default, 'treeseed-control-plane');
  assert.equal(bundle.runtime.services[0].endpoints[0].defaultAlias, 'treedx.treeseed.localhost');
});
