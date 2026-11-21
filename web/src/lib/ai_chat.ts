/**
 * Pure helpers for the AI chat screen: honest answer-source labelling, a small safe Markdown
 * parser, local conversation history and the recent-activity feed. No React, no DOM, so every
 * piece is unit-tested directly.
 */
import type { Book, LearningNote, LibraryItem } from '@/types';
import type { TranslationKey } from './i18n';

// ── Answer source ───────────────────────────────────────────────────────────

export type AnswerSourceKind = 'gemini' | 'catalog' | 'fallback' | 'action' | 'cache' | 'empty' | 'auth';

export interface AnswerSource {
  kind: AnswerSourceKind;
  labelKey: TranslationKey;
  /** True when semantic retrieval was unavailable and a lexical fallback ranked the books. */
  degraded: boolean;
}

const HEALTHY_RETRIEVAL = new Set(['semantic', 'semantic_cached', 'hybrid', undefined, null, '']);

/**
 * Maps the backend's `status` and `metrics.source` to what actually produced the answer.
 * Only `status: success` with `source: rag_llm` is a Gemini-generated answer; a deterministic
 * catalog hit also reports `success`, so the source decides.
 */
export function describeAnswerSource(
  status: string | undefined,
  source?: string | null,
  retrievalMode?: string | null,
): AnswerSource {
  const degraded = !HEALTHY_RETRIEVAL.has(retrievalMode ?? undefined) && retrievalMode !== 'semantic';
  const make = (kind: AnswerSourceKind, labelKey: TranslationKey): AnswerSource => ({ kind, labelKey, degraded });

  if (status === 'llm_fallback') return make('fallback', 'ai_source_fallback');
  if (status === 'popular_fallback') return make('fallback', 'ai_source_fallback');
  if (status === 'action_executed' || source === 'deterministic_action') return make('action', 'ai_source_action');
  if (status === 'auth_required' || source === 'auth_guard') return make('auth', 'ai_source_auth');
  if (status === 'empty_retrieval' || status === 'no_match') return make('empty', 'ai_source_empty');
  if (source === 'cache_hit') return make('cache', 'ai_source_cache');
  if (source === 'rag_llm') return make('gemini', 'ai_source_gemini');
  // Deterministic catalog lookups, clock answers and degraded retrieval without an LLM call.
  return make('catalog', 'ai_source_catalog');
}

// ── Markdown (safe subset, rendered as React elements — never as HTML) ──────

export type InlineNode =
  | { type: 'text'; text: string }
  | { type: 'strong'; children: InlineNode[] }
  | { type: 'em'; children: InlineNode[] }
  | { type: 'code'; text: string };

export type BlockNode =
  | { type: 'paragraph'; children: InlineNode[] }
  | { type: 'heading'; level: 2 | 3 | 4; children: InlineNode[] }
  | { type: 'list'; ordered: boolean; items: InlineNode[][] }
  | { type: 'code'; lang: string; text: string }
  | { type: 'quote'; children: InlineNode[] };

export function parseInline(text: string): InlineNode[] {
  const nodes: InlineNode[] = [];
  // `code`, **strong**, *em* / _em_. Anything unmatched stays literal text.
  const re = /(`[^`\n]+`)|(\*\*[^*\n]+?\*\*)|(\*[^*\s][^*\n]*?\*)|(\b_[^_\n]+_\b)/g;
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) nodes.push({ type: 'text', text: text.slice(last, m.index) });
    const tok = m[0];
    if (m[1]) nodes.push({ type: 'code', text: tok.slice(1, -1) });
    else if (m[2]) nodes.push({ type: 'strong', children: parseInline(tok.slice(2, -2)) });
    else nodes.push({ type: 'em', children: parseInline(tok.slice(1, -1)) });
    last = m.index + tok.length;
  }
  if (last < text.length) nodes.push({ type: 'text', text: text.slice(last) });
  return nodes;
}

const LIST_ITEM = /^\s*(?:([-*•])|(\d+)[.)])\s+(.*)$/;

/**
 * Parses the Markdown subset LLM answers use. An unterminated code fence (mid-stream) is
 * rendered as a code block so streaming text never jumps between layouts.
 */
export function parseMarkdown(source: string): BlockNode[] {
  const lines = source.replace(/\r\n?/g, '\n').split('\n');
  const blocks: BlockNode[] = [];
  let para: string[] = [];

  const flushPara = () => {
    if (para.length) {
      blocks.push({ type: 'paragraph', children: parseInline(para.join('\n')) });
      para = [];
    }
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    const fence = line.match(/^\s*```\s*([\w+-]*)\s*$/);
    if (fence) {
      flushPara();
      const body: string[] = [];
      i++;
      while (i < lines.length && !/^\s*```\s*$/.test(lines[i])) body.push(lines[i++]);
      blocks.push({ type: 'code', lang: fence[1] || '', text: body.join('\n') });
      continue;
    }

    if (!line.trim()) {
      flushPara();
      continue;
    }

    const heading = line.match(/^\s*(#{1,4})\s+(.*)$/);
    if (heading) {
      flushPara();
      const level = Math.min(4, Math.max(2, heading[1].length + 1)) as 2 | 3 | 4;
      blocks.push({ type: 'heading', level, children: parseInline(heading[2].trim()) });
      continue;
    }

    const quote = line.match(/^\s*>\s?(.*)$/);
    if (quote) {
      flushPara();
      blocks.push({ type: 'quote', children: parseInline(quote[1]) });
      continue;
    }

    const item = line.match(LIST_ITEM);
    if (item) {
      flushPara();
      const ordered = Boolean(item[2]);
      const items: InlineNode[][] = [parseInline(item[3])];
      while (i + 1 < lines.length) {
        const next = lines[i + 1].match(LIST_ITEM);
        if (!next || Boolean(next[2]) !== ordered) break;
        items.push(parseInline(next[3]));
        i++;
      }
      blocks.push({ type: 'list', ordered, items });
      continue;
    }

    para.push(line);
  }
  flushPara();
  return blocks;
}

// ── Local conversation history ──────────────────────────────────────────────

export const CHAT_HISTORY_KEY = 'libris_ai_conversations_v1';
export const MAX_CONVERSATIONS = 20;
export const MAX_MESSAGES_PER_CONVERSATION = 40;
const MAX_BOOKS_PER_MESSAGE = 8;

export interface StoredMessage {
  id: string;
  role: 'user' | 'ai';
  content: string;
  error?: boolean;
  status?: string;
  source?: string | null;
  retrievalMode?: string | null;
  actionBadge?: string;
  referencedBooks?: Book[];
}

/**
 * ISBNs of the books shown in the latest successful assistant answer, so a follow-up such as
 * "tell me more about it" can refer to them. Failed answers are skipped; at most five, as the
 * backend accepts.
 */
export function contextIsbnsFor(messages: StoredMessage[]): string[] {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m.role !== 'ai' || m.error) continue;
    const isbns = (m.referencedBooks ?? []).map((b) => b.isbn13).filter((v): v is string => !!v);
    if (isbns.length) return Array.from(new Set(isbns)).slice(0, 5);
  }
  return [];
}

export interface Conversation {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  messages: StoredMessage[];
}

function isStoredMessage(m: unknown): m is StoredMessage {
  if (!m || typeof m !== 'object') return false;
  const r = m as Record<string, unknown>;
  return typeof r.id === 'string' && (r.role === 'user' || r.role === 'ai') && typeof r.content === 'string';
}

/** Validates untrusted JSON from storage; corrupt entries are dropped, never thrown. */
export function parseConversations(raw: unknown): Conversation[] {
  if (!Array.isArray(raw)) return [];
  const out: Conversation[] = [];
  for (const c of raw) {
    if (!c || typeof c !== 'object') continue;
    const r = c as Record<string, unknown>;
    if (typeof r.id !== 'string' || typeof r.updatedAt !== 'string' || !Array.isArray(r.messages)) continue;
    const messages = r.messages.filter(isStoredMessage);
    if (!messages.length) continue;
    out.push({
      id: r.id,
      title: typeof r.title === 'string' && r.title ? r.title : messages[0].content.slice(0, 80),
      createdAt: typeof r.createdAt === 'string' ? r.createdAt : r.updatedAt,
      updatedAt: r.updatedAt,
      messages,
    });
  }
  return out.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)).slice(0, MAX_CONVERSATIONS);
}

export function newConversationId(): string {
  return `c-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
}

export function conversationTitle(firstUserMessage: string): string {
  const oneLine = firstUserMessage.replace(/\s+/g, ' ').trim();
  return oneLine.length > 60 ? `${oneLine.slice(0, 57)}…` : oneLine;
}

/** Inserts or replaces a conversation, newest first, trimmed to the storage limits. */
export function upsertConversation(list: Conversation[], conv: Conversation): Conversation[] {
  const trimmed: Conversation = {
    ...conv,
    messages: conv.messages
      .filter((m) => !(m.role === 'ai' && !m.content))
      .slice(-MAX_MESSAGES_PER_CONVERSATION)
      .map((m) => (m.referencedBooks ? { ...m, referencedBooks: m.referencedBooks.slice(0, MAX_BOOKS_PER_MESSAGE) } : m)),
  };
  if (!trimmed.messages.length) return list;
  return [trimmed, ...list.filter((c) => c.id !== conv.id)].slice(0, MAX_CONVERSATIONS);
}

export function loadConversations(): Conversation[] {
  try {
    const raw = localStorage.getItem(CHAT_HISTORY_KEY);
    return raw ? parseConversations(JSON.parse(raw)) : [];
  } catch {
    return [];
  }
}

export function saveConversations(list: Conversation[]): void {
  try {
    localStorage.setItem(CHAT_HISTORY_KEY, JSON.stringify(list));
  } catch {
    // Storage full or blocked: history is a convenience, the chat keeps working.
  }
}

// ── Recent activity feed ────────────────────────────────────────────────────

export interface ActivityEntry {
  id: string;
  kind: 'library' | 'note';
  at: string;
  bookId: string;
  bookTitle: string;
  detail: string;
}

/** Merges real library additions and notes into one newest-first feed. */
export function buildActivityFeed(library: LibraryItem[], notes: LearningNote[], limit = 6): ActivityEntry[] {
  const titleById = new Map<string, string>();
  for (const item of library) if (item.book?.title) titleById.set(item.bookId, item.book.title);

  const entries: ActivityEntry[] = [
    ...library
      .filter((i) => i.addedAt && !Number.isNaN(Date.parse(i.addedAt)))
      .map((i) => ({
        id: `lib-${i.id}`,
        kind: 'library' as const,
        at: i.addedAt,
        bookId: i.bookId,
        bookTitle: i.book?.title || i.bookId,
        detail: i.status,
      })),
    ...notes
      .filter((n) => n.createdAt && !Number.isNaN(Date.parse(n.createdAt)))
      .map((n) => ({
        id: `note-${n.id}`,
        kind: 'note' as const,
        at: n.updatedAt && !Number.isNaN(Date.parse(n.updatedAt)) ? n.updatedAt : n.createdAt,
        bookId: n.bookId,
        bookTitle: titleById.get(n.bookId) || n.bookId,
        detail: n.content.length > 80 ? `${n.content.slice(0, 77)}…` : n.content,
      })),
  ];
  return entries.sort((a, b) => Date.parse(b.at) - Date.parse(a.at)).slice(0, limit);
}

/** Compact relative time ("3 min", "2 h", "5 d") using Intl in the UI language. */
export function formatRelativeTime(iso: string, lang: string, now: number = Date.now()): string {
  const diffSec = Math.round((Date.parse(iso) - now) / 1000);
  if (Number.isNaN(diffSec)) return '';
  const abs = Math.abs(diffSec);
  const rtf = new Intl.RelativeTimeFormat(lang, { numeric: 'auto', style: 'short' });
  if (abs < 60) return rtf.format(Math.round(diffSec), 'second');
  if (abs < 3600) return rtf.format(Math.round(diffSec / 60), 'minute');
  if (abs < 86400) return rtf.format(Math.round(diffSec / 3600), 'hour');
  if (abs < 86400 * 30) return rtf.format(Math.round(diffSec / 86400), 'day');
  return new Date(iso).toLocaleDateString(lang);
}
