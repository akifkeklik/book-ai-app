import test from 'node:test';
import assert from 'node:assert/strict';
import { NextRequest } from 'next/server';
import { updateSession } from '../lib/supabase/middleware';

// Provide WebSocket mock if running on Node < 22 where native WebSocket is absent
if (typeof (globalThis as Record<string, unknown>).WebSocket === 'undefined') {
  (globalThis as Record<string, unknown>).WebSocket = class MockWebSocket {};
}

test('updateSession: safely passes through when Supabase env vars are missing', async () => {
  const originalUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const originalKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  delete process.env.NEXT_PUBLIC_SUPABASE_URL;
  delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  try {
    const req = new NextRequest('http://localhost:3000/catalog');
    const res = await updateSession(req);
    assert.equal(res.status, 200);
  } finally {
    if (originalUrl) process.env.NEXT_PUBLIC_SUPABASE_URL = originalUrl;
    if (originalKey) process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = originalKey;
  }
});

test('updateSession: unauthenticated access to /favorites redirects to /login?redirect=/favorites', async () => {
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'fake-anon-key';

  const req = new NextRequest('http://localhost:3000/favorites');
  const res = await updateSession(req);

  assert.equal(res.status, 307);
  const location = res.headers.get('location');
  assert.ok(location?.includes('/login'));
  assert.ok(location?.includes('redirect=%2Ffavorites') || location?.includes('redirect=/favorites'));
});

test('updateSession: allows public access to catalog without redirect', async () => {
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'fake-anon-key';

  const req = new NextRequest('http://localhost:3000/catalog');
  const res = await updateSession(req);

  // Should NOT redirect to /login
  assert.notEqual(res.status, 307);
  assert.equal(res.headers.get('location'), null);
});

test('updateSession: allows public access to AI discovery without redirect', async () => {
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'fake-anon-key';

  const req = new NextRequest('http://localhost:3000/ai-discovery');
  const res = await updateSession(req);

  assert.notEqual(res.status, 307);
  assert.equal(res.headers.get('location'), null);
});

test('updateSession: allows public access to root page without redirect', async () => {
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'fake-anon-key';

  const req = new NextRequest('http://localhost:3000/');
  const res = await updateSession(req);

  assert.notEqual(res.status, 307);
  assert.equal(res.headers.get('location'), null);
});

test('updateSession: preserves cookies on redirect response during unauthenticated /favorites redirect', async () => {
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://fake-project.supabase.co';
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'fake-anon-key';

  const req = new NextRequest('http://localhost:3000/favorites', {
    headers: {
      cookie: 'sb-test-auth-token=some_token; path=/',
    },
  });

  const res = await updateSession(req);
  assert.equal(res.status, 307);
  assert.ok(res.headers.get('location')?.includes('/login'));
});

