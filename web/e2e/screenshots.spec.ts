import path from 'node:path';
import { test } from '@playwright/test';

/**
 * Regenerates the README screenshots. Skipped unless SCREENSHOTS=1:
 *   SCREENSHOTS=1 npx playwright test screenshots
 */
const OUT = path.join(__dirname, '..', '..', 'docs', 'screenshots');

test.skip(!process.env.SCREENSHOTS, 'set SCREENSHOTS=1 to regenerate README screenshots');

test('capture README screenshots', async ({ page, isMobile }, testInfo) => {
  const suffix = isMobile ? 'web-phone' : 'desktop';
  const shots: Array<[string, string]> = isMobile
    ? [['home', '/'], ['review', '/learning'], ['catalog', '/catalog?category=Science']]
    : [['home', '/'], ['catalog', '/catalog?category=Science'], ['book', '/book/9780439554930']];

  for (const [name, url] of shots) {
    await page.goto(url, { waitUntil: 'networkidle' });
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(OUT, `${name}-${suffix}.png`) });
  }
  testInfo.annotations.push({ type: 'output', description: OUT });
});
