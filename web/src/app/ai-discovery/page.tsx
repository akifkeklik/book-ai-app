'use client';

import { useState } from 'react';
import { askAI } from '../actions/ai';
import { BookCard } from '@/components/BookCard';
import type { Book } from '@/types';
import { Sparkles, Send } from 'lucide-react';

export default function AIDiscoveryPage() {
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [messages, setMessages] = useState<{role: 'user' | 'ai', content: string, error?: boolean}[]>([]);
  const [recommendations, setRecommendations] = useState<Book[]>([]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!query.trim()) return;

    const userMessage = query.trim();
    setQuery('');
    setMessages(prev => [...prev, { role: 'user', content: userMessage }]);
    setLoading(true);
    setRecommendations([]);

    const response = await askAI(userMessage);
    
    setLoading(false);
    if (response.error) {
      setMessages(prev => [...prev, { role: 'ai', content: response.error!, error: true }]);
    } else {
      setMessages(prev => [...prev, { role: 'ai', content: response.answer }]);
      if (response.recommendations && response.recommendations.length > 0) {
        setRecommendations(response.recommendations);
      }
    }
  };

  return (
    <div className="container animate-fade-in" style={{ maxWidth: '800px', paddingBottom: '4rem' }}>
      <div style={{ textAlign: 'center', marginBottom: '3rem' }}>
        <h1 style={{ fontSize: '2.5rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.5rem' }}>
          <Sparkles className="text-gradient" size={32} />
          <span>AI Discovery</span>
        </h1>
        <p className="text-muted">Tell me what kind of book you&apos;re looking for.</p>
      </div>

      <div className="glass-panel" style={{ minHeight: '400px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ flex: 1, overflowY: 'auto', padding: '1rem', display: 'flex', flexDirection: 'column', gap: '1.5rem', marginBottom: '1.5rem' }}>
          {messages.length === 0 && (
            <div style={{ margin: 'auto', textAlign: 'center', color: 'var(--muted)' }}>
              <Sparkles size={48} style={{ opacity: 0.2, margin: '0 auto 1rem' }} />
              <p>Try saying: &quot;I want a sci-fi book about time travel with a strong female lead&quot;</p>
            </div>
          )}
          
          {messages.map((msg, i) => (
            <div key={i} style={{ 
              alignSelf: msg.role === 'user' ? 'flex-end' : 'flex-start',
              background: msg.role === 'user' ? 'var(--primary)' : msg.error ? 'rgba(239, 68, 68, 0.2)' : 'rgba(255,255,255,0.05)',
              color: msg.error ? 'var(--danger)' : 'white',
              padding: '1rem 1.5rem',
              borderRadius: '16px',
              borderBottomRightRadius: msg.role === 'user' ? '4px' : '16px',
              borderBottomLeftRadius: msg.role === 'ai' ? '4px' : '16px',
              maxWidth: '85%',
              lineHeight: 1.6
            }}>
              {msg.content}
            </div>
          ))}
          {loading && (
            <div style={{ alignSelf: 'flex-start', background: 'rgba(255,255,255,0.05)', padding: '1rem 1.5rem', borderRadius: '16px', borderBottomLeftRadius: '4px' }}>
              <span className="animate-pulse">Thinking...</span>
            </div>
          )}
        </div>

        <form onSubmit={handleSubmit} style={{ display: 'flex', gap: '0.5rem' }}>
          <input 
            type="text" 
            value={query} 
            onChange={(e) => setQuery(e.target.value)} 
            placeholder="Describe your ideal book..." 
            className="input-field"
            style={{ flex: 1 }}
            disabled={loading}
          />
          <button type="submit" className="btn btn-primary" disabled={loading || !query.trim()}>
            <Send size={18} />
          </button>
        </form>
      </div>

      {recommendations.length > 0 && (
        <div style={{ marginTop: '3rem' }} className="animate-fade-in">
          <h3 style={{ fontSize: '1.5rem', marginBottom: '1.5rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            Recommended Books
          </h3>
          <div className="grid-books">
            {recommendations.map(book => (
              <BookCard key={book.isbn13} book={book} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
