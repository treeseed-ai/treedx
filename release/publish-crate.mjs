import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const cratePath = resolve(process.argv[2] ?? '');
const token = process.env.CARGO_REGISTRY_TOKEN;
if (!cratePath || !token) throw new Error('Exact crate path and CARGO_REGISTRY_TOKEN are required.');
const metadata = JSON.parse(execFileSync('cargo', ['metadata', '--no-deps', '--format-version', '1', '--manifest-path', resolve(import.meta.dirname, '../packages/rust-sdk/Cargo.toml')], { encoding: 'utf8' }));
const pkg = metadata.packages[0];
const readmeFile = pkg.readme ? resolve(pkg.manifest_path, '..', pkg.readme) : null;
const upload = {
  name: pkg.name, vers: pkg.version,
  deps: pkg.dependencies.map((dep) => ({ name: dep.name, version_req: dep.req, features: dep.features, optional: dep.optional, default_features: dep.uses_default_features, target: dep.target, kind: dep.kind ?? 'normal', registry: dep.registry, explicit_name_in_toml: dep.rename })),
  features: pkg.features, authors: pkg.authors, description: pkg.description, documentation: pkg.documentation, homepage: pkg.homepage,
  readme: readmeFile ? readFileSync(readmeFile, 'utf8') : null, readme_file: pkg.readme ? pkg.readme.split('/').at(-1) : null,
  keywords: pkg.keywords, categories: pkg.categories, license: pkg.license, license_file: pkg.license_file ? pkg.license_file.split('/').at(-1) : null,
  repository: pkg.repository, badges: {}, links: pkg.links, rust_version: pkg.rust_version,
};
const json = Buffer.from(JSON.stringify(upload));
const crate = readFileSync(cratePath);
const length = (size) => { const value = Buffer.alloc(4); value.writeUInt32LE(size); return value; };
const response = await fetch('https://crates.io/api/v1/crates/new', { method: 'PUT', headers: { Authorization: token, 'Content-Type': 'application/octet-stream', Accept: 'application/json', 'User-Agent': 'TreeSeed-release-custody/1' }, body: Buffer.concat([length(json.length), json, length(crate.length), crate]) });
if (!response.ok) throw new Error(`crates.io rejected exact artifact (${response.status}): ${await response.text()}`);
const result = await response.json();
if (result.errors?.length) throw new Error(`crates.io rejected exact artifact: ${JSON.stringify(result.errors)}`);
console.log(JSON.stringify(result));
