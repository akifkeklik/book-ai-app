'use client';

import { useState, useEffect, useTransition } from 'react';
import { usePreferences } from '@/components/PreferencesProvider';
import { useAuth } from '@/components/AuthProvider';
import {
  createNote,
  updateNote,
  deleteNote,
  getBookNotes,
} from '@/app/actions/notes';
import type { LearningNote, NoteType } from '@/types';
import { NotesExportModal } from './NotesExportModal';
import {
  PenTool,
  Sparkles,
  HelpCircle,
  FileText,
  Trash2,
  Edit2,
  X,
  AlertCircle,
  Plus,
  Lock,
  Download,
} from 'lucide-react';
import Link from 'next/link';

interface BookNotesWidgetProps {
  bookId: string;
  initialNotes?: LearningNote[];
  isAuthenticated?: boolean;
}

export default function BookNotesWidget({
  bookId,
  initialNotes = [],
  isAuthenticated: initialAuth = false,
}: BookNotesWidgetProps) {
  const { t } = usePreferences();
  const { user, loading: authLoading } = useAuth();
  const [notes, setNotes] = useState<LearningNote[]>(initialNotes);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isAdding, setIsAdding] = useState(false);
  const [newType, setNewType] = useState<NoteType>('personal_note');
  const [newContent, setNewContent] = useState('');
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editContent, setEditContent] = useState('');
  const [editType, setEditType] = useState<NoteType>('personal_note');
  const [submitting, setSubmitting] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [isExportModalOpen, setIsExportModalOpen] = useState(false);
  const [, startTransition] = useTransition();

  const isUserAuthenticated = initialAuth || (!!user && !authLoading);

  // Fetch verified notes on mount or auth change
  useEffect(() => {
    let ignore = false;
    if (isUserAuthenticated) {
      startTransition(() => {
        setLoading(true);
      });
      getBookNotes(bookId)
        .then((res) => {
          if (!ignore && res.success) {
            setNotes(res.notes);
            setError(null);
          }
        })
        .catch(() => {
          if (!ignore) {
            setError('Failed to load learning notes');
          }
        })
        .finally(() => {
          if (!ignore) setLoading(false);
        });
    } else {
      startTransition(() => {
        setNotes([]);
        setLoading(false);
      });
    }
    return () => {
      ignore = true;
    };
  }, [bookId, isUserAuthenticated]);

  const handleCreate = async () => {
    if (!newContent.trim()) return;
    setSubmitting(true);
    setError(null);

    const tempId = `temp-${Date.now()}`;
    const optimisticNote: LearningNote = {
      id: tempId,
      userId: user?.id || 'temp',
      bookId,
      noteType: newType,
      content: newContent.trim(),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    // Optimistic UI insert
    setNotes((prev) => [optimisticNote, ...prev]);
    const previousContent = newContent;
    setNewContent('');
    setIsAdding(false);

    try {
      const res = await createNote(bookId, newType, previousContent.trim());
      if (res.success && res.note) {
        setNotes((prev) => prev.map((n) => (n.id === tempId ? res.note! : n)));
      } else {
        // Rollback
        setNotes((prev) => prev.filter((n) => n.id !== tempId));
        setNewContent(previousContent);
        setIsAdding(true);
        setError(res.error || 'Failed to save note');
      }
    } catch {
      setNotes((prev) => prev.filter((n) => n.id !== tempId));
      setNewContent(previousContent);
      setIsAdding(true);
      setError('A network error occurred while saving your note');
    } finally {
      setSubmitting(false);
    }
  };

  const handleStartEdit = (note: LearningNote) => {
    setEditingId(note.id);
    setEditContent(note.content);
    setEditType(note.noteType);
  };

  const handleCancelEdit = () => {
    setEditingId(null);
    setEditContent('');
  };

  const handleSaveEdit = async (noteId: string) => {
    if (!editContent.trim()) return;
    setSubmitting(true);
    setError(null);

    const prevNote = notes.find((n) => n.id === noteId);
    if (!prevNote) return;

    // Optimistic update
    setNotes((prev) =>
      prev.map((n) =>
        n.id === noteId
          ? { ...n, content: editContent.trim(), noteType: editType, updatedAt: new Date().toISOString() }
          : n
      )
    );
    setEditingId(null);

    try {
      const res = await updateNote(noteId, editContent.trim(), editType);
      if (res.success && res.note) {
        setNotes((prev) => prev.map((n) => (n.id === noteId ? res.note! : n)));
      } else {
        // Rollback
        setNotes((prev) => prev.map((n) => (n.id === noteId ? prevNote : n)));
        setError(res.error || 'Failed to update note');
      }
    } catch {
      setNotes((prev) => prev.map((n) => (n.id === noteId ? prevNote : n)));
      setError('A network error occurred while updating your note');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDelete = async (noteId: string) => {
    setDeletingId(noteId);
    setError(null);

    const prevNote = notes.find((n) => n.id === noteId);
    if (!prevNote) return;

    // Optimistic removal
    setNotes((prev) => prev.filter((n) => n.id !== noteId));

    try {
      const res = await deleteNote(noteId, bookId);
      if (!res.success) {
        // Rollback
        setNotes((prev) => [prevNote, ...prev]);
        setError(res.error || 'Failed to delete note');
      }
    } catch {
      setNotes((prev) => [prevNote, ...prev]);
      setError('A network error occurred while deleting your note');
    } finally {
      setDeletingId(null);
    }
  };

  const getTypeBadge = (type: NoteType) => {
    switch (type) {
      case 'key_takeaway':
        return {
          icon: <Sparkles size={13} />,
          label: t('note_type_takeaway'),
          bg: 'rgba(245, 158, 11, 0.15)',
          border: 'rgba(245, 158, 11, 0.3)',
          color: '#fbbf24',
        };
      case 'question':
        return {
          icon: <HelpCircle size={13} />,
          label: t('note_type_question'),
          bg: 'rgba(16, 185, 129, 0.15)',
          border: 'rgba(16, 185, 129, 0.3)',
          color: '#34d399',
        };
      case 'personal_note':
      default:
        return {
          icon: <FileText size={13} />,
          label: t('note_type_personal'),
          bg: 'rgba(139, 92, 246, 0.15)',
          border: 'rgba(139, 92, 246, 0.3)',
          color: 'var(--accent, #a78bfa)',
        };
    }
  };

  return (
    <section
      aria-labelledby="learning-notes-heading"
      className="learning-notes-widget"
      style={{
        marginTop: '2.5rem',
        paddingTop: '2rem',
        borderTop: '1px solid rgba(255, 255, 255, 0.1)',
      }}
    >
      {/* Header */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          flexWrap: 'wrap',
          gap: '1rem',
          marginBottom: '1.25rem',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
          <div
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: '36px',
              height: '36px',
              borderRadius: '10px',
              background: 'rgba(139, 92, 246, 0.18)',
              color: 'var(--accent, #a78bfa)',
            }}
          >
            <PenTool size={18} />
          </div>
          <div>
            <h2
              id="learning-notes-heading"
              style={{ fontSize: '1.25rem', fontWeight: 700, margin: 0, lineHeight: 1.2 }}
            >
              {t('notes_title')}
            </h2>
            <p className="text-muted" style={{ fontSize: '0.85rem', margin: 0, marginTop: '2px' }}>
              {t('notes_subtitle')}
            </p>
          </div>
        </div>

        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
          {isUserAuthenticated && notes.length > 0 && (
            <button
              type="button"
              onClick={() => setIsExportModalOpen(true)}
              className="btn btn-outline"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: '0.4rem',
                padding: '0.45rem 0.85rem',
                fontSize: '0.85rem',
              }}
              title={t('export_notes')}
              aria-label={t('export_notes')}
            >
              <Download size={15} />
              <span>{t('export_notes')}</span>
            </button>
          )}

          {isUserAuthenticated && !isAdding && (
            <button
              type="button"
              onClick={() => setIsAdding(true)}
              className="btn btn-primary"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: '0.5rem',
                padding: '0.45rem 1rem',
                fontSize: '0.9rem',
              }}
              aria-label={t('add_note')}
            >
              <Plus size={16} />
              <span>{t('add_note')}</span>
            </button>
          )}
        </div>
      </div>

      {/* Error Alert */}
      {error && (
        <div
          role="alert"
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '0.75rem',
            padding: '0.85rem 1rem',
            borderRadius: '10px',
            background: 'rgba(239, 68, 68, 0.15)',
            border: '1px solid rgba(239, 68, 68, 0.3)',
            color: '#f87171',
            marginBottom: '1rem',
            fontSize: '0.9rem',
          }}
        >
          <AlertCircle size={18} />
          <span style={{ flex: 1 }}>{error}</span>
          <button
            type="button"
            onClick={() => setError(null)}
            style={{ background: 'none', border: 'none', color: 'inherit', cursor: 'pointer' }}
            aria-label="Dismiss error"
          >
            <X size={16} />
          </button>
        </div>
      )}

      {/* Unauthenticated State */}
      {!isUserAuthenticated && (
        <div
          style={{
            padding: '1.5rem',
            borderRadius: '12px',
            background: 'rgba(255, 255, 255, 0.04)',
            border: '1px solid rgba(255, 255, 255, 0.08)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: '1rem',
            flexWrap: 'wrap',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
            <Lock size={18} color="var(--muted)" />
            <span style={{ fontSize: '0.95rem', color: 'rgba(255, 255, 255, 0.8)' }}>
              {t('sign_in_to_add_notes')}
            </span>
          </div>
          <Link
            href={`/login?redirect=/book/${encodeURIComponent(bookId)}`}
            className="btn btn-primary"
            style={{ fontSize: '0.85rem', padding: '0.4rem 1rem' }}
          >
            {t('nav_login')}
          </Link>
        </div>
      )}

      {/* Add Note Form */}
      {isUserAuthenticated && isAdding && (
        <div
          className="glass-panel"
          style={{
            padding: '1.25rem',
            borderRadius: '12px',
            marginBottom: '1.5rem',
            border: '1px solid rgba(139, 92, 246, 0.3)',
            background: 'rgba(30, 27, 75, 0.25)',
          }}
        >
          {/* Note Type Selector */}
          <div
            role="radiogroup"
            aria-label="Note Type"
            style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', marginBottom: '1rem' }}
          >
            {(['personal_note', 'key_takeaway', 'question'] as NoteType[]).map((type) => {
              const badge = getTypeBadge(type);
              const isSelected = newType === type;
              return (
                <button
                  key={type}
                  type="button"
                  role="radio"
                  aria-checked={isSelected}
                  onClick={() => setNewType(type)}
                  style={{
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: '0.4rem',
                    padding: '0.35rem 0.85rem',
                    borderRadius: '9999px',
                    fontSize: '0.85rem',
                    fontWeight: isSelected ? 600 : 500,
                    cursor: 'pointer',
                    transition: 'all 0.15s ease',
                    background: isSelected ? badge.bg : 'rgba(255, 255, 255, 0.05)',
                    border: `1px solid ${isSelected ? badge.border : 'rgba(255, 255, 255, 0.1)'}`,
                    color: isSelected ? badge.color : 'var(--muted)',
                  }}
                >
                  {badge.icon}
                  <span>{badge.label}</span>
                </button>
              );
            })}
          </div>

          {/* Text Area */}
          <textarea
            value={newContent}
            onChange={(e) => setNewContent(e.target.value)}
            placeholder={t('note_placeholder')}
            rows={4}
            maxLength={5000}
            style={{
              width: '100%',
              padding: '0.75rem',
              borderRadius: '8px',
              background: 'rgba(0, 0, 0, 0.25)',
              border: '1px solid rgba(255, 255, 255, 0.15)',
              color: '#fff',
              fontSize: '0.95rem',
              lineHeight: 1.5,
              resize: 'vertical',
              outline: 'none',
              fontFamily: 'inherit',
            }}
          />

          {/* Form Actions */}
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              marginTop: '0.75rem',
              flexWrap: 'wrap',
              gap: '0.5rem',
            }}
          >
            <span style={{ fontSize: '0.8rem', color: 'var(--muted)' }}>
              {newContent.length} / 5000
            </span>
            <div style={{ display: 'flex', gap: '0.5rem' }}>
              <button
                type="button"
                onClick={() => {
                  setIsAdding(false);
                  setNewContent('');
                }}
                className="btn"
                style={{
                  background: 'rgba(255, 255, 255, 0.08)',
                  padding: '0.4rem 0.9rem',
                  fontSize: '0.85rem',
                }}
              >
                {t('cancel')}
              </button>
              <button
                type="button"
                disabled={!newContent.trim() || submitting}
                onClick={handleCreate}
                className="btn btn-primary"
                style={{
                  padding: '0.4rem 1rem',
                  fontSize: '0.85rem',
                  opacity: !newContent.trim() || submitting ? 0.6 : 1,
                }}
              >
                {submitting ? t('loading') : t('save_note')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Loading Skeleton */}
      {loading && notes.length === 0 && (
        <div style={{ padding: '2rem 0', textAlign: 'center', color: 'var(--muted)' }}>
          {t('loading')}
        </div>
      )}

      {/* Empty State */}
      {!loading && isUserAuthenticated && notes.length === 0 && !isAdding && (
        <div
          style={{
            padding: '2rem 1.5rem',
            textAlign: 'center',
            borderRadius: '12px',
            background: 'rgba(255, 255, 255, 0.02)',
            border: '1px dashed rgba(255, 255, 255, 0.12)',
          }}
        >
          <FileText size={32} color="var(--muted)" style={{ margin: '0 auto 0.75rem' }} />
          <p style={{ color: 'var(--muted)', fontSize: '0.95rem', margin: 0, marginBottom: '1rem' }}>
            {t('empty_notes_book')}
          </p>
          <button
            type="button"
            onClick={() => setIsAdding(true)}
            className="btn btn-primary"
            style={{ fontSize: '0.85rem', padding: '0.4rem 1rem' }}
          >
            {t('add_note')}
          </button>
        </div>
      )}

      {/* Notes List */}
      {notes.length > 0 && (
        <div
          role="list"
          aria-label="Notes list"
          style={{ display: 'flex', flexDirection: 'column', gap: '0.85rem' }}
        >
          {notes.map((note) => {
            const badge = getTypeBadge(note.noteType);
            const isEditing = editingId === note.id;
            const isDeleting = deletingId === note.id;

            if (isEditing) {
              return (
                <div
                  key={note.id}
                  className="glass-panel"
                  style={{
                    padding: '1.25rem',
                    borderRadius: '12px',
                    border: '1px solid rgba(139, 92, 246, 0.3)',
                    background: 'rgba(30, 27, 75, 0.25)',
                  }}
                >
                  <div
                    role="radiogroup"
                    style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', marginBottom: '0.75rem' }}
                  >
                    {(['personal_note', 'key_takeaway', 'question'] as NoteType[]).map((type) => {
                      const b = getTypeBadge(type);
                      const isSel = editType === type;
                      return (
                        <button
                          key={type}
                          type="button"
                          onClick={() => setEditType(type)}
                          style={{
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: '0.35rem',
                            padding: '0.25rem 0.7rem',
                            borderRadius: '9999px',
                            fontSize: '0.8rem',
                            cursor: 'pointer',
                            background: isSel ? b.bg : 'rgba(255, 255, 255, 0.05)',
                            border: `1px solid ${isSel ? b.border : 'rgba(255, 255, 255, 0.1)'}`,
                            color: isSel ? b.color : 'var(--muted)',
                          }}
                        >
                          {b.icon}
                          <span>{b.label}</span>
                        </button>
                      );
                    })}
                  </div>
                  <textarea
                    value={editContent}
                    onChange={(e) => setEditContent(e.target.value)}
                    rows={3}
                    maxLength={5000}
                    style={{
                      width: '100%',
                      padding: '0.75rem',
                      borderRadius: '8px',
                      background: 'rgba(0, 0, 0, 0.25)',
                      border: '1px solid rgba(255, 255, 255, 0.15)',
                      color: '#fff',
                      fontSize: '0.95rem',
                      lineHeight: 1.5,
                      resize: 'vertical',
                      outline: 'none',
                      fontFamily: 'inherit',
                    }}
                  />
                  <div
                    style={{
                      display: 'flex',
                      justifyContent: 'flex-end',
                      gap: '0.5rem',
                      marginTop: '0.5rem',
                    }}
                  >
                    <button
                      type="button"
                      onClick={handleCancelEdit}
                      className="btn"
                      style={{
                        background: 'rgba(255, 255, 255, 0.08)',
                        padding: '0.35rem 0.8rem',
                        fontSize: '0.85rem',
                      }}
                    >
                      {t('cancel')}
                    </button>
                    <button
                      type="button"
                      disabled={!editContent.trim() || submitting}
                      onClick={() => handleSaveEdit(note.id)}
                      className="btn btn-primary"
                      style={{ padding: '0.35rem 0.9rem', fontSize: '0.85rem' }}
                    >
                      {submitting ? t('loading') : t('save_note')}
                    </button>
                  </div>
                </div>
              );
            }

            return (
              <article
                key={note.id}
                role="listitem"
                className="glass-panel animate-fade-in"
                style={{
                  padding: '1rem 1.25rem',
                  borderRadius: '12px',
                  border: '1px solid rgba(255, 255, 255, 0.08)',
                  background: 'rgba(255, 255, 255, 0.03)',
                  opacity: isDeleting ? 0.5 : 1,
                  transition: 'all 0.2s ease',
                }}
              >
                {/* Note Top Bar */}
                <div
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    marginBottom: '0.5rem',
                    gap: '0.5rem',
                  }}
                >
                  <span
                    style={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '0.35rem',
                      padding: '0.2rem 0.65rem',
                      borderRadius: '9999px',
                      fontSize: '0.78rem',
                      fontWeight: 600,
                      background: badge.bg,
                      border: `1px solid ${badge.border}`,
                      color: badge.color,
                    }}
                  >
                    {badge.icon}
                    <span>{badge.label}</span>
                  </span>

                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                    <span style={{ fontSize: '0.78rem', color: 'var(--muted)' }}>
                      {new Date(note.createdAt).toLocaleDateString(undefined, {
                        month: 'short',
                        day: 'numeric',
                        year: 'numeric',
                      })}
                    </span>
                    <button
                      type="button"
                      onClick={() => handleStartEdit(note)}
                      style={{
                        background: 'none',
                        border: 'none',
                        color: 'var(--muted)',
                        cursor: 'pointer',
                        padding: '4px',
                        display: 'inline-flex',
                        alignItems: 'center',
                      }}
                      title={t('edit_note')}
                      aria-label={`${t('edit_note')}: ${note.content.substring(0, 30)}`}
                    >
                      <Edit2 size={14} />
                    </button>
                    <button
                      type="button"
                      onClick={() => handleDelete(note.id)}
                      style={{
                        background: 'none',
                        border: 'none',
                        color: 'var(--danger, #ef4444)',
                        cursor: 'pointer',
                        padding: '4px',
                        display: 'inline-flex',
                        alignItems: 'center',
                      }}
                      title={t('delete_note')}
                      aria-label={`${t('delete_note')}: ${note.content.substring(0, 30)}`}
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>

                {/* Note Content */}
                <p
                  style={{
                    margin: 0,
                    fontSize: '0.95rem',
                    lineHeight: 1.6,
                    color: 'rgba(255, 255, 255, 0.9)',
                    whiteSpace: 'pre-wrap',
                    wordBreak: 'break-word',
                  }}
                >
                  {note.content}
                </p>
              </article>
            );
          })}
        </div>
      )}

      {/* Export Notes Modal */}
      <NotesExportModal
        isOpen={isExportModalOpen}
        onClose={() => setIsExportModalOpen(false)}
        bookId={bookId}
      />
    </section>
  );
}

