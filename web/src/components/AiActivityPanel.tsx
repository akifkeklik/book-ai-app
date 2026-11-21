'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { History, MessageSquare, Trash2, Bookmark, StickyNote, AlertCircle, Plus } from 'lucide-react';
import { useAuth } from './AuthProvider';
import { usePreferences } from './PreferencesProvider';
import { getLibraryBooks } from '@/app/actions/library';
import { getAllUserNotes } from '@/app/actions/notes';
import { buildActivityFeed, formatRelativeTime, type ActivityEntry, type Conversation } from '@/lib/ai_chat';

interface AiActivityPanelProps {
  conversations: Conversation[];
  activeId: string | null;
  onSelect: (conversation: Conversation) => void;
  onDelete: (id: string) => void;
  onNewChat: () => void;
  canStartNew: boolean;
}

type FeedState =
  | { phase: 'loading' }
  | { phase: 'ready'; entries: ActivityEntry[] }
  | { phase: 'error' };

/** Library additions and notes from the backend for the signed-in user. */
function RecentActivity({ userId }: { userId: string }) {
  const { t, preferences } = usePreferences();
  const [state, setState] = useState<FeedState>({ phase: 'loading' });

  useEffect(() => {
    let ignore = false;
    Promise.all([getLibraryBooks(), getAllUserNotes({ limit: 10 })])
      .then(([lib, notes]) => {
        if (ignore) return;
        // Both sources failing means we cannot honestly say "no activity".
        if (!lib.success && !notes.success) {
          setState({ phase: 'error' });
          return;
        }
        setState({
          phase: 'ready',
          entries: buildActivityFeed(lib.success ? lib.items : [], notes.success ? notes.notes : []),
        });
      })
      .catch(() => {
        if (!ignore) setState({ phase: 'error' });
      });
    return () => {
      ignore = true;
    };
  }, [userId]);

  if (state.phase === 'loading') {
    return (
      <ul className="ai-side-list" aria-busy="true">
        {[0, 1, 2].map((i) => (
          <li key={i} className="ai-side-skeleton" />
        ))}
      </ul>
    );
  }
  if (state.phase === 'error') {
    return (
      <p className="ai-side-empty" role="status">
        <AlertCircle size={14} aria-hidden="true" /> {t('ai_activity_error')}
      </p>
    );
  }
  if (!state.entries.length) {
    return <p className="ai-side-empty">{t('ai_activity_empty')}</p>;
  }
  return (
    <ul className="ai-side-list" data-testid="ai-recent-activity">
      {state.entries.map((e) => (
        <li key={e.id}>
          <Link href={`/book/${encodeURIComponent(e.bookId)}`} className="ai-side-item">
            <span className="ai-side-icon" aria-hidden="true">
              {e.kind === 'note' ? <StickyNote size={14} /> : <Bookmark size={14} />}
            </span>
            <span className="ai-side-text">
              <span className="ai-side-title">{e.bookTitle}</span>
              <span className="ai-side-meta">
                {e.kind === 'note' ? `${t('ai_activity_note')} · ${e.detail}` : t('ai_activity_added')}
              </span>
            </span>
            <time className="ai-side-time" dateTime={e.at}>
              {formatRelativeTime(e.at, preferences.language)}
            </time>
          </Link>
        </li>
      ))}
    </ul>
  );
}

export function AiActivityPanel({ conversations, activeId, onSelect, onDelete, onNewChat, canStartNew }: AiActivityPanelProps) {
  const { user, loading } = useAuth();
  const { t, preferences } = usePreferences();

  return (
    <aside className="ai-side" aria-label={t('ai_recent_chats')}>
      <section className="ai-side-card">
        <div className="ai-side-head">
          <h2>
            <MessageSquare size={15} aria-hidden="true" /> {t('ai_recent_chats')}
          </h2>
          <button type="button" className="ai-ghost-btn" onClick={onNewChat} disabled={!canStartNew}>
            <Plus size={14} aria-hidden="true" /> {t('ai_new_chat')}
          </button>
        </div>
        {conversations.length === 0 ? (
          <p className="ai-side-empty">{t('ai_recent_chats_empty')}</p>
        ) : (
          <ul className="ai-side-list" data-testid="ai-recent-chats">
            {conversations.slice(0, 8).map((c) => (
              <li key={c.id} className={`ai-side-row${c.id === activeId ? ' is-active' : ''}`}>
                <button
                  type="button"
                  className="ai-side-item"
                  onClick={() => onSelect(c)}
                  aria-current={c.id === activeId ? 'true' : undefined}
                >
                  <span className="ai-side-text">
                    <span className="ai-side-title">{c.title}</span>
                    <span className="ai-side-meta">
                      {formatRelativeTime(c.updatedAt, preferences.language)}
                    </span>
                  </span>
                </button>
                <button
                  type="button"
                  className="ai-icon-btn"
                  onClick={() => onDelete(c.id)}
                  aria-label={`${t('ai_delete_chat')}: ${c.title}`}
                  title={t('ai_delete_chat')}
                >
                  <Trash2 size={14} aria-hidden="true" />
                </button>
              </li>
            ))}
          </ul>
        )}
        <p className="ai-side-note">{t('ai_history_device_note')}</p>
      </section>

      <section className="ai-side-card">
        <div className="ai-side-head">
          <h2>
            <History size={15} aria-hidden="true" /> {t('ai_recent_activity')}
          </h2>
        </div>
        {loading ? (
          <ul className="ai-side-list" aria-busy="true">
            <li className="ai-side-skeleton" />
          </ul>
        ) : user ? (
          <RecentActivity key={user.id} userId={user.id} />
        ) : (
          <p className="ai-side-empty">
            <Link href="/login?redirect=/ai-discovery" className="ai-inline-link">
              {t('ai_activity_signin')}
            </Link>
          </p>
        )}
      </section>
    </aside>
  );
}
