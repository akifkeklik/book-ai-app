'use client';

import { useState } from 'react';
import Link from 'next/link';
import { BookPlus } from 'lucide-react';
import { usePreferences } from '@/components/PreferencesProvider';
import { useAuth } from '@/components/AuthProvider';
import { AddBookModal } from '@/components/AddBookModal';

/** "Can't find your book? Add it" — opens the add-a-book modal, or sends guests to log in first. */
export function AddBookButton({ initialQuery = '', variant = 'outline' }: { initialQuery?: string; variant?: 'outline' | 'primary' }) {
  const { t } = usePreferences();
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const className = `btn ${variant === 'primary' ? 'btn-primary' : 'btn-outline'} filter-chip`;

  if (!user) {
    return (
      <Link href="/login?redirect=/catalog" className={className} data-testid="add-book-button" style={{ gap: '0.4rem' }}>
        <BookPlus size={16} aria-hidden="true" /> {t('add_book_cta')}
      </Link>
    );
  }
  return (
    <>
      <button type="button" className={className} data-testid="add-book-button" onClick={() => setOpen(true)} style={{ gap: '0.4rem' }}>
        <BookPlus size={16} aria-hidden="true" /> {t('add_book_cta')}
      </button>
      <AddBookModal open={open} onClose={() => setOpen(false)} initialQuery={initialQuery} />
    </>
  );
}
