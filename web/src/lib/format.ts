/** Locale-aware number helpers shared by server and client components. */

export function formatCount(value: number, lang: string, compact = false): string {
  if (!Number.isFinite(value)) return '';
  return new Intl.NumberFormat(lang, compact ? { notation: 'compact', maximumFractionDigits: 1 } : {}).format(value);
}

export function formatRating(value: number, lang: string): string {
  if (!Number.isFinite(value)) return '';
  return new Intl.NumberFormat(lang, { minimumFractionDigits: 1, maximumFractionDigits: 1 }).format(value);
}

/** Catalog data stores some years as floats ("2015.0"); show them as plain years. */
export function cleanPublishedDate(raw: string): string {
  const trimmed = raw.trim();
  return /^\d{3,4}\.0+$/.test(trimmed) ? trimmed.split('.')[0] : trimmed;
}
