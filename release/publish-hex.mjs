import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const archivePath = resolve(process.argv[2] ?? '');
const token = process.env.HEX_API_KEY;
if (!archivePath || !token) throw new Error('Exact Hex archive path and HEX_API_KEY are required.');
const response = await fetch('https://hex.pm/api/publish', { method: 'POST', headers: { Authorization: token, 'Content-Type': 'application/x-tar', Accept: 'application/json', 'User-Agent': 'TreeSeed-release-custody/1' }, body: readFileSync(archivePath) });
if (!response.ok) throw new Error(`Hex rejected exact artifact (${response.status}): ${await response.text()}`);
console.log(await response.text());
