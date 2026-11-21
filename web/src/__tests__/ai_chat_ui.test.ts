import test from 'node:test';
import assert from 'node:assert/strict';
import {
  contextIsbnsFor,
  describeAnswerSource,
  parseMarkdown,
  parseInline,
  parseConversations,
  upsertConversation,
  conversationTitle,
  buildActivityFeed,
  MAX_CONVERSATIONS,
  type Conversation,
} from '../lib/ai_chat';
import type { LearningNote, LibraryItem } from '../types';

// ── Honest answer-source labels ─────────────────────────────────────────────

test('only a successful rag_llm answer is labelled as Gemini', () => {
  assert.equal(describeAnswerSource('success', 'rag_llm', 'semantic').kind, 'gemini');
  // A deterministic catalog hit also reports status "success" — it must not claim Gemini.
  assert.equal(describeAnswerSource('success', 'deterministic_catalog_hit').kind, 'catalog');
  assert.equal(describeAnswerSource('success', 'deterministic_author_hit').kind, 'catalog');
  assert.equal(describeAnswerSource('success', null).kind, 'catalog');
  assert.equal(describeAnswerSource('success', undefined).kind, 'catalog');
});

test('LLM failure, actions, empty retrieval and auth guard get their own labels', () => {
  assert.equal(describeAnswerSource('llm_fallback', 'rag_llm').kind, 'fallback');
  assert.equal(describeAnswerSource('popular_fallback', 'curated_anonymous_rec').kind, 'fallback');
  assert.equal(describeAnswerSource('action_executed', 'deterministic_action').kind, 'action');
  assert.equal(describeAnswerSource('empty_retrieval', 'empty_retrieval').kind, 'empty');
  assert.equal(describeAnswerSource('no_match', 'deterministic_catalog_miss').kind, 'empty');
  assert.equal(describeAnswerSource('auth_required', 'auth_guard').kind, 'auth');
  assert.equal(describeAnswerSource('success', 'cache_hit').kind, 'cache');
});

test('degraded retrieval is flagged; healthy semantic retrieval is not', () => {
  assert.equal(describeAnswerSource('lexical_fallback', 'rag_llm', 'lexical_fallback').degraded, true);
  assert.equal(describeAnswerSource('success', 'rag_llm', 'semantic').degraded, false);
  assert.equal(describeAnswerSource('success', 'rag_llm', null).degraded, false);
});

// ── Markdown ────────────────────────────────────────────────────────────────

test('markdown: paragraphs, lists, headings, quotes and inline formatting', () => {
  const blocks = parseMarkdown('## Picks\n\nTry **Dune** and *Hyperion*.\n\n- One `code`\n- Two\n\n1. First\n2. Second\n\n> quoted');
  assert.deepEqual(blocks.map((b) => b.type), ['heading', 'paragraph', 'list', 'list', 'quote']);
  const ul = blocks[2];
  const ol = blocks[3];
  assert.ok(ul.type === 'list' && !ul.ordered && ul.items.length === 2);
  assert.ok(ol.type === 'list' && ol.ordered && ol.items.length === 2);
  assert.deepEqual(parseInline('a **b** c').map((n) => n.type), ['text', 'strong', 'text']);
  assert.deepEqual(parseInline('use `x*y*z` here').map((n) => n.type), ['text', 'code', 'text']);
});

test('markdown: fenced code keeps its text verbatim, including an unterminated fence mid-stream', () => {
  const [code] = parseMarkdown('```python\nprint("**not bold**")\n```');
  assert.ok(code.type === 'code' && code.lang === 'python' && code.text === 'print("**not bold**")');
  const partial = parseMarkdown('Here:\n```\nline one');
  assert.equal(partial[1].type, 'code');
});

test('markdown: HTML in model output stays literal text (never parsed as markup)', () => {
  const [p] = parseMarkdown('<img src=x onerror=alert(1)> hello');
  assert.ok(p.type === 'paragraph');
  assert.deepEqual(p.children, [{ type: 'text', text: '<img src=x onerror=alert(1)> hello' }]);
});

test('markdown: plain prose without markdown is one paragraph per blank-line block', () => {
  const blocks = parseMarkdown('First line\nsecond line\n\nNext para');
  assert.equal(blocks.length, 2);
});

// ── Conversation history ────────────────────────────────────────────────────

const conv = (id: string, updatedAt: string, content = 'hi'): Conversation => ({
  id, title: content, createdAt: updatedAt, updatedAt,
  messages: [{ id: `${id}-u`, role: 'user', content }, { id: `${id}-a`, role: 'ai', content: 'answer', status: 'success' }],
});

test('history: corrupt storage entries are dropped, valid ones sorted newest first', () => {
  const parsed = parseConversations([
    conv('a', '2026-01-01T00:00:00Z'),
    { id: 'bad' },
    null,
    'x',
    { id: 'empty', updatedAt: '2026-01-02T00:00:00Z', messages: [{ role: 'robot' }] },
    conv('b', '2026-03-01T00:00:00Z'),
  ]);
  assert.deepEqual(parsed.map((c) => c.id), ['b', 'a']);
  assert.deepEqual(parseConversations('nope'), []);
  assert.deepEqual(parseConversations(null), []);
});

test('history: upsert replaces in place, moves to the top, drops empty AI placeholders and caps the list', () => {
  let list: Conversation[] = [];
  for (let i = 0; i < MAX_CONVERSATIONS + 5; i++) list = upsertConversation(list, conv(`c${i}`, `2026-01-01T00:00:${String(i).padStart(2, '0')}Z`));
  assert.equal(list.length, MAX_CONVERSATIONS);
  assert.equal(list[0].id, `c${MAX_CONVERSATIONS + 4}`);

  const updated = { ...conv('c10', '2026-02-01T00:00:00Z', 'again') };
  updated.messages = [...updated.messages, { id: 'pending', role: 'ai', content: '' }];
  list = upsertConversation(list, updated);
  assert.equal(list[0].id, 'c10');
  assert.equal(list.filter((c) => c.id === 'c10').length, 1);
  assert.ok(!list[0].messages.some((m) => m.id === 'pending'));
});

test('history: titles are single-line and bounded', () => {
  assert.equal(conversationTitle('  Books\nlike   Dune  '), 'Books like Dune');
  assert.ok(conversationTitle('x'.repeat(200)).length <= 60);
});

// ── Recent activity ─────────────────────────────────────────────────────────

const book = (isbn13: string, title: string) => ({ isbn13, title } as LibraryItem['book']);

test('activity feed merges library additions and notes newest first and skips entries without a timestamp', () => {
  const library: LibraryItem[] = [
    { id: '1', bookId: '111', status: 'reading', addedAt: '2026-05-01T10:00:00Z', book: book('111', 'Dune') },
    { id: '2', bookId: '222', status: 'favorite', addedAt: '', book: book('222', 'No Timestamp') },
  ];
  const notes: LearningNote[] = [
    { id: 'n1', userId: 'u', bookId: '111', noteType: 'key_takeaway', content: 'Spice must flow', createdAt: '2026-05-03T10:00:00Z', updatedAt: '2026-05-03T10:00:00Z' } as LearningNote,
  ];
  const feed = buildActivityFeed(library, notes);
  assert.deepEqual(feed.map((e) => e.id), ['note-n1', 'lib-1']);
  assert.equal(feed[0].bookTitle, 'Dune'); // resolved from the library for a note
  assert.ok(!feed.some((e) => e.bookTitle === 'No Timestamp'));
});

test('activity feed with no data is empty (the UI shows an empty state, not invented items)', () => {
  assert.deepEqual(buildActivityFeed([], []), []);
});

// ── Follow-up context ───────────────────────────────────────────────────────
// Live report: "1984 kitabı var mı?" -> answered; "nasıl bir kitap bu?" -> the backend never knew
// which book "bu" meant. The client now sends the books of the latest successful answer.

const ctxBook = (isbn13: string) => ({ isbn13, title: isbn13, authors: 'A' }) as never;

test('follow-up context: the books of the latest successful answer, deduplicated, at most five', () => {
  const messages = [
    { id: 'u1', role: 'user' as const, content: '1984 kitabı var mı?' },
    { id: 'a1', role: 'ai' as const, content: 'Evet', referencedBooks: [ctxBook('9780451524935'), ctxBook('9780451524935')] },
    { id: 'u2', role: 'user' as const, content: 'nasıl bir kitap bu?' },
  ];
  assert.deepEqual(contextIsbnsFor(messages), ['9780451524935']);
  const many = [{ id: 'a', role: 'ai' as const, content: 'x', referencedBooks: ['1', '2', '3', '4', '5', '6', '7'].map(ctxBook) }];
  assert.equal(contextIsbnsFor(many).length, 5);
});

test('follow-up context: failed answers and empty histories give no context', () => {
  assert.deepEqual(contextIsbnsFor([]), []);
  const messages = [
    { id: 'a1', role: 'ai' as const, content: 'ok', referencedBooks: [ctxBook('9780000000001')] },
    { id: 'a2', role: 'ai' as const, content: 'error', error: true, referencedBooks: [ctxBook('9780000000002')] },
  ];
  // The failed answer is skipped; the last successful one is used.
  assert.deepEqual(contextIsbnsFor(messages), ['9780000000001']);
});
