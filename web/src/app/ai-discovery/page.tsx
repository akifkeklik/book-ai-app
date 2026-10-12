'use client';

import { useState } from 'react';
import { askAI } from '../actions/ai';
import { BookCard } from '@/components/BookCard';
import type { Book } from '@/types';
import { Sparkles, Send, BookOpen } from 'lucide-react';

export default function AIDiscoveryPage() {
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [hasQueried, setHasQueried] = useState(false);
  const [lastQueryFailed, setLastQueryFailed] = useState(false);
  const [messages, setMessages] = useState<{role: 'user' | 'ai', content: string, error?: boolean}[]>([]);
  const [referencedBooks, setReferencedBooks] = useState<Book[]>([]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!query.trim() || loading) return;

    const userMessage = query.trim();
    setQuery('');
    setMessages(prev => [...prev, { role: 'user', content: userMessage }]);
    setLoading(true);
    setReferencedBooks([]);
    setLastQueryFailed(false);

    const response = await askAI(userMessage);
    
    setLoading(false);
    setHasQueried(true);
    if (response.error) {
      setLastQueryFailed(true);
      setMessages(prev => [...prev, { role: 'ai', content: response.error!, error: true }]);
    } else {
      setMessages(prev => [...prev, { role: 'ai', content: response.answer || 'Here are the catalog matches for your query:' }]);
      const books = Array.isArray(response.referencedBooks) && response.referencedBooks.length > 0
        ? response.referencedBooks
        : (Array.isArray(response.recommendations) ? response.recommendations : []);
      setReferencedBooks(books);
    }
  };

  const PROMPT_SUGGESTIONS = [
    'Fast-paced sci-fi with mind-bending time travel',
    'Deep mystery novel set in atmospheric rainy London',
    'Epic fantasy with rich worldbuilding and dragons',
    'Heartwarming fiction about second chances in life',
  ];

  const handleSelectSuggestion = (suggestion: string) => {
    setQuery(suggestion);
  };

  return (
    <div className="container animate-fade-in" style={{ maxWidth: '850px', paddingBottom: '4rem' }}>
      <div style={{ textAlign: 'center', marginBottom: '2.5rem' }}>
        <h1 style={{ fontSize: '2.75rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
          <Sparkles className="text-gradient" size={32} />
          <span>AI Discovery</span>
        </h1>
        <p className="text-muted" style={{ fontSize: '1.1rem' }}>
          Describe what you feel like reading, and our AI recommender will find books to match your mood and interests.
        </p>
      </div>

      <div className="glass-panel" style={{ minHeight: '420px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ flex: 1, overflowY: 'auto', padding: '1rem', display: 'flex', flexDirection: 'column', gap: '1.25rem', marginBottom: '1.5rem' }}>
          {messages.length === 0 && (
            <div style={{ margin: 'auto', textAlign: 'center', color: 'var(--muted)', padding: '2rem 1rem' }}>
              <Sparkles size={44} style={{ opacity: 0.3, margin: '0 auto 1rem', color: 'var(--accent)' }} />
              <p style={{ marginBottom: '1.25rem', fontSize: '1rem' }}>Not sure what to ask? Click a suggestion below to start:</p>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.6rem', justifyContent: 'center', maxWidth: '600px', margin: '0 auto' }}>
                {PROMPT_SUGGESTIONS.map((suggestion) => (
                  <button
                    key={suggestion}
                    type="button"
                    onClick={() => handleSelectSuggestion(suggestion)}
                    style={{
                      background: 'rgba(139, 92, 246, 0.1)',
                      border: '1px solid rgba(139, 92, 246, 0.25)',
                      color: 'var(--foreground)',
                      padding: '0.45rem 0.9rem',
                      borderRadius: '9999px',
                      fontSize: '0.825rem',
                      cursor: 'pointer',
                      transition: 'all 0.2s',
                    }}
                    onMouseEnter={(e) => {
                      (e.currentTarget as HTMLButtonElement).style.background = 'rgba(139, 92, 246, 0.25)';
                    }}
                    onMouseLeave={(e) => {
                      (e.currentTarget as HTMLButtonElement).style.background = 'rgba(139, 92, 246, 0.1)';
                    }}
                  >
                    ✨ {suggestion}
                  </button>
                ))}
              </div>
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

      {hasQueried && !loading && !lastQueryFailed && (
        referencedBooks.length > 0 ? (
          <div style={{ marginTop: '3rem' }} className="animate-fade-in" data-testid="referenced-books-section">
            <h3 style={{ fontSize: '1.5rem', marginBottom: '1.5rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <Sparkles className="text-gradient" size={22} />
              <span>Referenced Books</span>
            </h3>
            <div className="grid-books">
              {referencedBooks.map(book => (
                <BookCard key={book.isbn13 || book.title} book={book} />
              ))}
            </div>
          </div>
        ) : (
          <div
            style={{
              marginTop: '3rem',
              textAlign: 'center',
              padding: '2.5rem 1.5rem',
              background: 'rgba(255, 255, 255, 0.02)',
              borderRadius: '16px',
              border: '1px dashed rgba(255, 255, 255, 0.1)',
            }}
            className="animate-fade-in"
            data-testid="no-referenced-books"
          >
            <BookOpen size={36} style={{ opacity: 0.3, margin: '0 auto 0.75rem', color: 'var(--muted)' }} />
            <h4 style={{ fontSize: '1.1rem', marginBottom: '0.25rem', color: 'var(--foreground)' }}>
              No Books Referenced
            </h4>
            <p className="text-muted" style={{ fontSize: '0.9rem', maxWidth: '460px', margin: '0 auto' }}>
              The AI response did not cite any specific books from the catalog for this query. Try describing a genre, plot, or specific reading mood!
            </p>
          </div>
        )
      )}
    </div>
  );
}
