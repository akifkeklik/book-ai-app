'use client';

import { useState, useRef, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { streamAiChat } from '@/lib/ai_stream';
import { BookCard } from '@/components/BookCard';
import type { Book, AiAction } from '@/types';
import { usePreferences } from '@/components/PreferencesProvider';
import { isLanguage, LANGUAGE_NAMES, type Language, type ColorPalette, type ThemeMode } from '@/lib/preferences';
import { translate, type TranslationKey } from '@/lib/i18n';
import { Sparkles, Send, BookOpen, RefreshCw, CheckCircle2, Square } from 'lucide-react';

interface ChatMessage {
  id: string;
  role: 'user' | 'ai';
  content: string;
  error?: boolean;
  streaming?: boolean;
  actionBadge?: string;
  isGrounded?: boolean;
  referencedBooks?: Book[];
}

export default function AIDiscoveryPage() {
  const router = useRouter();
  const { preferences, setThemeMode, setColorPalette, setLanguage, t } = usePreferences();
  const lang = preferences.language || 'en';

  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [hasQueried, setHasQueried] = useState(false);
  const [lastQueryFailed, setLastQueryFailed] = useState(false);
  const [lastUserMessage, setLastUserMessage] = useState('');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [referencedBooks, setReferencedBooks] = useState<Book[]>([]);

  const abortControllerRef = useRef<AbortController | null>(null);
  const chatBottomRef = useRef<HTMLDivElement | null>(null);
  const messageIdCounterRef = useRef(0);

  // Clean up abort controller on unmount
  useEffect(() => {
    return () => {
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
      }
    };
  }, []);

  const scrollToBottom = () => {
    chatBottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  const executeAction = useCallback((action?: AiAction | null): string | undefined => {
    if (!action || typeof action !== 'object' || !action.type) return undefined;

    switch (action.type) {
      case 'SET_THEME': {
        const theme = action.payload?.theme as ThemeMode;
        if (theme === 'dark' || theme === 'light' || theme === 'system') {
          setThemeMode(theme);
          const themeLabel =
            theme === 'dark'
              ? translate(lang, 'theme_dark')
              : theme === 'light'
              ? translate(lang, 'theme_light')
              : translate(lang, 'theme_system');
          return translate(lang, 'ai_action_theme', { theme: themeLabel });
        }
        break;
      }
      case 'SET_PALETTE': {
        const pal = action.payload?.palette as ColorPalette;
        const validPalettes: ColorPalette[] = ['ocean_blue', 'forest_green', 'lavender', 'terracotta', 'amber', 'turquoise'];
        if (validPalettes.includes(pal)) {
          setColorPalette(pal);
          const paletteLabel = translate(lang, `palette_${pal}` as TranslationKey) || pal;
          return translate(lang, 'ai_action_palette', { palette: paletteLabel });
        }
        break;
      }
      case 'SET_LANGUAGE': {
        const l = action.payload?.language as Language;
        if (isLanguage(l)) {
          setLanguage(l);
          return translate(lang, 'ai_action_language', { language: LANGUAGE_NAMES[l] });
        }
        break;
      }
      case 'NAVIGATE': {
        const url = action.payload?.url;
        if (url && typeof url === 'string' && url.startsWith('/')) {
          router.push(url);
          return translate(lang, 'ai_action_navigate', { url });
        }
        break;
      }
    }
    return undefined;
  }, [lang, router, setColorPalette, setLanguage, setThemeMode]);

  const handleStopStream = () => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }
    setLoading(false);
    setMessages((prev) =>
      prev.map((msg, idx) =>
        idx === prev.length - 1 && msg.role === 'ai' && msg.streaming
          ? { ...msg, streaming: false, content: msg.content ? `${msg.content} (Stopped)` : 'Response cancelled.' }
          : msg
      )
    );
  };

  const handleSend = async (userMessage: string) => {
    const trimmed = userMessage.trim();
    if (!trimmed || loading) return; // Prevent duplicate submissions

    // Abort any prior in-flight request
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }

    const controller = new AbortController();
    abortControllerRef.current = controller;

    setQuery('');
    setLastUserMessage(trimmed);
    setLoading(true);
    setHasQueried(true);
    setLastQueryFailed(false);
    setReferencedBooks([]);

    const userMsgId = `user-${++messageIdCounterRef.current}`;
    const aiMsgId = `ai-${++messageIdCounterRef.current}`;

    setMessages((prev) => [
      ...prev,
      { id: userMsgId, role: 'user', content: trimmed },
      { id: aiMsgId, role: 'ai', content: '', streaming: true },
    ]);

    let accumulatedContent = '';
    let streamAction: AiAction | null = null;
    let streamReferencedBooks: Book[] = [];

    await streamAiChat(trimmed, {
      signal: controller.signal,
      onMetadata: (meta) => {
        if (controller.signal.aborted) return;
        if (meta.referenced_books && meta.referenced_books.length > 0) {
          streamReferencedBooks = meta.referenced_books;
          setReferencedBooks(meta.referenced_books);
          setMessages((prev) =>
            prev.map((m) =>
              m.id === aiMsgId
                ? { ...m, isGrounded: true, referencedBooks: meta.referenced_books }
                : m
            )
          );
        }
      },
      onChunk: (delta) => {
        if (controller.signal.aborted) return;
        accumulatedContent += delta;
        setMessages((prev) =>
          prev.map((m) =>
            m.id === aiMsgId ? { ...m, content: accumulatedContent } : m
          )
        );
        scrollToBottom();
      },
      onDone: (donePayload) => {
        if (controller.signal.aborted) return;
        const books =
          donePayload.referenced_books && donePayload.referenced_books.length > 0
            ? donePayload.referenced_books
            : streamReferencedBooks;

        setReferencedBooks(books);
        const finalAnswer = donePayload.answer || accumulatedContent || 'No details returned.';
        streamAction = donePayload.action || null;

        let badge: string | undefined;
        if (streamAction) {
          badge = executeAction(streamAction);
        }

        setMessages((prev) =>
          prev.map((m) =>
            m.id === aiMsgId
              ? {
                  ...m,
                  content: finalAnswer,
                  streaming: false,
                  actionBadge: badge,
                  isGrounded: books.length > 0,
                  referencedBooks: books,
                }
              : m
          )
        );
        setLoading(false);
        abortControllerRef.current = null;
      },
      onError: (errorMsg) => {
        if (controller.signal.aborted) return;
        setLastQueryFailed(true);
        setMessages((prev) =>
          prev.map((m) =>
            m.id === aiMsgId
              ? {
                  ...m,
                  content: errorMsg || 'An error occurred during AI processing.',
                  error: true,
                  streaming: false,
                }
              : m
          )
        );
        setLoading(false);
        abortControllerRef.current = null;
      },
    });
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    handleSend(query);
  };

  const PROMPT_SUGGESTIONS_BY_LANG: Record<Language, string[]> = {
    en: [
      'Do you have the book 1984?',
      'Books like Atomic Habits',
      'A short philosophy book for beginners',
      'Switch to dark mode',
    ],
    tr: [
      '1984 kitabı var mı?',
      'Atomik Alışkanlıklar gibi kitaplar',
      'Yeni başlayanlar için kısa bir felsefe kitabı',
      'Koyu temaya geç',
    ],
    de: [
      'Gibt es das Buch 1984?',
      'Bücher wie Die 1%-Methode',
      'Ein kurzes Philosophiebuch für Einsteiger',
      'Dunklen Modus aktivieren',
    ],
    es: [
      '¿Tenéis el libro 1984?',
      'Libros como Hábitos atómicos',
      'Un libro de filosofía breve para principiantes',
      'Cambiar al modo oscuro',
    ],
    fr: [
      'Avez-vous le livre 1984 ?',
      'Des livres comme Atomic Habits',
      'Un court livre de philosophie pour débuter',
      'Passer en mode sombre',
    ],
    it: [
      'Avete il libro 1984?',
      'Libri come Atomic Habits',
      'Un breve libro di filosofia per principianti',
      'Passa alla modalità scura',
    ],
  };

  const suggestions = PROMPT_SUGGESTIONS_BY_LANG[lang] || PROMPT_SUGGESTIONS_BY_LANG.en;

  // Derive honest grounding status
  const isGrounded = referencedBooks.length > 0;

  return (
    <div className="container animate-fade-in" style={{ maxWidth: '850px', paddingBottom: '4rem' }}>
      <div style={{ textAlign: 'center', marginBottom: '2.5rem' }}>
        <h1
          style={{
            fontSize: '2.75rem',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '0.5rem',
            marginBottom: '0.5rem',
          }}
        >
          <Sparkles className="text-gradient" size={32} />
          <span>{t('ai_title')}</span>
        </h1>
        <p className="text-muted" style={{ fontSize: '1.1rem' }}>
          {t('ai_subtitle')}
        </p>
      </div>

      <div className="saas-chat-box">
        {/* Header Honest RAG Status Indicator */}
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            borderBottom: '1px solid var(--card-border)',
            paddingBottom: '0.75rem',
          }}
        >
          <div className="saas-chat-grounded-pill" style={{ margin: 0 }} data-testid="rag-grounding-indicator">
            {loading ? (
              <>
                <span className="saas-pulse-dot" style={{ backgroundColor: '#f59e0b' }} />
                <span>
                  {t('ai_streaming')}
                </span>
              </>
            ) : isGrounded ? (
              <>
                <span className="saas-pulse-dot cyan" />
                <span>
                  {t('ai_grounded', { count: referencedBooks.length })}
                </span>
              </>
            ) : hasQueried ? (
              <>
                <span className="saas-pulse-dot" style={{ backgroundColor: '#94a3b8' }} />
                <span>
                  {t('ai_general')}
                </span>
              </>
            ) : (
              <>
                <span className="saas-pulse-dot cyan" />
                <span>{t('ai_ready')}</span>
              </>
            )}
          </div>
        </div>

        <div
          style={{
            flex: 1,
            overflowY: 'auto',
            padding: '0.5rem 0',
            display: 'flex',
            flexDirection: 'column',
            gap: '1.25rem',
            marginBottom: '1.25rem',
            minHeight: '260px',
            maxHeight: '480px',
          }}
        >
          {messages.length === 0 && (
            <div style={{ margin: 'auto', textAlign: 'center', color: 'var(--muted)', padding: '2rem 1rem' }}>
              <Sparkles size={44} style={{ opacity: 0.3, margin: '0 auto 1rem', color: 'var(--accent)' }} />
              <p style={{ marginBottom: '1.25rem', fontSize: '1rem' }}>
                {t('ai_suggestion_prompt')}
              </p>
              <div
                style={{
                  display: 'flex',
                  flexWrap: 'wrap',
                  gap: '0.6rem',
                  justifyContent: 'center',
                  maxWidth: '650px',
                  margin: '0 auto',
                }}
              >
                {suggestions.map((suggestion) => (
                  <button
                    key={suggestion}
                    type="button"
                    onClick={() => handleSend(suggestion)}
                    style={{
                      background: 'rgba(56, 189, 248, 0.08)',
                      border: '1px solid rgba(56, 189, 248, 0.22)',
                      color: 'var(--foreground)',
                      padding: '0.45rem 0.9rem',
                      borderRadius: '9999px',
                      fontSize: '0.825rem',
                      cursor: 'pointer',
                      transition: 'all 0.2s',
                    }}
                    onMouseEnter={(e) => {
                      (e.currentTarget as HTMLButtonElement).style.background = 'rgba(56, 189, 248, 0.18)';
                    }}
                    onMouseLeave={(e) => {
                      (e.currentTarget as HTMLButtonElement).style.background = 'rgba(56, 189, 248, 0.08)';
                    }}
                  >
                    ✨ {suggestion}
                  </button>
                ))}
              </div>
            </div>
          )}

          {messages.map((msg) => (
            <div
              key={msg.id}
              className={msg.role === 'user' ? 'saas-chat-bubble-user' : 'saas-chat-bubble-ai'}
              style={msg.error ? { background: 'rgba(239, 68, 68, 0.15)', borderColor: 'rgba(239, 68, 68, 0.4)', color: '#fca5a5' } : undefined}
            >
              {msg.role === 'ai' && !msg.error && (
                <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '6px' }}>
                  <Sparkles size={13} color="var(--electric-blue)" />
                  <span style={{ fontSize: '0.72rem', fontWeight: 700, color: 'var(--electric-blue)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                    Libris Intelligence {msg.streaming ? '· Streaming...' : ''}
                  </span>
                  {msg.isGrounded && (
                    <span
                      style={{
                        marginLeft: 'auto',
                        fontSize: '0.7rem',
                        color: 'var(--success)',
                        fontWeight: 600,
                      }}
                    >
                      ✓ Grounded
                    </span>
                  )}
                </div>
              )}
              <div style={{ whiteSpace: 'pre-wrap', lineHeight: 1.55 }}>
                {msg.content}
                {msg.streaming && !msg.content && (
                  <span className="animate-pulse" style={{ color: 'var(--text-muted)' }}>
                    {t('ai_thinking')}
                  </span>
                )}
                {msg.streaming && msg.content && (
                  <span
                    style={{
                      display: 'inline-block',
                      width: '6px',
                      height: '14px',
                      backgroundColor: 'var(--electric-blue)',
                      marginLeft: '4px',
                      verticalAlign: 'middle',
                      animation: 'pulse 1s infinite',
                    }}
                  />
                )}
              </div>
              {msg.actionBadge && (
                <div
                  style={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: '0.35rem',
                    marginTop: '0.6rem',
                    padding: '0.25rem 0.65rem',
                    borderRadius: '6px',
                    background: 'rgba(16, 185, 129, 0.2)',
                    border: '1px solid rgba(16, 185, 129, 0.4)',
                    color: '#34d399',
                    fontSize: '0.775rem',
                    fontWeight: 500,
                  }}
                >
                  <CheckCircle2 size={13} />
                  <span>{msg.actionBadge}</span>
                </div>
              )}
            </div>
          ))}

          <div ref={chatBottomRef} />
        </div>

        {lastQueryFailed && !loading && (
          <div style={{ alignSelf: 'flex-start', marginBottom: '0.75rem' }}>
            <button
              type="button"
              onClick={() => handleSend(lastUserMessage)}
              className="btn btn-outline"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: '0.4rem',
                padding: '0.35rem 0.75rem',
                fontSize: '0.8rem',
              }}
            >
              <RefreshCw size={14} />
              <span>{translate(lang, 'retry')}</span>
            </button>
          </div>
        )}

        <form onSubmit={handleSubmit} style={{ display: 'flex', gap: '0.5rem' }}>
          <label htmlFor="ai-discovery-query-input" className="sr-only">
            {translate(lang, 'search_placeholder')}
          </label>
          <input
            id="ai-discovery-query-input"
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={translate(lang, 'search_placeholder')}
            className="input-field"
            style={{ flex: 1 }}
            disabled={loading}
            aria-label={translate(lang, 'search_placeholder')}
          />
          {loading ? (
            <button
              type="button"
              onClick={handleStopStream}
              className="btn btn-outline"
              title={t('ai_stop_label')}
              aria-label={t('ai_stop')}
              style={{ borderColor: 'rgba(239, 68, 68, 0.5)', color: '#ef4444' }}
            >
              <Square size={16} fill="currentColor" />
            </button>
          ) : (
            <button
              type="submit"
              className="btn btn-primary"
              disabled={!query.trim()}
              aria-label={translate(lang, 'search')}
            >
              <Send size={18} />
            </button>
          )}
        </form>
      </div>

      {hasQueried && !loading && !lastQueryFailed && (
        referencedBooks.length > 0 ? (
          <div style={{ marginTop: '3rem' }} className="animate-fade-in" data-testid="referenced-books-section">
            <h3
              style={{
                fontSize: '1.5rem',
                marginBottom: '1.5rem',
                display: 'flex',
                alignItems: 'center',
                gap: '0.5rem',
              }}
            >
              <Sparkles className="text-gradient" size={22} />
              <span>{t('ai_referenced_books')}</span>
            </h3>
            <div className="grid-books">
              {referencedBooks.map((book) => (
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
              {t('ai_no_referenced_books')}
            </h4>
            <p className="text-muted" style={{ fontSize: '0.9rem', maxWidth: '460px', margin: '0 auto' }}>
              {t('ai_no_referenced_desc')}
            </p>
          </div>
        )
      )}
    </div>
  );
}
