/**
 * Fail-Closed Supabase Isolation Guard.
 * 
 * Guarantees that local development, automated testing, and local Compose
 * environments strictly fail closed instead of directing data queries or
 * mutations to a remote Supabase project.
 *
 * Operational safety:
 * - Never prints secret tokens, keys, or remote project URLs.
 * - Enforces server-side data plane unification through Flask backend.
 */

export class SupabaseIsolationError extends Error {
  readonly isIsolationViolation = true;
  constructor(message: string) {
    super(message);
    this.name = 'SupabaseIsolationError';
  }
}

/**
 * Checks if a given Supabase URL points to a remote Supabase cloud project.
 */
export function isRemoteSupabaseUrl(url?: string | null): boolean {
  if (!url || typeof url !== 'string') return false;
  const trimmed = url.trim().toLowerCase();
  if (
    trimmed.includes('mock.supabase.co') ||
    trimmed.includes('localhost') ||
    trimmed.includes('127.0.0.1') ||
    trimmed.includes('::1') ||
    trimmed.startsWith('mock')
  ) {
    return false;
  }
  return trimmed.includes('.supabase.co') || (trimmed.startsWith('https://') && !trimmed.includes('localhost'));
}

/**
 * Determines whether the current execution context is a local/testing environment
 * where direct access to live/remote Supabase is strictly disallowed.
 */
export function isLocalEnvironment(): boolean {
  if (process.env.LIBRIS_SUPABASE_ISOLATION === 'true') return true;
  if (process.env.NODE_ENV === 'test') return true;

  const backendUrl = (process.env.BACKEND_URL || '').toLowerCase();
  if (
    backendUrl.includes('localhost') ||
    backendUrl.includes('127.0.0.1') ||
    backendUrl.includes('backend:') ||
    backendUrl.includes('libris_backend')
  ) {
    return true;
  }

  const supabaseUrl = (process.env.NEXT_PUBLIC_SUPABASE_URL || '').toLowerCase();
  if (supabaseUrl.includes('mock') || supabaseUrl.includes('localhost')) {
    return true;
  }

  return process.env.NODE_ENV !== 'production';
}

/**
 * Asserts that a Supabase table operation is permitted.
 * If running in a local environment and the target URL is a live remote Supabase project,
 * throws SupabaseIsolationError (fail-closed).
 */
export function assertSafeSupabaseTarget(
  url?: string | null,
  operation: string = 'data operation'
): void {
  const targetUrl = url || process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (isLocalEnvironment() && isRemoteSupabaseUrl(targetUrl)) {
    throw new SupabaseIsolationError(
      `[SupabaseIsolation] Fail-closed: Remote Supabase ${operation} is prohibited in local/test environment. Target URL: [REDACTED_REMOTE_SUPABASE_URL]. Use the unified backend adapter.`
    );
  }
}
