import test from 'node:test';
import assert from 'node:assert/strict';
import { cleanPublishedDate, formatCount, formatRating } from '../lib/format';
import { normalizeBook } from '../lib/normalizers';

test('years stored as floats are shown as plain years', () => {
  assert.equal(cleanPublishedDate('2015.0'), '2015');
  assert.equal(cleanPublishedDate(' 1999.00 '), '1999');
  assert.equal(cleanPublishedDate('2015-03-01'), '2015-03-01');
  assert.equal(normalizeBook({ isbn13: '1', title: 'x', published_date: 2015.0 }).publishedDate, '2015');
  assert.equal(normalizeBook({ isbn13: '1', title: 'x', publishedDate: '2015.0' }).publishedDate, '2015');
});

test('counts and ratings follow the reader locale', () => {
  assert.equal(formatCount(5629932, 'en'), '5,629,932');
  assert.equal(formatCount(5629932, 'tr'), '5.629.932');
  assert.equal(formatCount(5629932, 'en', true), '5.6M');
  assert.equal(formatRating(4.5, 'en'), '4.5');
  assert.equal(formatRating(4.5, 'tr'), '4,5');
  assert.equal(formatRating(4, 'de'), '4,0');
});
