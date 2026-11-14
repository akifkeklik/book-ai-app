# Libris — Product Brief

## Problem

Readers of non-fiction forget most of a book within weeks. Highlights and notes pile up but are never revisited. Spaced-repetition tools such as Anki work, but every card has to be written by hand, so most readers stop after a few days.

## Who it is for

**Primary user: the deliberate non-fiction reader.** Students, engineers, and other professionals who read 1–4 books a month to learn something they want to use (psychology, business, history, technology), and who already take some notes.

They want to remember the ideas well enough to apply them, without running a second hobby of making flashcards.

Out of scope: readers who read only for entertainment, or who want reading statistics and social features.

## Promise

> Read it once. Remember it for good.

Save a key takeaway while you read. Libris turns it into a recall question at once and asks you again right before you would forget.

## The core loop

1. **Find** a book (catalog, search, AI suggestions).
2. **Capture** a key takeaway on the book page.
3. **See the question immediately.** The AI question appears on save, together with when it will be asked.
4. **Review** when it is due. The schedule widens (1 → 3 → 7 → … days) when you remember and tightens when you struggle.

Everything else (library shelves, recommendations, six languages) exists to support this loop.

## Positioning

| | Writes the questions for you | Schedules reviews | Knows your books |
|---|---|---|---|
| Anki | No | Yes | No |
| Goodreads | — | No | Yes |
| Readwise | Partly (resurfaces highlights) | Yes | Yes |
| **Libris** | **Yes, from your own notes** | **Yes** | **Yes** |

## Success metrics

These are **targets for a first beta, not measured results** — the project is not deployed and has no user data yet.

| Metric | Definition | Beta target |
|---|---|---|
| Activation | New users who save their first takeaway within 7 days | ≥ 40% |
| Core habit | Activated users who complete ≥ 1 review session per week, 4 weeks in a row | ≥ 25% |
| Retention of knowledge | Share of reviews answered "remembered" at stage 3+ (7+ days after capture) | ≥ 70% |
| Question quality | AI questions a user edits or deletes | ≤ 15% |
| Cost | LLM cost per active user per month | ≤ $0.05 |

The review history already stored per attempt (`review_attempts`) is enough to compute the retention and habit metrics; activation needs one product event (first takeaway saved).

## Business model (hypothesis)

- **Free:** catalog, library, up to 50 active recall questions, all six languages.
- **Pro (~$4/month):** unlimited questions, import of Kindle/Kobo highlights, Markdown/Anki export.

Unit economics are plausible because question generation is bounded: at most 5 LLM calls per request, and one call per saved takeaway.

## Not now

Deliberately out of scope until the core loop proves the activation and habit targets: mobile apps, social features, learning paths, knowledge graphs. The first three were built and removed; see the README's *Scope decisions*.

## Next steps

1. Deploy a public demo (web + API + Supabase).
2. Add product events for activation and review sessions.
3. Kindle highlight import, the most likely driver of activation.
