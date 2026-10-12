'use client';

import { Suspense, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';

function LoginForm() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const router = useRouter();
  const searchParams = useSearchParams();
  const supabase = createClient();

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);

    try {
      const { error: authError } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (authError) throw authError;

      const redirectPath = searchParams.get('redirect') || '/catalog';
      // Sanitize redirect path to prevent open redirect vulnerabilities
      const safeRedirect = redirectPath.startsWith('/') && !redirectPath.startsWith('//')
        ? redirectPath
        : '/catalog';

      router.push(safeRedirect);
      router.refresh();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to login');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="glass-panel animate-fade-in" style={{ width: '100%', maxWidth: '400px', padding: '2.5rem' }}>
      <h1 style={{ fontSize: '2rem', textAlign: 'center', marginBottom: '0.5rem' }}>Welcome Back</h1>
      <p className="text-muted text-center" style={{ marginBottom: '2rem' }}>Log in to access your personalized recommendations and library.</p>
      
      {error && (
        <div style={{ padding: '0.75rem', background: 'rgba(239, 68, 68, 0.1)', color: 'var(--danger)', borderRadius: '8px', marginBottom: '1.5rem', fontSize: '0.875rem' }}>
          {error}
        </div>
      )}

      <form onSubmit={handleLogin}>
        <div className="input-group">
          <label className="input-label" htmlFor="email">Email</label>
          <input 
            id="email"
            type="email" 
            required 
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="input-field"
            placeholder="your@email.com"
          />
        </div>
        
        <div className="input-group">
          <label className="input-label" htmlFor="password">Password</label>
          <input 
            id="password"
            type="password" 
            required 
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="input-field"
            placeholder="••••••••"
          />
        </div>
        
        <button 
          type="submit" 
          className="btn btn-primary" 
          style={{ width: '100%', marginTop: '1rem', padding: '1rem' }}
          disabled={loading}
        >
          {loading ? 'Logging in...' : 'Log in'}
        </button>
      </form>
      
      <p className="text-center" style={{ marginTop: '2rem', fontSize: '0.875rem' }}>
        Don&apos;t have an account? <Link href="/signup" style={{ color: 'var(--primary)', fontWeight: 500 }}>Sign up</Link>
      </p>
    </div>
  );
}

export default function LoginPage() {
  return (
    <div className="container" style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '70vh' }}>
      <Suspense fallback={<div className="glass-panel" style={{ width: '100%', maxWidth: '400px', padding: '2.5rem', textAlign: 'center' }}>Loading...</div>}>
        <LoginForm />
      </Suspense>
    </div>
  );
}
