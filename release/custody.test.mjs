import { readFileSync } from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

test('tag promotion consumes sealed artifacts and contains no build command', () => {
  const workflow = readFileSync('.github/workflows/publish.yml', 'utf8');
  const promotion = workflow.slice(workflow.indexOf('  promote:'));
  assert.match(promotion, /Download exact accepted candidate/u);
  assert.doesNotMatch(promotion, /(?:docker\s+build(?:\s|$)|docker\/build-push-action|npm\s+(?:run\s+)?build|python\s+-m\s+build|cargo\s+(?:build|package|publish)|mix\s+hex\.build)/u);
  assert.match(promotion, /custody -- verify/u);
});

test('legacy release gate cannot publish a tag', () => {
  const workflow = readFileSync('.github/workflows/release-gate.yml', 'utf8');
  const pushTrigger = workflow.slice(workflow.indexOf('  push:'), workflow.indexOf('\nenv:'));
  assert.doesNotMatch(pushTrigger, /\n\s+tags:/u);
  const plan = workflow.slice(workflow.indexOf('  publish-plan:'), workflow.indexOf('  build-publish-image:'));
  assert.doesNotMatch(plan, /startsWith\(github\.ref, 'refs\/tags\/'\)/u);
});
