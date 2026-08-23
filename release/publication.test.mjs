import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, rmSync } from 'node:fs';
import test from 'node:test';

const digest = `sha256:${'b'.repeat(64)}`;
test.afterEach(() => rmSync('release-assets', { recursive: true, force: true }));

test('materializes an SDK-validated immutable production bundle', () => {
  execFileSync(process.execPath, ['release/create-component-release.mjs'], {
    env: { ...process.env, TREESEED_RELEASE: '0.3.0-rc.5', TREESEED_SOURCE_COMMIT: 'a'.repeat(40), TREESEED_TREEDX_DIGEST: digest },
  });
  const compose = readFileSync('release-assets/compose.yml', 'utf8');
  const bundle = JSON.parse(readFileSync('release-assets/component-release.json', 'utf8'));
  assert.doesNotMatch(compose, /\bbuild\s*:/u);
  assert.doesNotMatch(compose, /^\s+ports:/mu);
  assert.doesNotMatch(compose, /docker\.sock/u);
  assert.match(compose, new RegExp(`treeseed/treedx@${digest}`));
  assert.equal(bundle.componentId, 'treedx');
  assert.equal(bundle.track, 'development');
  assert.equal(bundle.stableBase.catalogDigest, null);
  assert.equal(bundle.runtime.services[0].endpoints[0].defaultAlias, 'treedx.treeseed.localhost');
});
