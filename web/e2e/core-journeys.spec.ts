import { expect, test, type Page } from '@playwright/test';

/** Fails the test on any console error or uncaught exception (e.g. hydration mismatches). */
function trackErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });
  page.on('pageerror', (e) => errors.push(e.message));
  return errors;
}

async function useLanguage(page: Page, lang: string) {
  await page.context().addCookies([{ name: 'libris_lang', value: lang, url: 'http://127.0.0.1:3055' }]);
  await page.addInitScript((l) => {
    try {
      localStorage.setItem('libris_preferences', JSON.stringify({ language: l }));
    } catch {}
  }, lang);
}

test('home states the product promise and links to the catalog', async ({ page }) => {
  const errors = trackErrors(page);
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Remember it for good');
  await page.getByRole('link', { name: /browse catalog/i }).first().click();
  await expect(page).toHaveURL(/\/catalog/);
  expect(errors).toEqual([]);
});

test('switching category replaces the book list (no stale results)', async ({ page }) => {
  await page.goto('/catalog?category=Technology');
  const techTitles = await page.locator('.grid-books h3, .grid-books [data-testid="book-title"]').allInnerTexts();
  await page.goto('/catalog?category=Fantasy');
  const fantasyTitles = await page.locator('.grid-books h3, .grid-books [data-testid="book-title"]').allInnerTexts();
  expect(techTitles.length).toBeGreaterThan(0);
  expect(fantasyTitles.length).toBeGreaterThan(0);
  expect(fantasyTitles.slice(0, 5)).not.toEqual(techTitles.slice(0, 5));
});

test('search ranks title matches first', async ({ page }) => {
  await page.goto('/catalog?q=habits');
  const first = page.locator('.grid-books h3, .grid-books [data-testid="book-title"]').first();
  await expect(first).toContainText(/habits/i);
});

test('book detail shows clean years and localized numbers', async ({ page }) => {
  await useLanguage(page, 'tr');
  await page.goto('/catalog?category=Fantasy');
  await page.locator('.grid-books a[href^="/book/"]').first().click();
  await expect(page).toHaveURL(/\/book\//);
  await expect(page.getByText('Kataloğa dön')).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/\b\d{4}\.0\b/);
});

for (const lang of ['tr', 'de', 'es', 'fr', 'it']) {
  test(`pages render in ${lang} without hydration or console errors`, async ({ page }) => {
    const errors = trackErrors(page);
    await useLanguage(page, lang);
    for (const path of ['/', '/catalog?category=Science', '/learning', '/settings', '/login']) {
      await page.goto(path, { waitUntil: 'networkidle' });
    }
    await expect(page.locator('html')).toHaveAttribute('lang', lang);
    expect(errors).toEqual([]);
  });
}

test('review page explains itself to signed-out visitors', async ({ page }) => {
  await page.goto('/learning');
  await expect(page.getByRole('heading', { name: 'Review what you read' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Log in' }).last()).toHaveAttribute('href', /\/login\?redirect=\/learning/);
});

test('no page is wider than the screen', async ({ page }) => {
  for (const path of ['/', '/catalog', '/learning', '/settings', '/login', '/signup']) {
    await page.goto(path, { waitUntil: 'networkidle' });
    const { client, scroll } = await page.evaluate(() => ({
      client: document.documentElement.clientWidth,
      scroll: document.documentElement.scrollWidth,
    }));
    expect(scroll, `horizontal overflow on ${path}`).toBeLessThanOrEqual(client);
  }
});

test('phones get a bottom tab bar with the review tab', async ({ page, isMobile }) => {
  test.skip(!isMobile, 'phone layout only');
  await page.goto('/');
  const bar = page.locator('.nav-primary');
  await expect(bar).toBeVisible();
  const box = await bar.boundingBox();
  const viewport = page.viewportSize()!;
  expect(box!.y + box!.height).toBeGreaterThan(viewport.height - 4);
  await bar.getByRole('link', { name: 'Review' }).click();
  await expect(page).toHaveURL(/\/learning/);
});
