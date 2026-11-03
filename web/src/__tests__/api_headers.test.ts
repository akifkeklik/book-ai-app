import test from 'node:test';
import assert from 'node:assert/strict';
import { ApiService } from '../lib/api';
import { setTestClient } from '../lib/supabase/server';

test('ApiService.getHeaders: omits X-Api-Key when LIBRIS_API_KEY is missing/undefined', async () => {
  const originalKey = process.env.LIBRIS_API_KEY;
  delete process.env.LIBRIS_API_KEY;

  try {
    const headers = await ApiService.getHeaders();
    assert.equal(headers['Content-Type'], 'application/json');
    assert.equal(headers['X-Api-Key'], undefined);
    assert.equal('X-Api-Key' in headers, false);
  } finally {
    if (originalKey !== undefined) {
      process.env.LIBRIS_API_KEY = originalKey;
    } else {
      delete process.env.LIBRIS_API_KEY;
    }
  }
});

test('ApiService.getHeaders: omits X-Api-Key when LIBRIS_API_KEY is an empty string', async () => {
  const originalKey = process.env.LIBRIS_API_KEY;
  process.env.LIBRIS_API_KEY = '';

  try {
    const headers = await ApiService.getHeaders();
    assert.equal(headers['Content-Type'], 'application/json');
    assert.equal(headers['X-Api-Key'], undefined);
    assert.equal('X-Api-Key' in headers, false);
  } finally {
    if (originalKey !== undefined) {
      process.env.LIBRIS_API_KEY = originalKey;
    } else {
      delete process.env.LIBRIS_API_KEY;
    }
  }
});

test('ApiService.getHeaders: omits X-Api-Key when LIBRIS_API_KEY contains only whitespace', async () => {
  const originalKey = process.env.LIBRIS_API_KEY;
  process.env.LIBRIS_API_KEY = '   \t  \n  ';

  try {
    const headers = await ApiService.getHeaders();
    assert.equal(headers['Content-Type'], 'application/json');
    assert.equal(headers['X-Api-Key'], undefined);
    assert.equal('X-Api-Key' in headers, false);
  } finally {
    if (originalKey !== undefined) {
      process.env.LIBRIS_API_KEY = originalKey;
    } else {
      delete process.env.LIBRIS_API_KEY;
    }
  }
});

test('ApiService.getHeaders: populates X-Api-Key when a valid API key is present', async () => {
  const originalKey = process.env.LIBRIS_API_KEY;
  process.env.LIBRIS_API_KEY = 'valid-libris-secret-key';

  try {
    const headers = await ApiService.getHeaders();
    assert.equal(headers['Content-Type'], 'application/json');
    assert.equal(headers['X-Api-Key'], 'valid-libris-secret-key');
  } finally {
    if (originalKey !== undefined) {
      process.env.LIBRIS_API_KEY = originalKey;
    } else {
      delete process.env.LIBRIS_API_KEY;
    }
  }
});

test('ApiService.getHeaders: trims whitespace from valid API key', async () => {
  const originalKey = process.env.LIBRIS_API_KEY;
  process.env.LIBRIS_API_KEY = '  trimmed-secret-key  ';

  try {
    const headers = await ApiService.getHeaders();
    assert.equal(headers['X-Api-Key'], 'trimmed-secret-key');
  } finally {
    if (originalKey !== undefined) {
      process.env.LIBRIS_API_KEY = originalKey;
    } else {
      delete process.env.LIBRIS_API_KEY;
    }
  }
});

test('ApiService.getHeaders: forwards Bearer token when Supabase session is active', async () => {
  const mockToken = 'mocked.jwt.token-xyz';
  const fakeSupabase = {
    auth: {
      getSession: async () => ({
        data: {
          session: {
            access_token: mockToken,
          },
        },
      }),
    },
  };

  setTestClient(fakeSupabase);
  try {
    const headers = await ApiService.getHeaders();
    assert.equal(headers['Authorization'], `Bearer ${mockToken}`);
    assert.equal(headers['Content-Type'], 'application/json');
  } finally {
    setTestClient(null);
  }
});

test('ApiService.getHeaders: omits Authorization header when Supabase session is absent', async () => {
  const fakeSupabase = {
    auth: {
      getSession: async () => ({
        data: {
          session: null,
        },
      }),
    },
  };

  setTestClient(fakeSupabase);
  try {
    const headers = await ApiService.getHeaders();
    assert.equal(headers['Authorization'], undefined);
    assert.equal('Authorization' in headers, false);
  } finally {
    setTestClient(null);
  }
});

test('ApiService fetch integration: outbound requests never send empty X-Api-Key to Flask', async () => {
  const originalKey = process.env.LIBRIS_API_KEY;
  const originalFetch = globalThis.fetch;
  delete process.env.LIBRIS_API_KEY;

  let capturedHeaders: Record<string, string> = {};

  try {
    globalThis.fetch = async (_url: string | URL | Request, init?: RequestInit) => {
      capturedHeaders = (init?.headers as Record<string, string>) || {};
      return new Response(JSON.stringify({ categories: ['Fiction'] }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    };

    const categories = await ApiService.getCategories();
    assert.deepEqual(categories, ['Fiction']);
    assert.equal(capturedHeaders['Content-Type'], 'application/json');
    assert.equal('X-Api-Key' in capturedHeaders, false);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey !== undefined) {
      process.env.LIBRIS_API_KEY = originalKey;
    } else {
      delete process.env.LIBRIS_API_KEY;
    }
  }
});
