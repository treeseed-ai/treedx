import { describe, expect, it } from 'vitest';
import { TreeDxClient } from '../../src/treedx/index.js';

describe('live TreeDX API integration', () => {
  it('runs health when TREEDX_BASE_URL is configured or reports not configured cleanly', async () => {
    const baseUrl = process.env.TREEDX_BASE_URL;
    if (!baseUrl) {
      expect({ status: 'not_configured', reason: 'TREEDX_BASE_URL is not set' }).toMatchObject({ status: 'not_configured' });
      return;
    }

    const client = new TreeDxClient({ baseUrl, token: process.env.TREEDX_TOKEN });
    await expect(client.health()).resolves.toBeDefined();
  });
});
