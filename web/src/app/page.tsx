import Link from 'next/link';
import { BookOpen, Sparkles, Compass } from 'lucide-react';

export default function Home() {
  return (
    <div className="container" style={{ padding: '4rem 2rem', textAlign: 'center' }}>
      <div className="animate-fade-in" style={{ maxWidth: '800px', margin: '0 auto' }}>
        <h1 style={{ fontSize: '4rem', marginBottom: '1.5rem', lineHeight: '1.1' }}>
          Discover Books<br />
          <span className="text-gradient">Tailored to You.</span>
        </h1>
        <p className="text-muted" style={{ fontSize: '1.25rem', marginBottom: '3rem' }}>
          Libris uses advanced AI to understand your taste and recommend books you&apos;ll actually love. Stop endlessly scrolling and start reading.
        </p>
        
        <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center', marginBottom: '4rem' }}>
          <Link href="/catalog" className="btn btn-primary" style={{ padding: '1rem 2rem', fontSize: '1.1rem' }}>
            <Compass size={20} /> Browse Catalog
          </Link>
          <Link href="/ai-discovery" className="btn btn-outline" style={{ padding: '1rem 2rem', fontSize: '1.1rem' }}>
            <Sparkles size={20} className="text-gradient" /> Try AI Discovery
          </Link>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: '2rem', textAlign: 'left' }}>
          <div className="glass-panel">
            <div style={{ background: 'rgba(59, 130, 246, 0.1)', width: '48px', height: '48px', borderRadius: '12px', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: '1rem' }}>
              <BookOpen size={24} color="var(--primary)" />
            </div>
            <h3 style={{ fontSize: '1.25rem', marginBottom: '0.5rem' }}>Vast Collection</h3>
            <p className="text-muted">Explore thousands of books across all genres and categories.</p>
          </div>
          
          <div className="glass-panel">
            <div style={{ background: 'rgba(139, 92, 246, 0.1)', width: '48px', height: '48px', borderRadius: '12px', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: '1rem' }}>
              <Sparkles size={24} color="var(--accent)" />
            </div>
            <h3 style={{ fontSize: '1.25rem', marginBottom: '0.5rem' }}>AI Recommendations</h3>
            <p className="text-muted">Our AI understands your preferences to suggest your next favorite read.</p>
          </div>
        </div>
      </div>
    </div>
  );
}
