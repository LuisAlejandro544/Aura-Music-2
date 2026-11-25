import test from 'node:test';
import assert from 'node:assert/strict';
import { getWebHelloMessage } from './appMeta';

test('getWebHelloMessage returns exact Hello World text', () => {
  assert.equal(getWebHelloMessage(), 'Hello World');
});
