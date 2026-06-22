import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

process.env.TREESEED_TENANT_ROOT ??= dirname(fileURLToPath(import.meta.url));

const { createTreeseedTenantSite } = await import('@treeseed/core/config');

export default createTreeseedTenantSite();
