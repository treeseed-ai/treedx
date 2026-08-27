import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { basename, relative, resolve } from 'node:path';
import { releaseEvidenceSchema } from '@treeseed/sdk/development';

const root = resolve(import.meta.dirname, '..');
const sha256 = (path) => `sha256:${createHash('sha256').update(readFileSync(path)).digest('hex')}`;
const evidencePath = resolve(root, process.argv[3] ?? 'release-assets/release-evidence-v1.json');
const output = resolve(root, process.argv[4] ?? 'release-assets');
const files = (directory) => readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
  const path = resolve(directory, entry.name);
  return entry.isDirectory() ? files(path) : [path];
});

if (process.argv[2] === 'seal') {
  const sourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
  const version = JSON.parse(readFileSync(resolve(root, 'packages/ts-sdk/package.json'), 'utf8')).version;
  const imageDigests = [
    ['treedx-image', 'treeseed/treedx', process.env.TREESEED_TREEDX_DIGEST],
    ['treedx-profiler-image', 'treeseed/treedx-profiler', process.env.TREESEED_TREEDX_PROFILER_DIGEST],
  ];
  for (const [, , digest] of imageDigests) if (!/^sha256:[a-f0-9]{64}$/u.test(digest ?? '')) throw new Error('Both exact TreeDX OCI manifest digests are required.');
  const artifacts = imageDigests.map(([id, image, digest]) => ({ id, kind: 'oci-image', identity: `${image}@${digest}`, digest, mediaType: 'application/vnd.oci.image.index.v1+json' }));
  for (const path of files(output).filter((path) => basename(path) !== basename(evidencePath)).sort()) {
    if (!statSync(path).isFile()) continue;
    const identity = relative(output, path);
    const kind = identity.endsWith('.tgz') ? 'npm-package' : identity.endsWith('.crate') || identity.endsWith('.whl') || identity.endsWith('.tar.gz') || identity.endsWith('.tar') ? 'archive' : identity === 'component-release.json' ? 'component-manifest' : identity === 'compose.yml' ? 'compose' : identity.includes('sbom') ? 'sbom' : 'archive';
    const mediaType = identity.endsWith('.json') ? 'application/json' : identity.endsWith('.yml') ? 'application/yaml' : 'application/octet-stream';
    artifacts.push({ id: `asset-${createHash('sha256').update(identity).digest('hex').slice(0, 12)}`, kind, identity, digest: sha256(path), mediaType, size: statSync(path).size });
  }
  const receiptDigest = `sha256:${createHash('sha256').update(`${sourceCommit}\n${artifacts.map(({ digest }) => digest).join('\n')}`).digest('hex')}`;
  const names = ['@treeseed/treedx', 'treedx', 'treedx', 'treedx'];
  const evidence = releaseEvidenceSchema.parse({
    schemaVersion: 'treeseed.release-evidence/v1',
    candidate: { id: `candidate-${sourceCommit.slice(0, 12)}`, receiptDigest, sourceCommit, stagingRef: process.env.GITHUB_REF ?? 'refs/heads/staging', workflowRunId: process.env.GITHUB_RUN_ID ?? '1', createdAt: new Date().toISOString() },
    packages: names.map((name) => ({ projectId: 'treedx', name, version, minimumBump: 'patch' })),
    artifacts,
    contractBundles: [],
    compatibilityAttestations: [],
    verification: { status: 'passed', operations: ['TreeDX release gate', 'four SDK package checks', 'multi-architecture service/profiler OCI builds'], completedAt: new Date().toISOString() },
  });
  writeFileSync(evidencePath, `${JSON.stringify(evidence, null, 2)}\n`);
} else if (process.argv[2] === 'verify') {
  const evidence = releaseEvidenceSchema.parse(JSON.parse(readFileSync(evidencePath, 'utf8')));
  const commit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
  if (evidence.candidate.sourceCommit !== commit) throw new Error('Candidate source commit differs from tagged commit.');
  if (process.env.GITHUB_REF?.startsWith('refs/tags/') && evidence.packages.some(({ version }) => version !== process.env.GITHUB_REF_NAME)) throw new Error('Tag does not match every sealed package version.');
  for (const artifact of evidence.artifacts.filter(({ kind }) => kind !== 'oci-image')) {
    if (sha256(resolve(evidencePath, '..', artifact.identity)) !== artifact.digest) throw new Error(`Candidate artifact digest mismatch: ${artifact.identity}.`);
  }
} else throw new Error('custody requires seal or verify.');
