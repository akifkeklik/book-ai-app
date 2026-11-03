import { test } from 'node:test';
import assert from 'node:assert/strict';
import nextConfig from '../../next.config';
import { ApiService } from '../lib/api';

test('CDN Cache & Security: next.config.ts header directives enforce strict isolation', async () => {
  assert.ok(typeof nextConfig.headers === 'function', 'nextConfig must export async headers() function');

  const headersRules = await nextConfig.headers();
  assert.ok(Array.isArray(headersRules), 'headers() must return an array of route header configurations');

  // Helper to find rule by source
  const findRule = (src: string) => headersRules.find((r: { source: string }) => r.source === src);

  // 1. Universal Security Headers
  const globalRule = findRule('/:path*');
  assert.ok(globalRule, 'Universal security rule /:path* must exist');
  const globalHeaderMap = Object.fromEntries(globalRule.headers.map((h: { key: string; value: string }) => [h.key, h.value]));
  assert.equal(globalHeaderMap['X-Content-Type-Options'], 'nosniff');
  assert.equal(globalHeaderMap['X-Frame-Options'], 'DENY');
  assert.equal(globalHeaderMap['Referrer-Policy'], 'strict-origin-when-cross-origin');

  // 2. Public Taxonomy: bounded TTL with stale-while-revalidate for CDN
  const catRule = findRule('/api/categories');
  assert.ok(catRule, 'Public categories route rule must exist');
  const catHeaders = Object.fromEntries(catRule.headers.map((h: { key: string; value: string }) => [h.key, h.value]));
  assert.ok(catHeaders['Cache-Control'].includes('public'));
  assert.ok(catHeaders['Cache-Control'].includes('s-maxage=3600'));
  assert.ok(catHeaders['Cache-Control'].includes('stale-while-revalidate'));

  // 3. Public Catalog: bounded TTL for CDN
  const booksRule = findRule('/api/books');
  assert.ok(booksRule, 'Public catalog route rule must exist');
  const booksHeaders = Object.fromEntries(booksRule.headers.map((h: { key: string; value: string }) => [h.key, h.value]));
  assert.ok(booksHeaders['Cache-Control'].includes('public'));
  assert.ok(booksHeaders['Cache-Control'].includes('s-maxage=300'));

  // 4. Personalized Endpoints: MUST be private, no-cache, no-store
  const personalizedRule = findRule('/api/recommend/personalized');
  assert.ok(personalizedRule, 'Personalized route rule must exist');
  const personalizedHeaders = Object.fromEntries(personalizedRule.headers.map((h: { key: string; value: string }) => [h.key, h.value]));
  assert.ok(personalizedHeaders['Cache-Control'].includes('no-store'));
  assert.ok(personalizedHeaders['Cache-Control'].includes('private'));

  // 5. Mutation Endpoints: MUST be private, no-store
  const feedbackRule = findRule('/api/feedback');
  assert.ok(feedbackRule, 'Feedback mutation route rule must exist');
  const feedbackHeaders = Object.fromEntries(feedbackRule.headers.map((h: { key: string; value: string }) => [h.key, h.value]));
  assert.ok(feedbackHeaders['Cache-Control'].includes('no-store'));

  const trackRule = findRule('/api/track');
  assert.ok(trackRule, 'Track mutation route rule must exist');
  const trackHeaders = Object.fromEntries(trackRule.headers.map((h: { key: string; value: string }) => [h.key, h.value]));
  assert.ok(trackHeaders['Cache-Control'].includes('no-store'));

  // 6. Generative AI Chat: MUST be private, no-store
  const aiChatRule = findRule('/api/ai/chat');
  assert.ok(aiChatRule, 'AI Chat route rule must exist');
  const aiChatHeaders = Object.fromEntries(aiChatRule.headers.map((h: { key: string; value: string }) => [h.key, h.value]));
  assert.ok(aiChatHeaders['Cache-Control'].includes('no-store'));

  // 7. Preferences & Onboarding: MUST be private, no-store
  const prefRule = findRule('/api/preferences');
  assert.ok(prefRule, 'Preferences route rule must exist');
  const prefHeaders = Object.fromEntries(prefRule.headers.map((h: { key: string; value: string }) => [h.key, h.value]));
  assert.ok(prefHeaders['Cache-Control'].includes('no-store'));
  assert.ok(prefHeaders['Cache-Control'].includes('private'));

  const onboardingRule = findRule('/api/onboarding');
  assert.ok(onboardingRule, 'Onboarding route rule must exist');
  const onboardingHeaders = Object.fromEntries(onboardingRule.headers.map((h: { key: string; value: string }) => [h.key, h.value]));
  assert.ok(onboardingHeaders['Cache-Control'].includes('no-store'));
  assert.ok(onboardingHeaders['Cache-Control'].includes('private'));
});

test('CDN Cache Security: Preferences API methods strictly specify cache: "no-store"', async () => {
  const originalFetch = global.fetch;
  const capturedInits: RequestInit[] = [];

  global.fetch = (async (_input: RequestInfo | URL, init?: RequestInit) => {
    if (init) capturedInits.push(init);
    return new Response(JSON.stringify({ status: 'success', preferred_genres: ['Sci-Fi'] }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }) as typeof fetch;

  try {
    await ApiService.getUserPreferences();
    await ApiService.updateUserPreferences(['Sci-Fi']);

    assert.equal(capturedInits.length, 2);
    assert.equal(capturedInits[0].cache, 'no-store', 'getUserPreferences MUST use cache: "no-store"');
    assert.equal(capturedInits[1].cache, 'no-store', 'updateUserPreferences MUST use cache: "no-store"');
  } finally {
    global.fetch = originalFetch;
  }
});

test('CDN Cache Security: Public API calls do not attach session cookies or authorization headers', async () => {
  const publicHeaders = await ApiService.getHeaders(true);

  assert.equal(publicHeaders['Authorization'], undefined, 'Public calls must NEVER attach Authorization header');
  assert.equal(publicHeaders['Cookie'], undefined, 'Public calls must NEVER attach Cookie header');
  assert.equal(publicHeaders['Content-Type'], 'application/json');
});

test('CDN Cache Security: Distinct query parameters generate distinct URLs preventing cache collision', async () => {
  const originalFetch = global.fetch;
  const capturedUrls: string[] = [];

  global.fetch = (async (input: RequestInfo | URL) => {
    capturedUrls.push(input.toString());
    return new Response(JSON.stringify({ books: [], total: 0, total_pages: 1 }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }) as typeof fetch;

  try {
    // Request page 1 with Fiction
    await ApiService.getBooks({ page: 1, category: 'Fiction', sort: 'rating' });
    // Request page 2 with Fiction
    await ApiService.getBooks({ page: 2, category: 'Fiction', sort: 'rating' });
    // Request Science
    await ApiService.getBooks({ page: 1, category: 'Science', sort: 'rating' });
    // Request Search query
    await ApiService.getBooks({ query: 'asimov', sort: 'title' });

    assert.equal(capturedUrls.length, 4);
    // Every query URL must be distinct
    const uniqueUrls = new Set(capturedUrls);
    assert.equal(uniqueUrls.size, 4, 'All filter/query combinations must have unique URLs to prevent cache collisions');
    assert.ok(capturedUrls[0].includes('page=1&category=Fiction&sort=rating'));
    assert.ok(capturedUrls[1].includes('page=2&category=Fiction&sort=rating'));
    assert.ok(capturedUrls[2].includes('page=1&category=Science&sort=rating'));
    assert.ok(capturedUrls[3].includes('q=asimov&sort=title'));
  } finally {
    global.fetch = originalFetch;
  }
});

test('CDN Cache Security: Personalized recommendations strictly use cache: "no-store"', async () => {
  const originalFetch = global.fetch;
  let capturedInit: RequestInit | undefined;

  global.fetch = (async (_input: RequestInfo | URL, init?: RequestInit) => {
    capturedInit = init;
    return new Response(JSON.stringify({ recommendations: [] }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }) as typeof fetch;

  try {
    await ApiService.getPersonalizedRecommendations(5);
    assert.ok(capturedInit, 'Fetch should have been invoked with options');
    assert.equal(capturedInit.cache, 'no-store', 'Personalized recommendations MUST specify cache: "no-store"');
  } finally {
    global.fetch = originalFetch;
  }
});

test('PWA & Service Worker Security: sw.js strictly refuses to cache private, auth, or generative routes', async () => {
  const fs = await import('node:fs');
  const path = await import('node:path');
  const swPath = path.resolve(__dirname, '../../public/sw.js');
  assert.ok(fs.existsSync(swPath), 'public/sw.js must exist');

  const swContent = fs.readFileSync(swPath, 'utf-8');

  // Verify private route guard
  assert.ok(swContent.includes('isPrivateOrDynamicRoute'), 'sw.js must define isPrivateOrDynamicRoute guard');
  assert.ok(swContent.includes("path.startsWith('/api/feedback')"), 'sw.js must block /api/feedback');
  assert.ok(swContent.includes("path.startsWith('/api/track')"), 'sw.js must block /api/track');
  assert.ok(swContent.includes("path.startsWith('/api/preferences')"), 'sw.js must block /api/preferences');
  assert.ok(swContent.includes("path.startsWith('/api/onboarding')"), 'sw.js must block /api/onboarding');
  assert.ok(swContent.includes("path.startsWith('/api/recommend/personalized')"), 'sw.js must block /api/recommend/personalized');
  assert.ok(swContent.includes("path.startsWith('/api/ai/')"), 'sw.js must block /api/ai/ streaming and chat');
  assert.ok(swContent.includes("path.startsWith('/favorites')"), 'sw.js must block /favorites');
  assert.ok(swContent.includes("path.startsWith('/settings')"), 'sw.js must block /settings');

  // Verify cache purge on logout
  assert.ok(swContent.includes("event.data.type === 'LOGOUT'"), 'sw.js must listen for LOGOUT message to purge caches');
  assert.ok(swContent.includes('caches.delete(name)'), 'sw.js must delete all cache names on LOGOUT');

  // Verify manifest exists and is valid
  const manifestPath = path.resolve(__dirname, '../../public/manifest.json');
  assert.ok(fs.existsSync(manifestPath), 'public/manifest.json must exist');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
  assert.ok(manifest.name && manifest.name.includes('Libris'), 'Manifest must define name');
  assert.equal(manifest.start_url, '/', 'Manifest start_url must be /');
  assert.ok(manifest.icons && manifest.icons.length > 0, 'Manifest must specify at least one icon');
});
