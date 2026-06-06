import { describe, expect, it } from 'vitest';
import { createPage, getNextCursor, isTreeDxPage } from '../../src/treedx/index.js';

describe('pagination helpers', () => {
  it('preserves page metadata', () => {
    const page = createPage({ items: [1], nextCursor: 'next', hasMore: true });
    expect(isTreeDxPage(page)).toBe(true);
    expect(getNextCursor(page)).toBe('next');
    expect(page.hasMore).toBe(true);
  });
});
