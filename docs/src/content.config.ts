import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const tenantRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
process.env.TREESEED_TENANT_ROOT ??= tenantRoot;

const { createTreeseedTenantCollections } = await import('@treeseed/core/content-config');

export const collections = createTreeseedTenantCollections();
