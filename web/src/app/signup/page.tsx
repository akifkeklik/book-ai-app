'use client';

import { Suspense, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { sanitizeRedirect } from '../login/page';
import { usePreferences } from '@/components/PreferencesProvider';

function SignUpForm() {
  const { t } = usePreferences();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [confirmationSent, setConfirmationSent] = useState(false);
  const router = useRouter();
  const searchParams = useSearchParams();
  const supabase = createClient();

  const rawRedirect = searchParams.get('redirect');
  const safeRedirect = rawRedirect ? sanitizeRedirect(rawRedirect) : '/?onboarding=true';

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);

    try {
      const { data, error: authError } = await supabase.auth.signUp({
        email,
        password,
      });

      if (authError) throw authError;

      if (data.session) {
        // Direct session created (auto-confirmed or confirmation disabled)
        router.push(safeRedirect);
        router.refresh();
      } else if (data.user) {
        // Supabase returns an empty identities array if email already exists with confirmation enabled
        if (data.user.identities && data.user.identities.length === 0) {
          setError(t('signup_exists'));
          return;
        }
        setConfirmationSent(true);
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to sign up');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="glass-panel animate-fade-in" style={{ width: '100%', maxWidth: '400px', padding: '2.5rem' }}>
      <h1 style={{ fontSize: '2rem', textAlign: 'center', marginBottom: '0.5rem' }}>{t('signup_title')}</h1>
      <p className="text-muted text-center" style={{ marginBottom: '2rem' }}>{t('signup_subtitle')}</p>
      
      {error && (
        <div style={{ padding: '0.75rem', background: 'rgba(239, 68, 68, 0.1)', color: 'var(--danger)', borderRadius: '8px', marginBottom: '1.5rem', fontSize: '0.875rem' }}>
          {error}
        </div>
      )}

      {confirmationSent ? (
        <div className="text-center" style={{ padding: '1rem 0' }}>
          <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>✉️</div>
          <h2 style={{ fontSize: '1.25rem', marginBottom: '0.5rem' }}>{t('signup_check_email')}</h2>
          <p className="text-muted" style={{ marginBottom: '1.5rem', fontSize: '0.875rem' }}>
            We sent a confirmation link to <strong>{email}</strong>. Please verify your email before logging in.
          </p>
          <Link
            href={rawRedirect ? `/login?redirect=${encodeURIComponent(rawRedirect)}` : '/login'}
            className="btn btn-primary"
            style={{ display: 'inline-block', width: '100%', padding: '0.75rem', textAlign: 'center' }}
          >
            Go to Log in
          </Link>
        </div>
      ) : (
        <form onSubmit={handleSignUp}>
          <div className="input-group">
            <label className="input-label" htmlFor="email">{t('email_label')}</label>
            <input 
              id="email"
              type="email" 
              required 
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="input-field"
              placeholder={t('email_placeholder')}
            />
          </div>
          
          <div className="input-group">
            <label className="input-label" htmlFor="password">{t('password_label')}</label>
            <input 
              id="password"
              type="password" 
              required 
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="input-field"
              placeholder={t('password_min_hint')}
              minLength={6}
            />
          </div>
          
          <button 
            type="submit" 
            className="btn btn-primary" 
            style={{ width: '100%', marginTop: '1rem', padding: '1rem' }}
            disabled={loading}
          >
            {loading ? 'Creating account...' : 'Sign up'}
          </button>
        </form>
      )}
      
      <p className="text-center" style={{ marginTop: '2rem', fontSize: '0.875rem' }}>
        Already have an account?{' '}
        <Link
          href={rawRedirect ? `/login?redirect=${encodeURIComponent(rawRedirect)}` : '/login'}
          style={{ color: 'var(--primary)', fontWeight: 500 }}
        >
          Log in
        </Link>
      </p>
    </div>
  );
}

export default function SignUpPage() {
  const { t } = usePreferences();
  return (
    <div className="container" style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '70vh' }}>
      <Suspense fallback={<div className="glass-panel" style={{ width: '100%', maxWidth: '400px', padding: '2.5rem', textAlign: 'center' }}>{t('loading')}</div>}>
        <SignUpForm />
      </Suspense>
    </div>
  );
}
