import type { Book, AiAction } from '@/types';
import { normalizeBooks } from './normalizers';

export interface StreamMetadata {
  referenced_books: Book[];
  status: string;
}

export interface StreamDonePayload {
  answer: string;
  referenced_books: Book[];
  status: string;
  action?: AiAction | null;
  /** metrics.source from the backend (e.g. rag_llm, deterministic_catalog_hit); null if absent. */
  source?: string | null;
  retrieval_mode?: string | null;
}

export interface StreamErrorInfo {
  /** HTTP status when the request was answered with an error. */
  status?: number;
  /** True when the request never reached the server or the stream broke mid-way. */
  network?: boolean;
  /** True when the server answered but reported (or produced) a failure instead of an answer. */
  server?: boolean;
}

export interface StreamAiChatOptions {
  signal?: AbortSignal;
  endpoint?: string;
  /** ISBNs of the books in the previous answer, so a follow-up ("tell me more") can refer to them. */
  contextIsbns?: string[];
  onMetadata?: (meta: StreamMetadata) => void;
  onChunk?: (delta: string) => void;
  onDone?: (payload: StreamDonePayload) => void;
  onError?: (error: string, info?: StreamErrorInfo) => void;
}

/**
 * Robust Server-Sent Events (SSE) parser and reader for Next.js AI Discovery.
 * Handles buffer boundaries, multi-byte UTF-8 chunks, cancellation via AbortSignal,
 * and error recovery.
 */
export async function streamAiChat(
  query: string,
  options: StreamAiChatOptions = {}
): Promise<void> {
  const { signal, onMetadata, onChunk, onDone, onError, endpoint = '/api/ai/chat/stream' } = options;
  const contextIsbns = (options.contextIsbns ?? []).filter(Boolean).slice(0, 5);

  let response: Response;
  try {
    response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(contextIsbns.length ? { query, context_isbns: contextIsbns } : { query }),
      cache: 'no-store',
      signal,
    });
  } catch (err: unknown) {
    if (signal?.aborted) return;
    const msg = err instanceof Error ? err.message : 'Network failure connecting to AI assistant';
    onError?.(msg, { network: true });
    return;
  }

  if (!response.ok) {
    if (signal?.aborted) return;
    let errorMsg = `Streaming failed with HTTP ${response.status}`;
    try {
      const errJson = await response.json();
      if (errJson?.error) errorMsg = String(errJson.error);
    } catch {
      // Ignore JSON parse failure on non-JSON error response
    }
    onError?.(errorMsg, { status: response.status });
    return;
  }

  if (!response.body) {
    if (signal?.aborted) return;
    onError?.('Stream body is empty', { server: true });
    return;
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder('utf-8');
  let buffer = '';
  // Every stream must end in exactly one `done` or `error`; without one the caller would be
  // left in its loading state forever.
  let finished = false;

  const handleEvent = (rawEvent: string) => {
    if (finished || !rawEvent.trim()) return;

    let eventType = 'message';
    let dataStr = '';
    for (const line of rawEvent.split('\n')) {
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataStr = line.substring(5).trim();
      }
    }
    if (!dataStr) return;

    let parsed;
    try {
      parsed = JSON.parse(dataStr);
    } catch {
      // Malformed JSON frame - discard safely without crashing
      return;
    }

    if (eventType === 'metadata') {
      onMetadata?.({
        referenced_books: normalizeBooks(parsed.referenced_books),
        status: parsed.status || 'streaming',
      });
    } else if (eventType === 'chunk') {
      const delta = typeof parsed.delta === 'string' ? parsed.delta : '';
      if (delta) onChunk?.(delta);
    } else if (eventType === 'done') {
      finished = true;
      onDone?.({
        answer: parsed.answer || '',
        referenced_books: normalizeBooks(parsed.referenced_books),
        status: parsed.status || 'success',
        action: parsed.action || null,
        source: typeof parsed.source === 'string' ? parsed.source : null,
        retrieval_mode: typeof parsed.retrieval_mode === 'string' ? parsed.retrieval_mode : null,
      });
    } else if (eventType === 'error') {
      finished = true;
      onError?.(parsed.error || 'An error occurred during AI processing.', { server: true });
    }
  };

  try {
    while (true) {
      if (signal?.aborted) {
        await reader.cancel();
        return;
      }

      const { done, value } = await reader.read();
      if (done) break;

      // Normalise CRLF so proxies that rewrite line endings cannot break event framing.
      buffer += decoder.decode(value, { stream: true }).replace(/\r\n?/g, '\n');

      // Split SSE events on double newline; the last part is an incomplete fragment (or empty).
      const parts = buffer.split('\n\n');
      buffer = parts.pop() || '';
      parts.forEach(handleEvent);
    }

    if (signal?.aborted) return;
    // A final event without the trailing blank line is still a complete event.
    handleEvent(buffer + decoder.decode().replace(/\r\n?/g, '\n'));
    if (!finished) {
      onError?.('The AI stream ended before an answer was completed', { network: true });
    }
  } catch (err: unknown) {
    if (signal?.aborted || finished) return;
    const msg = err instanceof Error ? err.message : 'Stream interrupted unexpectedly';
    onError?.(msg, { network: true });
  } finally {
    reader.releaseLock();
  }
}

