import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { componentReleaseSchema, deploymentDigest } from '@treeseed/sdk/deployment';

const release = process.env.TREESEED_RELEASE;
const sourceCommit = process.env.TREESEED_SOURCE_COMMIT;
const imageDigest = process.env.TREESEED_TREEDX_DIGEST;
if (!release || !sourceCommit || !imageDigest) throw new Error('Release, exact source commit, and multi-architecture image digest are required.');
if (!/^[a-f0-9]{40}$/u.test(sourceCommit) || !/^sha256:[a-f0-9]{64}$/u.test(imageDigest)) throw new Error('Source or image digest is malformed.');

const track = release.includes('-rc.') ? 'development' : 'stable';
const revision = Number(process.env.TREESEED_COMPONENT_REVISION ?? '1');
if (!Number.isInteger(revision) || revision < 1) throw new Error('Component revision must be a positive integer.');
const debianRelease = `${release.replace(/-rc\.(\d+)$/u, '~rc$1')}-${revision}`;
const compose = readFileSync(resolve('release/compose.template.yml'), 'utf8').replace('@TREEDX_IMAGE@', `treeseed/treedx@${imageDigest}`);
if (/\bbuild\s*:/u.test(compose) || /@TREEDX_IMAGE@/u.test(compose)) throw new Error('Production Compose bundle is not fully materialized.');
const composeDigest = `sha256:${createHash('sha256').update(compose).digest('hex')}`;
const runtime = {
  schemaVersion: 'treeseed.package-runtime/v1',
  componentId: 'treedx',
  version: debianRelease,
  compose: { projectName: 'treeseed-treedx', files: [{ path: 'compose.yml', digest: composeDigest }] },
  services: [{
    id: 'treedx',
    composeService: 'treedx',
    endpoints: [{
      id: 'http', protocol: 'http', port: 4000, visibility: 'host',
      defaultAlias: 'treedx.treeseed.localhost', aliasOverride: true,
      tls: 'edge', authentication: 'application',
      healthGate: { protocol: 'http', path: '/api/v1/ready', timeoutSeconds: 120 },
    }],
  }],
  configuration: {
    environment: [
      'TREEDX_GIT_ALLOWED_HOSTS', 'TREEDX_JWT_ALLOWED_ALGS', 'TREEDX_JWT_AUDIENCE', 'TREEDX_JWT_ISSUER',
      'TREEDX_REMOTE_CREDENTIAL_BROKER_SERVICE_ID',
    ].map((name) => ({ name, required: true, source: 'configuration' })).concat([
      { name: 'TREEDX_BOOTSTRAP_TRUST_ACTOR_ID', required: true, source: 'configuration', default: 'treeseed-api' },
      { name: 'TREEDX_BOOTSTRAP_TRUST_TENANT_ID', required: true, source: 'configuration', default: 'treeseed-control-plane' },
    ]),
    secretEnvironment: [
      'TREEDX_REMOTE_CREDENTIAL_BROKER_ASSERTION', 'TREEDX_SECRET_KEY_BASE',
    ].map((name) => ({ name, required: true })),
    secretFiles: [],
    files: [],
  },
  stateVolumes: [{ id: 'data', volume: '/var/lib/treeseed/components/treedx/data', backup: 'required' }],
  migrations: [{ id: 'treedx-snapshot', order: 0, backupRequired: true }],
  requiredCapabilities: ['docker-compose'],
  dependencies: [{ id: 'control-plane', capability: 'control-plane-api', locality: 'either', optional: false }],
};
const evidenceUrl = `https://hub.docker.com/r/treeseed/treedx/tags?name=${encodeURIComponent(release)}`;
const bundle = componentReleaseSchema.parse({
  schemaVersion: 'treeseed.component-release/v1',
  componentId: 'treedx',
  release: debianRelease,
  applicationVersion: release,
  revision,
  track,
  source: { repository: 'treeseed-ai/treedx', commit: sourceCommit },
  stableBase: track === 'development' ? { releaseRange: '>=0.1.0 <0.2.0', compatibilityId: 'treeseed-linux-amd64-v1', catalogDigest: null } : null,
  packages: [{ name: 'treeseed-component-treedx', version: debianRelease, architecture: 'all', origin: 'TreeSeed Deployment', order: 40 }],
  images: [{ role: 'treedx', repository: 'treeseed/treedx', digest: imageDigest, platforms: ['linux/amd64', 'linux/arm64'], consumers: ['treedx'] }],
  runtime,
  runtimeDigest: deploymentDigest(runtime),
  rollback: { compatible: true, requiresBackup: true },
  evidence: { provenance: [evidenceUrl], sboms: [evidenceUrl], vulnerabilities: [] },
});

const output = resolve('release-assets');
mkdirSync(output, { recursive: true });
writeFileSync(resolve(output, 'compose.yml'), compose);
writeFileSync(resolve(output, 'component-release.json'), `${JSON.stringify(bundle, null, 2)}\n`);
console.log(JSON.stringify({ ok: true, release, sourceCommit, imageDigest, runtimeDigest: bundle.runtimeDigest }));
