'use client';

import Link from 'next/link';
import { useAuth } from './AuthProvider';
import { BookOpen, LogOut, Compass, Sparkles } from 'lucide-react';

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
          {!loading && (
            <>
              {user ? (
                <>
                  <Link href="/catalog" className="text-muted flex items-center gap-2 hover:text-white transition-colors">
                    <Compass size={18} />
                    <span>Catalog</span>
                  </Link>
                  <Link href="/ai-discovery" className="text-muted flex items-center gap-2 hover:text-white transition-colors">
                    <Sparkles size={18} color="var(--accent)" />
                    <span className="text-gradient">AI Discovery</span>
                  </Link>
                  <button onClick={signOut} className="btn btn-outline ml-4">
                    <LogOut size={16} />
                    <span>Sign Out</span>
                  </button>
                </>
              ) : (
                <>
                  <Link href="/login" className="btn btn-outline">Log in</Link>
                  <Link href="/signup" className="btn btn-primary">Sign up</Link>
                </>
              )}
            </>
          )}
        </div>
      </div>
    </nav>
  );
}
