import { cookies } from 'next/headers';
import { translate } from '@/lib/i18n';
import { resolveLanguage } from '@/lib/preferences';
import { BookDetailSkeleton } from '@/components/Skeleton';

export default async function BookLoading() {
  const lang = resolveLanguage((await cookies()).get('libris_lang')?.value);
  return <BookDetailSkeleton label={translate(lang, 'loading_book_details')} />;
}
