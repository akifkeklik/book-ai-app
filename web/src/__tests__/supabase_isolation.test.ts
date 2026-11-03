import test from 'node:test';
import assert from 'node:assert/strict';
import {
  isRemoteSupabaseUrl,
  isLocalEnvironment,
  assertSafeSupabaseTarget,
  SupabaseIsolationError,
} from '../lib/supabase/isolation';
import { createClient } from '../lib/supabase/server';

test('Supabase Isolation: isRemoteSupabaseUrl classifies domains deterministically', () => {
  // Safe mock or local loopback patterns
  assert.equal(isRemoteSupabaseUrl('https://mock.supabase.co'), false);
  assert.equal(isRemoteSupabaseUrl('http://localhost:54321'), false);
  assert.equal(isRemoteSupabaseUrl('http://127.0.0.1:54321'), false);
  assert.equal(isRemoteSupabaseUrl('http://[::1]:54321'), false);
  assert.equal(isRemoteSupabaseUrl('mock_anon_key'), false);
  assert.equal(isRemoteSupabaseUrl(null), false);
  assert.equal(isRemoteSupabaseUrl(''), false);

  // Dangerous live remote Supabase cloud projects
  assert.equal(isRemoteSupabaseUrl('https://vnedgshbefpctjyzpqlm.supabase.co'), true);
  assert.equal(isRemoteSupabaseUrl('https://xyzcompany.supabase.co'), true);
  assert.equal(isRemoteSupabaseUrl('https://prod-db.example.com'), true);
});

test('Supabase Isolation: isLocalEnvironment detects test, dev, and compose hosts', () => {
  // In node:test runner, NODE_ENV is test or LIBRIS_SUPABASE_ISOLATION is set
  assert.equal(isLocalEnvironment(), true);
});

test('Supabase Isolation: assertSafeSupabaseTarget throws SupabaseIsolationError for remote endpoints in local mode', () => {
  // In test environment, pointing to remote Supabase must throw fail-closed
  assert.throws(
    () => {
      assertSafeSupabaseTarget('https://vnedgshbefpctjyzpqlm.supabase.co', 'table query: favorites');
    },
    (err: unknown) => {
      assert.ok(err instanceof SupabaseIsolationError);
      assert.ok(err.message.includes('Fail-closed: Remote Supabase table query: favorites is prohibited'));
      // Guarantees zero credential or URL leakage in error string
      assert.ok(!err.message.includes('vnedgshbefpctjyzpqlm'));
      assert.ok(err.message.includes('[REDACTED_REMOTE_SUPABASE_URL]'));
      return true;
    }
  );

  // Safe mock or local targets do not throw
  assert.doesNotThrow(() => {
    assertSafeSupabaseTarget('https://mock.supabase.co', 'table query: favorites');
  });
  assert.doesNotThrow(() => {
    assertSafeSupabaseTarget('http://localhost:54321', 'table query: favorites');
  });
});

test('Supabase Isolation: createClient().from() fails closed when targeting remote Supabase in local mode', async () => {
  const originalUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const originalKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  try {
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://vnedgshbefpctjyzpqlm.supabase.co';
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'mock-anon-key-for-test';
    const client = await createClient();

    assert.throws(
      () => {
        client.from('favorites');
      },
      (err: unknown) => {
        assert.ok(err instanceof SupabaseIsolationError);
        assert.ok(err.message.includes('Fail-closed: Remote Supabase table query: favorites is prohibited'));
        return true;
      }
    );
  } finally {
    process.env.NEXT_PUBLIC_SUPABASE_URL = originalUrl;
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = originalKey;
  }
});
