'use client';

import Link from 'next/link';
import { useAuth } from './AuthProvider';
import { BookOpen, LogOut, Compass, Sparkles, Bookmark } from 'lucide-react';

export function Navbar() {
  const { user, loading, signOut } = useAuth();

  return (
    <nav className="navbar">
      <div className="container nav-container">
        <Link href="/" className="brand">
          <BookOpen size={24} color="var(--primary)" />
          <span>Libris</span>
        </Link>
        
        <div className="nav-links">
          <Link href="/catalog" className="text-muted flex items-center gap-2 hover:text-white transition-colors">
            <Compass size={18} />
            <span>Catalog</span>
          </Link>
          <Link href="/ai-discovery" className="text-muted flex items-center gap-2 hover:text-white transition-colors">
            <Sparkles size={18} color="var(--accent)" />
            <span className="text-gradient">AI Discovery</span>
          </Link>

          {!loading && user && (
            <Link
              href="/favorites"
              id="nav-library-link"
              className="text-muted flex items-center gap-2 hover:text-white transition-colors"
            >
              <Bookmark size={18} color="var(--primary)" />
              <span>Library</span>
            </Link>
          )}

          {!loading && (
            <>
              {user ? (
                <button onClick={signOut} className="btn btn-outline" style={{ padding: '0.5rem 1rem', fontSize: '0.875rem', marginLeft: '0.5rem' }}>
                  <LogOut size={16} />
                  <span>Sign Out</span>
                </button>
              ) : (
                <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center', marginLeft: '0.5rem' }}>
                  <Link href="/login" className="btn btn-outline" style={{ padding: '0.5rem 1rem', fontSize: '0.875rem' }}>Log in</Link>
                  <Link href="/signup" className="btn btn-primary" style={{ padding: '0.5rem 1rem', fontSize: '0.875rem' }}>Sign up</Link>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </nav>
  );
}
