'use server';

import { createClient } from '@/lib/supabase/server';
import { normalizeBook } from '@/lib/normalizers';
import { ApiService } from '@/lib/api';
import type { Book, LibraryCollectionStatus, LibraryItem } from '@/types';
import { revalidatePath } from 'next/cache';

function safeRevalidatePath(path: string) {
  try {
    revalidatePath(path);
  } catch {
    // Gracefully ignore when executed outside Next.js request lifecycle (e.g. testing)
  }
}

const VALID_STATUSES: readonly LibraryCollectionStatus[] = [
  'favorite',
  'want_to_read',
  'reading',
  'finished',
] as const;

function mapInteractionToStatus(rawType: string): LibraryCollectionStatus | null {
  const normalized = rawType.trim().toLowerCase();
  if (normalized === 'favorite' || normalized === 'like') {
    return 'favorite';
  }
  if (normalized === 'want_to_read') {
    return 'want_to_read';
  }
  if (normalized === 'reading') {
    return 'reading';
  }
  if (normalized === 'finished') {
    return 'finished';
  }
  return null;
}

/**
 * Retrieves the signed-in user's library items across all collections.
 * Scoped strictly to the authenticated identity verified by Supabase Auth.
 */
export async function getLibraryBooks(): Promise<{
  success: boolean;
  items: LibraryItem[];
  error?: string;
}> {
  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return {
        success: false,
        items: [],
        error: 'Unauthorized: Please sign in to view your library',
      };
    }

    // 1. Fetch user interactions (favorites, want_to_read, finished, etc.)
    const { data: interactions, error: interactionsError } = await supabase
      .from('user_interactions')
      .select('book_id, interaction_type, created_at')
      .eq('user_id', user.id)
      .in('interaction_type', ['favorite', 'like', 'want_to_read', 'reading', 'finished'])
      .order('created_at', { ascending: false });

    if (interactionsError) {
      return {
        success: false,
        items: [],
        error: interactionsError.message || 'Failed to fetch library interactions',
      };
    }

    // 2. Fetch mobile favorites table entries for seamless cross-platform syncing
    const { data: mobileFavorites, error: favsError } = await supabase
      .from('favorites')
      .select('book_id, book_title, book_author, book_image_url, added_at')
      .eq('user_id', user.id);

    if (favsError) {
      // Non-fatal if mobile table query fails, continue with interactions
      console.warn('Could not read mobile favorites:', favsError.message);
    }

    // 3. Deduplicate and merge collections by book_id
    // Key: book_id, Value: { status, addedAt, fallbackMeta }
    const bookMap = new Map<
      string,
      {
        status: LibraryCollectionStatus;
        addedAt: string;
        title?: string;
        author?: string;
        thumbnail?: string;
      }
    >();

    // Process interactions first
    if (Array.isArray(interactions)) {
      for (const item of interactions) {
        if (!item.book_id) continue;
        const mappedStatus = mapInteractionToStatus(item.interaction_type);
        if (mappedStatus) {
          bookMap.set(String(item.book_id), {
            status: mappedStatus,
            addedAt: item.created_at || new Date().toISOString(),
          });
        }
      }
    }

    // Merge mobile favorites (any book in favorites is a 'favorite' unless explicitly marked differently)
    if (Array.isArray(mobileFavorites)) {
      for (const fav of mobileFavorites) {
        if (!fav.book_id) continue;
        const id = String(fav.book_id);
        const existing = bookMap.get(id);
        if (!existing) {
          bookMap.set(id, {
            status: 'favorite',
            addedAt: fav.added_at || new Date().toISOString(),
            title: fav.book_title,
            author: fav.book_author,
            thumbnail: fav.book_image_url,
          });
        } else {
          // Enrich fallback metadata if missing
          if (!existing.title && fav.book_title) existing.title = fav.book_title;
          if (!existing.author && fav.book_author) existing.author = fav.book_author;
          if (!existing.thumbnail && fav.book_image_url) existing.thumbnail = fav.book_image_url;
        }
      }
    }

    const uniqueBookIds = Array.from(bookMap.keys());
    if (uniqueBookIds.length === 0) {
      return { success: true, items: [] };
    }

    // 4. Enrich books by querying the books table
    const booksDetailMap = new Map<string, Book>();
    try {
      const { data: booksData } = await supabase
        .from('books')
        .select('*')
        .in('isbn13', uniqueBookIds);

      if (Array.isArray(booksData)) {
        for (const raw of booksData) {
          const normalized = normalizeBook(raw);
          if (normalized.isbn13) {
            booksDetailMap.set(normalized.isbn13, normalized);
          }
        }
      }
    } catch {
      // Fall through to fallback enrichment
    }

    // 5. Construct canonical LibraryItem list with fallback handling
    const libraryItems: LibraryItem[] = [];

    for (const [bookId, entry] of bookMap.entries()) {
      let book = booksDetailMap.get(bookId);

      // If book wasn't found in books table, try fallback or API lookup
      if (!book) {
        try {
          const apiBook = await ApiService.getBookByIsbn(bookId);
          if (apiBook) {
            book = apiBook;
          }
        } catch {
          // Ignore API error and use metadata fallback
        }
      }

      if (!book) {
        book = normalizeBook({
          isbn13: bookId,
          title: entry.title || `Book ${bookId}`,
          authors: entry.author || 'Unknown Author',
          thumbnail: entry.thumbnail || '',
        });
      }

      libraryItems.push({
        id: bookId,
        bookId,
        status: entry.status,
        addedAt: entry.addedAt,
        book,
      });
    }

    // Sort by addedAt descending
    libraryItems.sort((a, b) => new Date(b.addedAt).getTime() - new Date(a.addedAt).getTime());

    return {
      success: true,
      items: libraryItems,
    };
  } catch (error: unknown) {
    return {
      success: false,
      items: [],
      error: error instanceof Error ? error.message : 'Failed to fetch library',
    };
  }
}

/**
 * Removes a book completely from the user's library and collections.
 */
export async function removeLibraryItem(bookId: string): Promise<{
  success: boolean;
  error?: string;
}> {
  if (!bookId || typeof bookId !== 'string') {
    return { success: false, error: 'Invalid book ID' };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    // Delete from user_interactions scoped strictly to auth.uid()
    const { error: deleteInteractionError } = await supabase
      .from('user_interactions')
      .delete()
      .eq('user_id', user.id)
      .eq('book_id', bookId);

    if (deleteInteractionError) {
      return { success: false, error: deleteInteractionError.message };
    }

    // Also delete from mobile favorites table if present
    await supabase
      .from('favorites')
      .delete()
      .eq('user_id', user.id)
      .eq('book_id', bookId);

    safeRevalidatePath('/favorites');
    safeRevalidatePath(`/book/${bookId}`);
    return { success: true };
  } catch (error: unknown) {
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Failed to remove library item',
    };
  }
}

/**
 * Updates a book's collection status (e.g. Favorite, Want to Read, Finished).
 */
export async function updateLibraryItemStatus(
  bookId: string,
  newStatus: LibraryCollectionStatus
): Promise<{
  success: boolean;
  error?: string;
}> {
  if (!bookId || typeof bookId !== 'string') {
    return { success: false, error: 'Invalid book ID' };
  }

  if (!VALID_STATUSES.includes(newStatus)) {
    return { success: false, error: `Invalid collection status: ${newStatus}` };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return { success: false, error: 'Unauthorized' };
    }

    // Upsert into user_interactions
    const { error: upsertError } = await supabase.from('user_interactions').upsert(
      {
        user_id: user.id,
        book_id: bookId,
        interaction_type: newStatus,
        created_at: new Date().toISOString(),
      },
      { onConflict: 'user_id,book_id' }
    );

    if (upsertError) {
      return { success: false, error: upsertError.message };
    }

    // Synchronize favorites table for cross-platform consistency
    if (newStatus === 'favorite') {
      // Ensure mobile table has the entry
      try {
        const { data: bookData } = await supabase
          .from('books')
          .select('title, authors, thumbnail')
          .eq('isbn13', bookId)
          .maybeSingle();

        await supabase.from('favorites').upsert(
          {
            user_id: user.id,
            book_id: bookId,
            book_title: bookData?.title || 'Book',
            book_author: bookData?.authors || 'Unknown Author',
            book_image_url: bookData?.thumbnail || '',
            added_at: new Date().toISOString(),
          },
          { onConflict: 'user_id,book_id' }
        );
      } catch {
        // Non-fatal
      }
    } else {
      // If changed to want_to_read or finished, remove from mobile favorites table
      await supabase
        .from('favorites')
        .delete()
        .eq('user_id', user.id)
        .eq('book_id', bookId);
    }

    safeRevalidatePath('/favorites');
    safeRevalidatePath(`/book/${bookId}`);
    return { success: true };
  } catch (error: unknown) {
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Failed to update item status',
    };
  }
}
