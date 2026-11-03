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
}

export interface StreamAiChatOptions {
  signal?: AbortSignal;
  endpoint?: string;
  onMetadata?: (meta: StreamMetadata) => void;
  onChunk?: (delta: string) => void;
  onDone?: (payload: StreamDonePayload) => void;
  onError?: (error: string) => void;
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

  let response: Response;
  try {
    response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query }),
      cache: 'no-store',
      signal,
    });
  } catch (err: unknown) {
    if (signal?.aborted) return;
    const msg = err instanceof Error ? err.message : 'Network failure connecting to AI assistant';
    onError?.(msg);
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
    onError?.(errorMsg);
    return;
  }

  if (!response.body) {
    if (signal?.aborted) return;
    onError?.('Stream body is empty');
    return;
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder('utf-8');
  let buffer = '';

  try {
    while (true) {
      if (signal?.aborted) {
        await reader.cancel();
        return;
      }

      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });

      // Split SSE events on double newline
      const parts = buffer.split('\n\n');
      // The last part is either empty or an incomplete event fragment
      buffer = parts.pop() || '';

      for (const part of parts) {
        if (!part.trim()) continue;

        const lines = part.split('\n');
        let eventType = 'message';
        let dataStr = '';

        for (const line of lines) {
          if (line.startsWith('event:')) {
            eventType = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            dataStr = line.substring(5).trim();
          }
        }

        if (!dataStr) continue;

        try {
          const parsed = JSON.parse(dataStr);

          if (eventType === 'metadata') {
            const referenced = normalizeBooks(parsed.referenced_books);
            onMetadata?.({
              referenced_books: referenced,
              status: parsed.status || 'streaming',
            });
          } else if (eventType === 'chunk') {
            const delta = typeof parsed.delta === 'string' ? parsed.delta : '';
            if (delta) {
              onChunk?.(delta);
            }
          } else if (eventType === 'done') {
            const referenced = normalizeBooks(parsed.referenced_books);
            onDone?.({
              answer: parsed.answer || '',
              referenced_books: referenced,
              status: parsed.status || 'success',
              action: parsed.action || null,
            });
          } else if (eventType === 'error') {
            onError?.(parsed.error || 'An error occurred during AI processing.');
          }
        } catch {
          // Incomplete or malformed JSON chunk - discard safely without crashing
        }
      }
    }
  } catch (err: unknown) {
    if (signal?.aborted) return;
    const msg = err instanceof Error ? err.message : 'Stream interrupted unexpectedly';
    onError?.(msg);
  } finally {
    reader.releaseLock();
  }
}

