import test from 'node:test';
import assert from 'node:assert/strict';
import { sanitizeRedirect } from '../app/login/page';

test('sanitizeRedirect: permits valid internal relative paths', () => {
  assert.equal(sanitizeRedirect('/favorites'), '/favorites');
  assert.equal(sanitizeRedirect('/catalog'), '/catalog');
  assert.equal(sanitizeRedirect('/book/9780143127741'), '/book/9780143127741');
  assert.equal(sanitizeRedirect('/catalog?genre=Fiction&sort=rating'), '/catalog?genre=Fiction&sort=rating');
});

test('sanitizeRedirect: falls back to /catalog for null, undefined, or empty values', () => {
  assert.equal(sanitizeRedirect(null), '/catalog');
  assert.equal(sanitizeRedirect(''), '/catalog');
  assert.equal(sanitizeRedirect('   '), '/catalog');
});

test('sanitizeRedirect: rejects external URLs and open redirect vectors', () => {
  // Protocol-relative URLs
  assert.equal(sanitizeRedirect('//evil.com'), '/catalog');
  assert.equal(sanitizeRedirect('//evil.com/path'), '/catalog');

  // Backslash variants
  assert.equal(sanitizeRedirect('/\\evil.com'), '/catalog');
  assert.equal(sanitizeRedirect('\\evil.com'), '/catalog');

  // Full absolute URLs
  assert.equal(sanitizeRedirect('https://evil.com'), '/catalog');
  assert.equal(sanitizeRedirect('http://attacker.com/steal-session'), '/catalog');

  // Javascript / data protocols
  assert.equal(sanitizeRedirect('javascript:alert(document.cookie)'), '/catalog');
  assert.equal(sanitizeRedirect('data:text/html,<script>alert(1)</script>'), '/catalog');
});
