import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { THEME_IDS, THEME_SWATCHES, LEGACY_THEME_MAP, normalizeThemeId, DEFAULT_THEME } from '../lib/themes';

const css = readFileSync(join(__dirname, '..', 'app', 'themes.css'), 'utf8');
const REQUIRED = [
  'background', 'canvas-deep', 'surface', 'surface-elevated', 'surface-subtle',
  'text-primary', 'text-secondary', 'text-muted', 'primary', 'primary-hover', 'accent', 'on-primary',
];

function block(theme: string, mode: 'light' | 'dark'): Record<string, string> {
  const re = new RegExp(`html\\[data-theme="${mode}"\\]\\[data-palette="${theme}"\\]\\s*\\{([^}]*)\\}`);
  const m = css.match(re);
  assert.ok(m, `themes.css has no block for ${theme} / ${mode}`);
  return Object.fromEntries([...m[1].matchAll(/--([\w-]+):\s*(#[0-9a-f]{6})/gi)].map((x) => [x[1], x[2].toLowerCase()]));
}

function luminance(hex: string): number {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

test('there are exactly 10 themes and every one defines both a light and a dark variant (20 blocks)', () => {
  assert.equal(THEME_IDS.length, 10);
  let blocks = 0;
  for (const id of THEME_IDS) {
    for (const mode of ['light', 'dark'] as const) {
      const vars = block(id, mode);
      for (const key of REQUIRED) assert.ok(vars[key], `${id}/${mode} is missing --${key}`);
      blocks++;
    }
  }
  assert.equal(blocks, 20);
});

test('dark variants are real dark palettes, not inverted light ones', () => {
  for (const id of THEME_IDS) {
    const light = block(id, 'light');
    const dark = block(id, 'dark');
    assert.ok(luminance(dark.background) < 0.02, `${id} dark background is too bright`);
    assert.ok(luminance(light.background) > 0.85, `${id} light background is too dark`);
    assert.notEqual(light.primary, dark.primary, `${id} reuses the light accent in dark mode`);
  }
});

test('all 20 combinations meet WCAG AA (4.5:1) for body, muted text and text on the primary colour', () => {
  const failures: string[] = [];
  for (const id of THEME_IDS) {
    for (const mode of ['light', 'dark'] as const) {
      const v = block(id, mode);
      const checks: Array<[string, string, string]> = [
        ['text-primary', v['text-primary'], v.background],
        ['text-secondary', v['text-secondary'], v.surface],
        ['text-muted/bg', v['text-muted'], v.background],
        ['text-muted/subtle', v['text-muted'], v['surface-subtle']],
        ['on-primary', v['on-primary'], v.primary],
        ['on-primary/hover', v['on-primary'], v['primary-hover']],
        ['primary/bg', v.primary, v.background],
      ];
      for (const [name, fg, bg] of checks) {
        const ratio = contrast(fg, bg);
        if (ratio < 4.5) failures.push(`${id}/${mode} ${name}: ${ratio.toFixed(2)}`);
      }
    }
  }
  assert.deepEqual(failures, []);
});

/** sRGB hex -> OKLab (Björn Ottosson), the perceptual space the theme generator works in. */
function oklab(hex: string): [number, number, number] {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}

test('no two themes look alike: primary colours are perceptually distinct in both modes', () => {
  // The retired set had Ocean Mist and Arctic Sky 0.024 apart (practically the same blue).
  const MIN_DISTANCE = 0.06;
  const close: string[] = [];
  for (const mode of ['light', 'dark'] as const) {
    for (let i = 0; i < THEME_IDS.length; i++) {
      for (let j = i + 1; j < THEME_IDS.length; j++) {
        const [a, b] = [THEME_IDS[i], THEME_IDS[j]].map((id) => oklab(block(id, mode).primary));
        const d = Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
        if (d < MIN_DISTANCE) close.push(`${mode}: ${THEME_IDS[i]} vs ${THEME_IDS[j]} = ${d.toFixed(3)}`);
      }
    }
  }
  assert.deepEqual(close, []);
});

test('picker swatches match the CSS tokens', () => {
  for (const id of THEME_IDS) {
    for (const mode of ['light', 'dark'] as const) {
      const v = block(id, mode);
      const sw = THEME_SWATCHES[id][mode];
      assert.equal(sw.bg, v.background, `${id}/${mode} bg`);
      assert.equal(sw.surface, v.surface, `${id}/${mode} surface`);
      assert.equal(sw.primary, v.primary, `${id}/${mode} primary`);
      assert.equal(sw.accent, v.accent, `${id}/${mode} accent`);
    }
  }
});

test('normalizeThemeId accepts current ids, migrates every legacy id and rejects the rest', () => {
  for (const id of THEME_IDS) assert.equal(normalizeThemeId(id), id);
  for (const [legacy, target] of Object.entries(LEGACY_THEME_MAP)) {
    assert.equal(normalizeThemeId(legacy), target);
    assert.ok((THEME_IDS as readonly string[]).includes(target));
  }
  for (const bad of ['neon', '', null, undefined, 42, 'constructor', '__proto__']) {
    assert.equal(normalizeThemeId(bad), null, String(bad));
  }
  assert.ok((THEME_IDS as readonly string[]).includes(DEFAULT_THEME));
});

test('the pre-paint init script knows the themes and the legacy map (no flash of the wrong theme)', () => {
  const layout = readFileSync(join(__dirname, '..', 'app', 'layout.tsx'), 'utf8');
  assert.match(layout, /JSON\.stringify\(THEME_IDS\)/);
  assert.match(layout, /JSON\.stringify\(LEGACY_THEME_MAP\)/);
  assert.match(layout, /import "\.\/themes\.css"/);
});
