import fs from 'node:fs';
import path from 'node:path';
import { test, expect, type Page } from '@playwright/test';
import { THEME_IDS, THEME_SWATCHES } from '../src/lib/themes';

/**
 * Every theme × appearance mode, checked in a real browser: the pre-paint script applies it,
 * nothing flips it afterwards (no flash), the page uses its colours, text stays readable and
 * nothing scrolls sideways. Set THEME_SHOTS=<dir> to also save a screenshot of each.
 */
const MODES = ['light', 'dark'] as const;
const PAGES = ['/', '/ai-discovery', '/settings', '/catalog', '/book/9780439554930', '/login'];
const SHOTS = process.env.THEME_SHOTS;

function hexToRgb(hex: string): string {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  return `rgb(${r}, ${g}, ${b})`;
}

async function seedPreferences(page: Page, prefs: Record<string, unknown> | null) {
  await page.addInitScript((p) => {
    if (p && !sessionStorage.getItem('__seeded')) {
      localStorage.setItem('libris_user_preferences', JSON.stringify(p));
      sessionStorage.setItem('__seeded', '1');
    }
    // Record every value the theme attributes take, from before the first byte of page script.
    // <html> may not exist yet when this runs, so observe the whole document.
    const w = window as unknown as { __themeHistory: string[] };
    w.__themeHistory = [];
    new MutationObserver((records) => {
      for (const rec of records) {
        if (rec.target !== document.documentElement) continue;
        const el = document.documentElement;
        w.__themeHistory.push(`${el.getAttribute('data-theme')}/${el.getAttribute('data-palette')}`);
      }
    }).observe(document, { attributes: true, subtree: true, attributeFilter: ['data-theme', 'data-palette'] });
  }, prefs);
}

/** Visible text whose colour is too close to the nearest opaque background behind it. */
async function lowContrastText(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    type RGBA = { r: number; g: number; b: number; a: number };
    // Computed colours come back as rgb()/rgba() or, for color-mix(), as color(srgb r g b / a).
    const parse = (c: string): RGBA | null => {
      const srgb = c.match(/color\(srgb ([^)]+)\)/);
      if (srgb) {
        const [r, g, b, a = 1] = srgb[1].split(/[ /]+/).filter(Boolean).map(Number);
        return { r: r * 255, g: g * 255, b: b * 255, a };
      }
      const m = c.match(/rgba?\(([^)]+)\)/);
      if (!m) return null;
      const [r, g, b, a = 1] = m[1].split(/[ ,/]+/).filter(Boolean).map(Number);
      return { r, g, b, a };
    };
    const lum = ({ r, g, b }: RGBA) => {
      const f = (v: number) => ((v /= 255) <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
    };
    const over = (top: RGBA, below: RGBA): RGBA => ({
      r: top.r * top.a + below.r * (1 - top.a),
      g: top.g * top.a + below.g * (1 - top.a),
      b: top.b * top.a + below.b * (1 - top.a),
      a: 1,
    });
    /** Composites every translucent background layer down to the first opaque one. */
    const bgOf = (el: Element | null): RGBA | null => {
      const layers: RGBA[] = [];
      for (let n = el; n; n = n.parentElement) {
        const cs = getComputedStyle(n);
        if (cs.backgroundImage !== 'none') return null; // gradient / cover image: undecidable
        const c = parse(cs.backgroundColor);
        if (c && c.a > 0) layers.push(c);
        if (c && c.a >= 0.99) break;
      }
      const base = parse(getComputedStyle(document.body).backgroundColor)!;
      return layers.reverse().reduce((acc, l) => over(l, acc), { ...base, a: 1 });
    };
    const bad: string[] = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    const seen = new Set<Element>();
    while (walker.nextNode()) {
      const el = walker.currentNode.parentElement;
      if (!el || seen.has(el) || !walker.currentNode.textContent?.trim()) continue;
      seen.add(el);
      const rect = el.getBoundingClientRect();
      const cs = getComputedStyle(el);
      if (!rect.width || !rect.height || cs.visibility === 'hidden' || Number(cs.opacity) < 0.5) continue;
      if (el.closest('.sr-only, [aria-hidden="true"], .skip-link, [disabled]')) continue;
      const fg = parse(cs.color);
      const bg = bgOf(el);
      if (!fg || !bg || fg.a < 0.5) continue;
      const [hi, lo] = [lum(fg.a < 1 ? over(fg, bg) : fg), lum(bg)].sort((a, b) => b - a);
      const ratio = (hi + 0.05) / (lo + 0.05);
      if (ratio < 3) bad.push(`${ratio.toFixed(2)} "${el.textContent!.trim().slice(0, 40)}" <${el.tagName.toLowerCase()}.${el.className}>`);
    }
    return bad;
  });
}

for (const theme of THEME_IDS) {
  for (const mode of MODES) {
    test(`theme ${theme} / ${mode}`, async ({ page, isMobile }) => {
      await seedPreferences(page, { themeMode: mode, colorPalette: theme });
      const expectedBg = hexToRgb(THEME_SWATCHES[theme][mode].bg);

      for (const url of PAGES) {
        await page.goto(url, { waitUntil: 'networkidle' });
        const html = page.locator('html');
        await expect(html).toHaveAttribute('data-theme', mode);
        await expect(html).toHaveAttribute('data-palette', theme);

        // Applied before paint and never flipped by hydration (the flash this guards against).
        const history = await page.evaluate(() => (window as unknown as { __themeHistory: string[] }).__themeHistory);
        expect(new Set(history.filter((h) => !h.startsWith('null'))), `${url} theme history`).toEqual(new Set([`${mode}/${theme}`]));

        await page.waitForTimeout(300); // let the cross-fade settle before reading colours
        expect(await page.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe(expectedBg);

        const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        expect(overflow, `${url} horizontal overflow`).toBeLessThanOrEqual(1);

        expect(await lowContrastText(page), `${url} low-contrast text`).toEqual([]);

        if (SHOTS) {
          const dir = path.join(SHOTS, isMobile ? 'phone' : 'desktop');
          fs.mkdirSync(dir, { recursive: true });
          const name = `${url === '/' ? 'home' : url.slice(1).replace(/\//g, '_')}__${theme}__${mode}.png`;
          await page.screenshot({ path: path.join(dir, name) });
        }
      }
    });
  }
}

test('picking a theme and mode in the UI persists across reloads', async ({ page }) => {
  await seedPreferences(page, { themeMode: 'light', colorPalette: 'ocean_mist' });
  await page.goto('/settings', { waitUntil: 'networkidle' });

  const option = page.locator('[data-theme-option="rose_quartz"]');
  await option.click();
  await expect(option).toHaveAttribute('aria-checked', 'true');
  await expect(page.locator('html')).toHaveAttribute('data-palette', 'rose_quartz');
  await expect(page.locator('[role="radiogroup"] [aria-checked="true"]')).toHaveCount(1);

  await page.locator('#nav-theme-toggle').click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');

  await page.reload({ waitUntil: 'networkidle' });
  await expect(page.locator('html')).toHaveAttribute('data-palette', 'rose_quartz');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await expect(page.locator('[data-theme-option="rose_quartz"]')).toHaveAttribute('aria-checked', 'true');
  const stored = await page.evaluate(() => JSON.parse(localStorage.getItem('libris_user_preferences') || '{}'));
  expect([stored.colorPalette, stored.themeMode]).toEqual(['rose_quartz', 'dark']);

  // Navigating keeps it too.
  await page.goto('/ai-discovery', { waitUntil: 'networkidle' });
  await expect(page.locator('html')).toHaveAttribute('data-palette', 'rose_quartz');
});

test('a palette saved by an earlier release is migrated before first paint', async ({ page }) => {
  await seedPreferences(page, { themeMode: 'dark', colorPalette: 'forest_green' });
  await page.goto('/', { waitUntil: 'networkidle' });
  await expect(page.locator('html')).toHaveAttribute('data-palette', 'mint_breeze');
  const history = await page.evaluate(() => (window as unknown as { __themeHistory: string[] }).__themeHistory);
  expect(new Set(history)).toEqual(new Set(['dark/mint_breeze']));
});

for (const scheme of ['light', 'dark'] as const) {
  test(`first visit follows the system ${scheme} preference without flipping`, async ({ browser }) => {
    const context = await browser.newContext({ colorScheme: scheme });
    const page = await context.newPage();
    await seedPreferences(page, null);
    await page.goto('/', { waitUntil: 'networkidle' });
    await page.waitForTimeout(300);
    await expect(page.locator('html')).toHaveAttribute('data-theme', scheme);
    const history = await page.evaluate(() => (window as unknown as { __themeHistory: string[] }).__themeHistory);
    expect(new Set(history)).toEqual(new Set([`${scheme}/ocean_mist`]));
    await context.close();
  });
}
