import type { TreeDxPage } from '../types/index.js';

export function createPage<T>(input: TreeDxPage<T>): TreeDxPage<T> {
  return {
    items: input.items,
    nextCursor: input.nextCursor,
    hasMore: input.hasMore,
    cursor: input.cursor,
    limit: input.limit
  };
}

export function isTreeDxPage(value: unknown): value is TreeDxPage<unknown> {
  return typeof value === 'object' && value !== null && Array.isArray((value as TreeDxPage<unknown>).items);
}

export function getNextCursor<T>(page: TreeDxPage<T>): string | undefined {
  return page.nextCursor;
}
