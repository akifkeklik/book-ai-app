import { test, expect } from '@playwright/test';

/**
 * AI chat against the hermetic stack: the backend runs with no LLM key and no Supabase, so
 * these checks prove the UI reports what really happened instead of implying a Gemini answer.
 */
test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    if (!sessionStorage.getItem('__seeded')) {
      localStorage.setItem('libris_user_preferences', JSON.stringify({ themeMode: 'light', colorPalette: 'ocean_mist', language: 'en' }));
      sessionStorage.setItem('__seeded', '1');
    }
  });
  await page.goto('/ai-discovery', { waitUntil: 'networkidle' });
});

test('preset question 1 runs the real catalog lookup and is labelled as a catalog answer', async ({ page }) => {
  await page.locator('.ai-suggestion', { hasText: 'Do you have the book 1984?' }).click();
  const source = page.getByTestId('ai-answer-source').last();
  await expect(source).toBeVisible({ timeout: 20_000 });
  // Deterministic catalog hit; a repeat of the same question is served (and labelled) from cache.
  await expect(source).toHaveAttribute('data-source', /^(catalog|cache)$/);
  await expect(page.getByTestId('referenced-books-section')).toBeVisible();
  await expect(page.locator('.ai-sources a').first()).toContainText('1984');
});

test('without an LLM key, an open question is labelled as a fallback, never as Gemini', async ({ page }) => {
  await page.locator('.ai-suggestion', { hasText: 'Books like Dune' }).click();
  const source = page.getByTestId('ai-answer-source').last();
  await expect(source).toBeVisible({ timeout: 30_000 });
  await expect(source).not.toHaveAttribute('data-source', 'gemini');
});

test('the dark-mode preset executes the real action and switches the theme', async ({ page }) => {
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await page.locator('.ai-suggestion', { hasText: 'Switch to dark mode' }).click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark', { timeout: 20_000 });
  await expect(page.getByTestId('ai-answer-source').last()).toHaveAttribute('data-source', 'action');
  await expect(page.locator('.ai-action-badge')).toBeVisible();
});

test('typed questions send on Enter, and conversations are kept in recent chats after reload', async ({ page }) => {
  const input = page.locator('#ai-discovery-query-input');
  await input.fill('Do you have the book 1984?');
  await input.press('Enter');
  await expect(page.getByTestId('ai-answer-source').last()).toBeVisible({ timeout: 20_000 });

  await page.reload({ waitUntil: 'networkidle' });
  const recent = page.getByTestId('ai-recent-chats');
  await expect(recent).toContainText('Do you have the book 1984?');

  await recent.locator('.ai-side-item', { hasText: 'Do you have the book 1984?' }).click();
  await expect(page.locator('.ai-bubble-user')).toContainText('Do you have the book 1984?');
  await expect(page.locator('.ai-bubble-ai').first()).not.toBeEmpty();

  await page.getByRole('button', { name: /Delete chat: Do you have the book 1984\?/ }).click();
  await expect(page.getByTestId('ai-recent-chats')).toHaveCount(0);
});

test('signed out, recent activity asks to sign in instead of showing invented items', async ({ page }) => {
  await expect(page.getByRole('link', { name: /Sign in to see your recent library/ })).toBeVisible();
  await expect(page.getByTestId('ai-recent-activity')).toHaveCount(0);
});

test('a backend failure is shown as an error with retry, not as an answer', async ({ page }) => {
  await page.route('**/api/ai/chat/stream', (route) => route.fulfill({ status: 503, contentType: 'application/json', body: '{"error":"down"}' }));
  await page.locator('.ai-suggestion', { hasText: 'Books like Dune' }).click();
  await expect(page.locator('.ai-msg[role="alert"]')).toContainText("The assistant couldn't answer");
  await expect(page.getByRole('button', { name: 'Retry' })).toBeVisible();
  await expect(page.getByTestId('ai-answer-source')).toHaveCount(0);
});
