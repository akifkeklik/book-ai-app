import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Guard: messages shown to the reader are translated. Server actions return English (sometimes
 * technical) error text; showing it, or an English fallback literal, put English sentences in a
 * Turkish/German/... UI. Error state must be set from a translation key instead.
 */
const SRC = join(__dirname, '..');

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return name === '__tests__' ? [] : files(p);
    return p.endsWith('.tsx') ? [p] : [];
  });
}

const PATTERNS: Array<[string, RegExp]> = [
  ['server error text shown to the user', /set(?:Error|GenreError|ErrorMessage)\(\s*\w+\.error\b/],
  ['English fallback literal in an error message', /set(?:Error|GenreError|ErrorMessage)\([^)]*\|\|\s*['"`][A-Z][a-z]/],
  ['English literal as an error message', /set(?:Error|GenreError|ErrorMessage)\(\s*['"`][A-Z][a-z]+ /],
  ['raw exception message shown to the user', /set(?:Error|GenreError|ErrorMessage)\(\s*err(?:or)? instanceof Error \? err(?:or)?\.message/],
];

test('UI components never show untranslated error text', () => {
  const offenders: string[] = [];
  for (const file of [...files(join(SRC, 'components')), ...files(join(SRC, 'app'))]) {
    const lines = readFileSync(file, 'utf8').split(/\r?\n/);
    lines.forEach((line, i) => {
      for (const [why, re] of PATTERNS) {
        if (re.test(line)) offenders.push(`${file.slice(SRC.length + 1)}:${i + 1} ${why}`);
      }
    });
  }
  assert.deepEqual(offenders, []);
});
