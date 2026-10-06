import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const tag = process.argv[2] || process.env.GITHUB_REF_NAME;
const semver = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/u;
if (!tag || !semver.test(tag)) throw new Error('A semantic release tag without a v prefix is required.');

const versions = [
  JSON.parse(readFileSync(resolve(root, 'packages/ts-sdk/package.json'), 'utf8')).version,
  /version\s*=\s*"([^"]+)"/u.exec(readFileSync(resolve(root, 'packages/python-sdk/pyproject.toml'), 'utf8'))?.[1],
  /version\s*=\s*"([^"]+)"/u.exec(readFileSync(resolve(root, 'packages/rust-sdk/Cargo.toml'), 'utf8'))?.[1],
  /version:\s*"([^"]+)"/u.exec(readFileSync(resolve(root, 'packages/elixir-sdk/mix.exs'), 'utf8'))?.[1],
  /version:\s*"([^"]+)"/u.exec(readFileSync(resolve(root, 'apps/api/mix.exs'), 'utf8'))?.[1],
];
if (versions.some((version) => version !== tag)) throw new Error(`Tag ${tag} does not match every TreeDX package version: ${versions.join(', ')}.`);
console.log(`TreeDX release tag ${tag} matches every package version.`);
