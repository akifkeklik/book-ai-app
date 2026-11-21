'use client';

import { useState, useRef, useEffect, useCallback, memo } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { streamAiChat, type StreamErrorInfo } from '@/lib/ai_stream';
import { BookCard } from '@/components/BookCard';
import { ChatMarkdown } from '@/components/ChatMarkdown';
import { AiActivityPanel } from '@/components/AiActivityPanel';
import { useConversationHistory, readConversations, writeConversations } from '@/components/useConversationHistory';
import type { Book, AiAction } from '@/types';
import { usePreferences } from '@/components/PreferencesProvider';
import { isLanguage, LANGUAGE_NAMES, type Language, type ThemeMode } from '@/lib/preferences';
import { normalizeThemeId } from '@/lib/themes';
import { translate, type TranslationKey } from '@/lib/i18n';
import {
  contextIsbnsFor,
  conversationTitle,
  newConversationId,
  describeAnswerSource,
  upsertConversation,
  type Conversation,
  type StoredMessage,
} from '@/lib/ai_chat';
import { Sparkles, Send, BookOpen, RefreshCw, CheckCircle2, Square, AlertTriangle, Copy, Check, Plus } from 'lucide-react';
import './ai-chat.css';

interface ChatMessage extends StoredMessage {
  streaming?: boolean;
}

const PROMPT_SUGGESTIONS_BY_LANG: Record<Language, string[]> = {
  en: ['Do you have the book 1984?', 'Books like Dune', 'A short philosophy book for beginners', 'Switch to dark mode'],
  tr: ['1984 kitabı var mı?', 'Dune gibi kitaplar', 'Yeni başlayanlar için kısa bir felsefe kitabı', 'Koyu temaya geç'],
  de: ['Gibt es das Buch 1984?', 'Bücher wie Dune', 'Ein kurzes Philosophiebuch für Einsteiger', 'Dunklen Modus aktivieren'],
  es: ['¿Tenéis el libro 1984?', 'Libros como Dune', 'Un libro de filosofía breve para principiantes', 'Cambiar al modo oscuro'],
  fr: ['Avez-vous le livre 1984 ?', 'Des livres comme Dune', 'Un court livre de philosophie pour débuter', 'Passer en mode sombre'],
  it: ['Avete il libro 1984?', 'Libri come Dune', 'Un breve libro di filosofia per principianti', 'Passa alla modalità scura'],
};

function errorMessageKey(info?: StreamErrorInfo): TranslationKey | null {
  if (info?.network) return 'ai_error_network';
  if (info?.server) return 'ai_error_server';
  if (info?.status === 429) return 'ai_error_rate';
  if (info?.status && info.status >= 500) return 'ai_error_network';
  return null;
}

const MessageBubble = memo(function MessageBubble({
  msg,
  t,
}: {
  msg: ChatMessage;
  t: (key: TranslationKey, args?: Record<string, string | number>) => string;
}) {
  const [copied, setCopied] = useState(false);

  if (msg.role === 'user') {
    return (
      <div className="ai-msg ai-msg-user">
        <span className="sr-only">{t('ai_you')}: </span>
        <div className="ai-bubble ai-bubble-user">{msg.content}</div>
      </div>
    );
  }

  if (msg.error) {
    return (
      <div className="ai-msg ai-msg-ai" role="alert">
        <div className="ai-avatar ai-avatar-error" aria-hidden="true">
          <AlertTriangle size={15} />
        </div>
        <div className="ai-bubble ai-bubble-error">
          <strong>{t('ai_error_title')}</strong>
          <p>{msg.content}</p>
        </div>
      </div>
    );
  }

  const source = !msg.streaming && msg.status ? describeAnswerSource(msg.status, msg.source, msg.retrievalMode) : null;
  const books = msg.referencedBooks || [];

  const copy = () => {
    navigator.clipboard?.writeText(msg.content).then(
      () => {
        setCopied(true);
        window.setTimeout(() => setCopied(false), 1500);
      },
      () => {},
    );
  };

  return (
    <div className="ai-msg ai-msg-ai">
      <div className="ai-avatar" aria-hidden="true">
        <Sparkles size={15} />
      </div>
      <div className="ai-bubble ai-bubble-ai" aria-busy={msg.streaming || undefined}>
        <div className="ai-bubble-head">
          <span className="ai-bubble-name">Libris AI</span>
          {source && (
            <span className={`ai-source-chip is-${source.kind}`} data-testid="ai-answer-source" data-source={source.kind}>
              {t(source.labelKey)}
            </span>
          )}
        </div>

        {msg.streaming && !msg.content ? (
          <div className="ai-typing" aria-label={t('ai_thinking')}>
            <span />
            <span />
            <span />
          </div>
        ) : (
          <div className={msg.streaming ? 'ai-streaming' : undefined}>
            <ChatMarkdown content={msg.content} />
          </div>
        )}

        {source?.degraded && <p className="ai-degraded-note">{t('ai_retrieval_degraded')}</p>}

        {books.length > 0 && !msg.streaming && (
          <div className="ai-sources">
            <span className="ai-sources-label">{t('ai_referenced_books')}</span>
            <ul>
              {books.slice(0, 6).map((b) => (
                <li key={b.isbn13 || b.title}>
                  {b.isbn13 ? (
                    <Link href={`/book/${encodeURIComponent(b.isbn13)}`}>{b.title}</Link>
                  ) : (
                    <span>{b.title}</span>
                  )}
                </li>
              ))}
            </ul>
          </div>
        )}

        {(msg.actionBadge || (!msg.streaming && msg.content)) && (
          <div className="ai-bubble-foot">
            {msg.actionBadge && (
              <span className="ai-action-badge">
                <CheckCircle2 size={13} aria-hidden="true" />
                {msg.actionBadge}
              </span>
            )}
            {!msg.streaming && msg.content && (
              <button type="button" className="ai-icon-btn" onClick={copy} aria-label={t('ai_copy')} title={t('ai_copy')}>
                {copied ? <Check size={14} aria-hidden="true" /> : <Copy size={14} aria-hidden="true" />}
                <span className="sr-only" aria-live="polite">{copied ? t('ai_copied') : ''}</span>
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
});

export default function AIDiscoveryPage() {
  const router = useRouter();
  const { preferences, setThemeMode, setColorPalette, setLanguage, t } = usePreferences();
  const lang = preferences.language || 'en';

  const conversations = useConversationHistory();
  const [activeId, setActiveId] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [lastQueryFailed, setLastQueryFailed] = useState(false);
  const [lastUserMessage, setLastUserMessage] = useState('');
  const [messages, setMessages] = useState<ChatMessage[]>([]);

  const abortControllerRef = useRef<AbortController | null>(null);
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const inputRef = useRef<HTMLTextAreaElement | null>(null);
  const stickToBottomRef = useRef(true);
  const messageIdCounterRef = useRef(0);

  useEffect(() => {
    return () => abortControllerRef.current?.abort();
  }, []);

  // Keep the view pinned to the newest text while streaming, unless the user scrolled up to read.
  useEffect(() => {
    const el = scrollRef.current;
    if (el && stickToBottomRef.current) el.scrollTop = el.scrollHeight;
  }, [messages]);

  // Persist the conversation once no answer is in flight.
  useEffect(() => {
    if (!activeId || !messages.length || messages.some((m) => m.streaming)) return;
    const existing = readConversations().find((c) => c.id === activeId);
    const now = new Date().toISOString();
    const firstUser = messages.find((m) => m.role === 'user');
    const stored: StoredMessage[] = messages.map((m) => {
      const copy: ChatMessage = { ...m };
      delete copy.streaming;
      return copy;
    });
    writeConversations(
      upsertConversation(readConversations(), {
        id: activeId,
        title: existing?.title || conversationTitle(firstUser?.content || ''),
        createdAt: existing?.createdAt || now,
        updatedAt: now,
        messages: stored,
      }),
    );
  }, [messages, activeId]);

  const onScroll = () => {
    const el = scrollRef.current;
    if (el) stickToBottomRef.current = el.scrollHeight - el.scrollTop - el.clientHeight < 48;
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
        // Accepts current theme ids and the legacy palette ids the backend may still send.
        const theme = normalizeThemeId(action.payload?.palette);
        if (theme) {
          setColorPalette(theme);
          return translate(lang, 'ai_action_palette', { palette: translate(lang, `palette_${theme}`) });
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
        if (url && typeof url === 'string' && url.startsWith('/') && !url.startsWith('//')) {
          router.push(url);
          return translate(lang, 'ai_action_navigate', { url });
        }
        break;
      }
    }
    return undefined;
  }, [lang, router, setColorPalette, setLanguage, setThemeMode]);

  const handleStopStream = () => {
    abortControllerRef.current?.abort();
    abortControllerRef.current = null;
    setLoading(false);
    setMessages((prev) =>
      prev.map((msg) =>
        msg.role === 'ai' && msg.streaming
          ? {
              ...msg,
              streaming: false,
              status: undefined,
              content: msg.content ? `${msg.content}\n\n_${t('ai_stopped')}_` : t('ai_cancelled'),
            }
          : msg
      )
    );
  };

  const handleSend = async (userMessage: string) => {
    const trimmed = userMessage.trim();
    if (!trimmed || loading) return;

    abortControllerRef.current?.abort();
    const controller = new AbortController();
    abortControllerRef.current = controller;

    const conversationId = activeId ?? newConversationId();
    if (!activeId) setActiveId(conversationId);

    // Captured before the new turn is appended: the books the user can be referring to.
    const contextIsbns = contextIsbnsFor(messages);

    setQuery('');
    setLastUserMessage(trimmed);
    setLoading(true);
    setLastQueryFailed(false);
    stickToBottomRef.current = true;

    const userMsgId = `user-${++messageIdCounterRef.current}`;
    const aiMsgId = `ai-${++messageIdCounterRef.current}`;
    setMessages((prev) => [
      ...prev,
      { id: userMsgId, role: 'user', content: trimmed },
      { id: aiMsgId, role: 'ai', content: '', streaming: true },
    ]);

    const patch = (fields: Partial<ChatMessage>) =>
      setMessages((prev) => prev.map((m) => (m.id === aiMsgId ? { ...m, ...fields } : m)));

    let accumulated = '';
    let metaBooks: Book[] = [];

    await streamAiChat(trimmed, {
      signal: controller.signal,
      contextIsbns,
      onMetadata: (meta) => {
        if (controller.signal.aborted) return;
        if (meta.referenced_books.length > 0) {
          metaBooks = meta.referenced_books;
          patch({ referencedBooks: meta.referenced_books });
        }
      },
      onChunk: (delta) => {
        if (controller.signal.aborted) return;
        accumulated += delta;
        patch({ content: accumulated });
      },
      onDone: (done) => {
        if (controller.signal.aborted) return;
        const books = done.referenced_books.length > 0 ? done.referenced_books : metaBooks;
        patch({
          content: done.answer || accumulated || t('ai_no_referenced_books'),
          streaming: false,
          status: done.status,
          source: done.source ?? null,
          retrievalMode: done.retrieval_mode ?? null,
          actionBadge: done.action ? executeAction(done.action) : undefined,
          referencedBooks: books,
        });
        setLoading(false);
        abortControllerRef.current = null;
      },
      onError: (errorMsg, info) => {
        if (controller.signal.aborted) return;
        setLastQueryFailed(true);
        const key = errorMessageKey(info);
        patch({ content: key ? t(key) : errorMsg || t('ai_error_network'), error: true, streaming: false });
        setLoading(false);
        abortControllerRef.current = null;
      },
    });
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    handleSend(query);
  };

  const onKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault();
      handleSend(query);
    }
  };

  const startNewChat = () => {
    if (loading) return;
    setActiveId(null);
    setMessages([]);
    setLastQueryFailed(false);
    inputRef.current?.focus();
  };

  const openConversation = (c: Conversation) => {
    if (loading) handleStopStream();
    setActiveId(c.id);
    setMessages(c.messages);
    setLastQueryFailed(false);
    stickToBottomRef.current = true;
  };

  const deleteConversation = (id: string) => {
    writeConversations(readConversations().filter((c) => c.id !== id));
    if (id === activeId) {
      setActiveId(null);
      setMessages([]);
    }
  };

  const suggestions = PROMPT_SUGGESTIONS_BY_LANG[lang] || PROMPT_SUGGESTIONS_BY_LANG.en;
  const lastAi = [...messages].reverse().find((m) => m.role === 'ai');
  const referencedBooks = lastAi && !lastAi.streaming && !lastAi.error ? lastAi.referencedBooks || [] : [];
  const lastSource = lastAi?.status && !lastAi.streaming ? describeAnswerSource(lastAi.status, lastAi.source, lastAi.retrievalMode) : null;
  const hasQueried = messages.length > 0;

  return (
    <div className="container ai-page animate-fade-in">
      <header className="ai-hero">
        <h1>
          <Sparkles className="ai-hero-icon" size={28} aria-hidden="true" />
          <span>{t('ai_title')}</span>
        </h1>
        <p className="text-muted">{t('ai_subtitle')}</p>
      </header>

      <div className="ai-layout">
        <section className="ai-chat" aria-label={t('ai_title')}>
          <div className="ai-chat-head">
            <div className="ai-status-pill" data-testid="rag-grounding-indicator" role="status">
              {loading ? (
                <>
                  <span className="ai-status-dot is-busy" />
                  <span>{t('ai_streaming')}</span>
                </>
              ) : lastAi?.error ? (
                <>
                  <span className="ai-status-dot is-error" />
                  <span>{t('ai_error_title')}</span>
                </>
              ) : referencedBooks.length > 0 ? (
                <>
                  <span className="ai-status-dot is-ok" />
                  <span>{t('ai_grounded', { count: referencedBooks.length })}</span>
                </>
              ) : hasQueried && lastSource ? (
                <>
                  <span className="ai-status-dot" />
                  <span>{t('ai_general')}</span>
                </>
              ) : (
                <>
                  <span className="ai-status-dot is-ok" />
                  <span>{t('ai_ready')}</span>
                </>
              )}
            </div>
            {hasQueried && (
              <button type="button" className="ai-ghost-btn" onClick={startNewChat} disabled={loading}>
                <Plus size={14} aria-hidden="true" /> {t('ai_new_chat')}
              </button>
            )}
          </div>

          <div className="ai-messages" ref={scrollRef} onScroll={onScroll} role="log" aria-live="polite" aria-relevant="additions">
            {messages.length === 0 ? (
              <div className="ai-empty">
                <div className="ai-empty-icon" aria-hidden="true">
                  <Sparkles size={26} />
                </div>
                <p>{t('ai_suggestion_prompt')}</p>
                <div className="ai-suggestions">
                  {suggestions.map((suggestion) => (
                    <button key={suggestion} type="button" className="ai-suggestion" onClick={() => handleSend(suggestion)}>
                      {suggestion}
                    </button>
                  ))}
                </div>
              </div>
            ) : (
              messages.map((msg) => <MessageBubble key={msg.id} msg={msg} t={t} />)
            )}
          </div>

          {lastQueryFailed && !loading && (
            <button type="button" onClick={() => handleSend(lastUserMessage)} className="btn btn-outline ai-retry">
              <RefreshCw size={14} aria-hidden="true" />
              <span>{translate(lang, 'retry')}</span>
            </button>
          )}

          <form onSubmit={handleSubmit} className="ai-composer">
            <label htmlFor="ai-discovery-query-input" className="sr-only">
              {t('ai_input_placeholder')}
            </label>
            <textarea
              id="ai-discovery-query-input"
              ref={inputRef}
              rows={1}
              value={query}
              maxLength={1000}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={onKeyDown}
              placeholder={t('ai_input_placeholder')}
              disabled={loading}
            />
            {loading ? (
              <button
                type="button"
                onClick={handleStopStream}
                className="ai-send-btn is-stop"
                title={t('ai_stop_label')}
                aria-label={t('ai_stop')}
              >
                <Square size={14} fill="currentColor" aria-hidden="true" />
              </button>
            ) : (
              <button type="submit" className="ai-send-btn" disabled={!query.trim()} aria-label={translate(lang, 'search')}>
                <Send size={16} aria-hidden="true" />
              </button>
            )}
          </form>
        </section>

        <AiActivityPanel
          conversations={conversations}
          activeId={activeId}
          onSelect={openConversation}
          onDelete={deleteConversation}
          onNewChat={startNewChat}
          canStartNew={!loading && hasQueried}
        />
      </div>

      {hasQueried && !loading && !lastAi?.error && (
        referencedBooks.length > 0 ? (
          <section className="ai-books animate-fade-in" data-testid="referenced-books-section">
            <h2>
              <BookOpen size={20} aria-hidden="true" />
              <span>{t('ai_referenced_books')}</span>
            </h2>
            <div className="grid-books">
              {referencedBooks.map((book) => (
                <BookCard key={book.isbn13 || book.title} book={book} />
              ))}
            </div>
          </section>
        ) : lastSource && lastSource.kind !== 'action' ? (
          <div className="ai-books-empty animate-fade-in" data-testid="no-referenced-books">
            <BookOpen size={30} aria-hidden="true" />
            <h2>{t('ai_no_referenced_books')}</h2>
            <p className="text-muted">{t('ai_no_referenced_desc')}</p>
          </div>
        ) : null
      )}
    </div>
  );
}
