import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { LOCALES, translate, type TranslationKey } from '../lib/i18n';
import { LANGUAGES, resolveLanguage } from '../lib/preferences';

// Key completeness is enforced by the TypeScript type of LOCALES; these tests guard
// what the compiler cannot see: placeholders, empty strings, and inline translations.

const placeholders = (value: string) => new Set(Array.from(value.matchAll(/\{(\w+)\}/g), (m) => m[1]));
const keys = Object.keys(LOCALES.en) as TranslationKey[];

test('every supported language has a dictionary', () => {
  for (const lang of LANGUAGES) {
    assert.ok(LOCALES[lang], `missing dictionary for ${lang}`);
    assert.equal(Object.keys(LOCALES[lang]).length, keys.length, `${lang} key count differs from en`);
  }
});

test('every translation keeps the placeholders of English and is non-empty', () => {
  const problems: string[] = [];
  for (const lang of LANGUAGES) {
    for (const key of keys) {
      const value = LOCALES[lang][key];
      if (!value || !value.trim()) problems.push(`${lang}.${key}: empty`);
      const expected = [...placeholders(LOCALES.en[key])].sort().join(',');
      const actual = [...placeholders(value ?? '')].sort().join(',');
      if (expected !== actual) problems.push(`${lang}.${key}: {${actual}} != {${expected}}`);
    }
  }
  assert.deepEqual(problems, []);
});

test('translate substitutes arguments in every language', () => {
  for (const lang of LANGUAGES) {
    assert.match(translate(lang, 'ai_grounded', { count: 3 }), /3/);
    assert.doesNotMatch(translate(lang, 'ai_grounded', { count: 3 }), /\{count\}/);
  }
});

test('untrusted language values resolve to a supported language', () => {
  assert.equal(resolveLanguage('fr'), 'fr');
  assert.equal(resolveLanguage('xx'), 'en');
  assert.equal(resolveLanguage(undefined), 'en');
});

test('components do not hard-code per-language text', () => {
  const offenders: string[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) {
        if (name !== '__tests__' && name !== 'locales') walk(path);
      } else if (/\.tsx?$/.test(name) && !path.endsWith(join('lib', 'i18n.ts'))) {
        if (/\b(lang|language)\s*===\s*'(tr|de|en|es|fr|it)'\s*\?/.test(readFileSync(path, 'utf-8'))) offenders.push(path);
      }
    }
  };
  walk(join(__dirname, '..'));
  assert.deepEqual(offenders, [], 'use t(...) instead of inline language ternaries');
});
