// Libris PWA Service Worker — Strict Static-Only Caching
const STATIC_CACHE_NAME = 'libris-static-v1';

// Static assets allowlist — NEVER include personalized or authenticated endpoints
const PRECACHE_ASSETS = [
  '/',
  '/manifest.json',
  '/favicon.ico',
];

// Security guard: paths that must NEVER be cached by service worker
function isPrivateOrDynamicRoute(url) {
  const path = url.pathname;
  return (
    path.startsWith('/api/feedback') ||
    path.startsWith('/api/track') ||
    path.startsWith('/api/preferences') ||
    path.startsWith('/api/onboarding') ||
    path.startsWith('/api/recommend/personalized') ||
    path.startsWith('/api/ai/') ||
    path.startsWith('/favorites') ||
    path.startsWith('/settings')
  );
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(STATIC_CACHE_NAME).then((cache) => {
      return cache.addAll(PRECACHE_ASSETS);
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((name) => name !== STATIC_CACHE_NAME)
          .map((name) => caches.delete(name))
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);

  // 1. Only handle GET requests
  if (request.method !== 'GET') {
    return;
  }

  // 2. Reject private or authenticated routes from SW cache completely
  if (isPrivateOrDynamicRoute(url)) {
    return;
  }

  // 3. For navigation requests: Network first with cached static shell fallback
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).catch(async () => {
        const cache = await caches.open(STATIC_CACHE_NAME);
        const cachedHome = await cache.match('/');
        return cachedHome || new Response('Offline - please check your internet connection.', {
          status: 503,
          headers: { 'Content-Type': 'text/plain' },
        });
      })
    );
    return;
  }

  // 4. For static assets (CSS, JS, Fonts, Images): Stale-While-Revalidate
  if (
    url.pathname.startsWith('/_next/static/') ||
    url.pathname.match(/\.(css|js|woff2?|svg|png|jpg|ico)$/)
  ) {
    event.respondWith(
      caches.match(request).then((cachedResponse) => {
        const fetchPromise = fetch(request).then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            const responseToCache = networkResponse.clone();
            caches.open(STATIC_CACHE_NAME).then((cache) => {
              cache.put(request, responseToCache);
            });
          }
          return networkResponse;
        }).catch(() => cachedResponse);

        return cachedResponse || fetchPromise;
      })
    );
  }
});

// Purge cache when user logs out
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'LOGOUT') {
    caches.keys().then((names) => {
      names.forEach((name) => caches.delete(name));
    });
  }
});
