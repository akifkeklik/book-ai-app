import test from 'node:test';
import assert from 'node:assert';
import type { Book } from '@/types';
import { streamAiChat, StreamMetadata, StreamDonePayload } from '../lib/ai_stream';

// Helper to create a mocked SSE ReadableStream from text chunks
function createMockStream(chunks: string[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  let index = 0;
  return new ReadableStream({
    pull(controller) {
      if (index < chunks.length) {
        controller.enqueue(encoder.encode(chunks[index]));
        index++;
      } else {
        controller.close();
      }
    },
  });
}

test('AI Chat Streaming: successfully consumes multiple token chunk events in order', async () => {
  const ssePayload = [
    'event: metadata\ndata: {"referenced_books":[],"status":"streaming"}\n\n',
    'event: chunk\ndata: {"delta":"Dune is "}\n\n',
    'event: chunk\ndata: {"delta":"a classic "}\n\n',
    'event: chunk\ndata: {"delta":"masterpiece."}\n\n',
    'event: done\ndata: {"answer":"Dune is a classic masterpiece.","referenced_books":[],"status":"success"}\n\n',
  ];

  const chunksReceived: string[] = [];
  let metadataReceived: StreamMetadata | null = null;
  let doneReceived: StreamDonePayload | null = null;
  let errorReceived: string | null = null;

  const originalFetch = global.fetch;
  global.fetch = (async () => {
    return new Response(createMockStream(ssePayload), {
      status: 200,
      headers: { 'Content-Type': 'text/event-stream' },
    });
  }) as typeof fetch;

  try {
    await streamAiChat('Tell me about Dune', {
      onMetadata: (meta) => { metadataReceived = meta; },
      onChunk: (delta) => { chunksReceived.push(delta); },
      onDone: (payload) => { doneReceived = payload; },
      onError: (err) => { errorReceived = err; },
    });

    assert.strictEqual(errorReceived, null);
    assert.ok(metadataReceived);
    assert.deepStrictEqual(chunksReceived, ['Dune is ', 'a classic ', 'masterpiece.']);
    assert.ok(doneReceived !== null);
    const finalPayload = doneReceived as unknown as StreamDonePayload;
    assert.strictEqual(finalPayload.answer, 'Dune is a classic masterpiece.');
    assert.strictEqual(finalPayload.status, 'success');
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Chat Streaming: parses referenced book citations accurately into typed Book entities', async () => {
  const ssePayload = [
    'event: metadata\ndata: {"referenced_books":[{"isbn13":"9780451524935","title":"1984","authors":"George Orwell","average_rating":4.7}],"status":"streaming"}\n\n',
    'event: chunk\ndata: {"delta":"1984 by George Orwell."}\n\n',
    'event: done\ndata: {"answer":"1984 by George Orwell.","referenced_books":[{"isbn13":"9780451524935","title":"1984","authors":"George Orwell","average_rating":4.7}],"status":"success"}\n\n',
  ];

  let metaBooks: Book[] = [];
  let doneBooks: Book[] = [];

  const originalFetch = global.fetch;
  global.fetch = (async () => {
    return new Response(createMockStream(ssePayload), {
      status: 200,
      headers: { 'Content-Type': 'text/event-stream' },
    });
  }) as typeof fetch;

  try {
    await streamAiChat('Tell me about 1984', {
      onMetadata: (m) => { metaBooks = m.referenced_books; },
      onDone: (d) => { doneBooks = d.referenced_books; },
    });

    assert.strictEqual(metaBooks.length, 1);
    assert.strictEqual(metaBooks[0].isbn13, '9780451524935');
    assert.strictEqual(metaBooks[0].title, '1984');
    assert.strictEqual(doneBooks.length, 1);
    assert.strictEqual(doneBooks[0].isbn13, '9780451524935');
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Chat Streaming: handles empty stream response body without crashing', async () => {
  let errorMsg = '';
  const originalFetch = global.fetch;
  global.fetch = (async () => {
    return new Response(null, {
      status: 200,
      headers: { 'Content-Type': 'text/event-stream' },
    });
  }) as typeof fetch;

  try {
    await streamAiChat('Test empty', {
      onError: (err) => { errorMsg = err; },
    });
    assert.ok(errorMsg.includes('empty'));
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Chat Streaming: handles server error 500 cleanly with parsed error message', async () => {
  let errorMsg = '';
  const originalFetch = global.fetch;
  global.fetch = (async () => {
    return new Response(JSON.stringify({ error: 'Database connection failed' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }) as typeof fetch;

  try {
    await streamAiChat('Trigger failure', {
      onError: (err) => { errorMsg = err; },
    });
    assert.strictEqual(errorMsg, 'Database connection failed');
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Chat Streaming: handles authentication failure 401 gracefully', async () => {
  let errorMsg = '';
  const originalFetch = global.fetch;
  global.fetch = (async () => {
    return new Response(JSON.stringify({ error: 'Session expired. Please log in again.' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }) as typeof fetch;

  try {
    await streamAiChat('Auth test', {
      onError: (err) => { errorMsg = err; },
    });
    assert.strictEqual(errorMsg, 'Session expired. Please log in again.');
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Chat Streaming: handles network interruption gracefully', async () => {
  let errorMsg = '';
  const originalFetch = global.fetch;
  global.fetch = (async () => {
    throw new TypeError('Failed to fetch: network connection closed');
  }) as typeof fetch;

  try {
    await streamAiChat('Network test', {
      onError: (err) => { errorMsg = err; },
    });
    assert.ok(errorMsg.includes('network connection closed'));
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Chat Streaming: supports AbortController cancellation and stops processing', async () => {
  const controller = new AbortController();
  const chunksReceived: string[] = [];

  const originalFetch = global.fetch;
  global.fetch = (async () => {
    return new Response(
      createMockStream([
        'event: chunk\ndata: {"delta":"Part 1"}\n\n',
        'event: chunk\ndata: {"delta":"Part 2"}\n\n',
      ]),
      { status: 200, headers: { 'Content-Type': 'text/event-stream' } }
    );
  }) as typeof fetch;

  try {
    await streamAiChat('Cancel test', {
      signal: controller.signal,
      onChunk: (delta) => {
        chunksReceived.push(delta);
        // Abort upon receiving the first token
        controller.abort();
      },
    });

    // Only chunks before cancellation are delivered
    assert.strictEqual(chunksReceived.length, 1);
    assert.strictEqual(chunksReceived[0], 'Part 1');
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Chat Streaming: handles fragmented or split SSE chunks across network frames', async () => {
  // Simulate stream where an event is split right down the middle across network frames
  const frame1 = 'event: chunk\ndata: {"del';
  const frame2 = 'ta":"Fragmented text"}\n\n';

  const chunksReceived: string[] = [];

  const originalFetch = global.fetch;
  global.fetch = (async () => {
    return new Response(createMockStream([frame1, frame2]), {
      status: 200,
      headers: { 'Content-Type': 'text/event-stream' },
    });
  }) as typeof fetch;

  try {
    await streamAiChat('Frame test', {
      onChunk: (delta) => { chunksReceived.push(delta); },
    });

    assert.strictEqual(chunksReceived.length, 1);
    assert.strictEqual(chunksReceived[0], 'Fragmented text');
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Chat Streaming: handles server event: error without throwing', async () => {
  const ssePayload = [
    'event: error\ndata: {"error":"External AI inference rate limit exceeded"}\n\n',
  ];

  let errorMsg = '';
  const originalFetch = global.fetch;
  global.fetch = (async () => {
    return new Response(createMockStream(ssePayload), { status: 200 });
  }) as typeof fetch;

  try {
    await streamAiChat('Rate limit test', {
      onError: (err) => { errorMsg = err; },
    });
    assert.strictEqual(errorMsg, 'External AI inference rate limit exceeded');
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Chat Streaming: discards malformed and corrupted JSON lines without halting subsequent chunks', async () => {
  const ssePayload = [
    'event: chunk\ndata: {INVALID_JSON_CHUNK\n\n',
    'event: chunk\ndata: {"delta":"Valid recovery text"}\n\n',
  ];

  const chunksReceived: string[] = [];
  const originalFetch = global.fetch;
  global.fetch = (async () => {
    return new Response(createMockStream(ssePayload), {
      status: 200,
      headers: { 'Content-Type': 'text/event-stream' },
    });
  }) as typeof fetch;

  try {
    await streamAiChat('Corrupted chunk test', {
      onChunk: (delta) => { chunksReceived.push(delta); },
    });

    assert.strictEqual(chunksReceived.length, 1);
    assert.strictEqual(chunksReceived[0], 'Valid recovery text');
  } finally {
    global.fetch = originalFetch;
  }
});

test('AI Grounding Integrity: verified books derive isGrounded true while empty books enforce ungrounded indicator', () => {
  const deriveGrounding = (books: Book[] | undefined | null): boolean => {
    return Array.isArray(books) && books.length > 0;
  };

  // 1. Empty array -> ungrounded
  assert.strictEqual(deriveGrounding([]), false);

  // 2. Undefined or null -> ungrounded
  assert.strictEqual(deriveGrounding(undefined), false);
  assert.strictEqual(deriveGrounding(null), false);

  // 3. Populated array -> verified
  const sampleBook: Book = {
    isbn13: '9780451524935',
    title: '1984',
    authors: 'George Orwell',
    categories: 'Fiction',
    description: '',
    thumbnail: '',
    averageRating: 4.5,
    ratingsCount: 100,
    publishedDate: '1949',
    pageCount: 328,
  };
  assert.strictEqual(deriveGrounding([sampleBook]), true);
});

function withMockStream(chunks: string[], run: () => Promise<void>): Promise<void> {
  const originalFetch = global.fetch;
  global.fetch = (async () =>
    new Response(createMockStream(chunks), {
      status: 200,
      headers: { 'Content-Type': 'text/event-stream' },
    })) as typeof fetch;
  return run().finally(() => {
    global.fetch = originalFetch;
  });
}

test('AI Chat Streaming: a stream that closes without done/error reports a network error', async () => {
  const errors: { msg: string; network?: boolean }[] = [];
  let doneCalled = false;
  await withMockStream(
    ['event: metadata\ndata: {"referenced_books":[],"status":"streaming"}\n\n', 'event: chunk\ndata: {"delta":"Half an ans"}\n\n'],
    () =>
      streamAiChat('Truncated', {
        onDone: () => { doneCalled = true; },
        onError: (msg, info) => { errors.push({ msg, network: info?.network }); },
      })
  );
  assert.strictEqual(doneCalled, false);
  assert.strictEqual(errors.length, 1, 'caller must be released from its loading state exactly once');
  assert.strictEqual(errors[0].network, true);
});

test('AI Chat Streaming: a final done event without the trailing blank line is still delivered', async () => {
  let done: StreamDonePayload | null = null;
  let errorCalled = false;
  await withMockStream(
    ['event: chunk\ndata: {"delta":"Hi"}\n\n', 'event: done\ndata: {"answer":"Hi","referenced_books":[],"status":"success","source":"rag_llm"}'],
    () =>
      streamAiChat('No trailing newline', {
        onDone: (d) => { done = d; },
        onError: () => { errorCalled = true; },
      })
  );
  assert.strictEqual(errorCalled, false);
  assert.ok(done);
  assert.strictEqual((done as StreamDonePayload).source, 'rag_llm');
});

test('AI Chat Streaming: CRLF-framed events are parsed', async () => {
  const chunks: string[] = [];
  let doneCalled = false;
  await withMockStream(
    ['event: chunk\r\ndata: {"delta":"A"}\r\n\r\n', 'event: done\r\ndata: {"answer":"A","referenced_books":[],"status":"success"}\r\n\r\n'],
    () =>
      streamAiChat('CRLF', {
        onChunk: (d) => { chunks.push(d); },
        onDone: () => { doneCalled = true; },
      })
  );
  assert.deepStrictEqual(chunks, ['A']);
  assert.strictEqual(doneCalled, true);
});

test('AI Chat Streaming: an in-stream error event is flagged as a server error and reported once', async () => {
  const infos: (boolean | undefined)[] = [];
  await withMockStream(
    ['event: error\ndata: {"error":"An error occurred during AI processing."}\n\n'],
    () => streamAiChat('Server failure', { onError: (_m, info) => { infos.push(info?.server); } })
  );
  assert.deepStrictEqual(infos, [true]);
});

test('AI Chat Streaming: the previous answer\'s books are sent so a follow-up can refer to them', async () => {
  let sentBody: Record<string, unknown> | null = null;
  const originalFetch = global.fetch;
  global.fetch = (async (_url: unknown, init?: RequestInit) => {
    sentBody = JSON.parse(String(init?.body));
    return new Response(createMockStream(['event: done\ndata: {"answer":"ok","referenced_books":[],"status":"success"}\n\n']), {
      status: 200,
      headers: { 'Content-Type': 'text/event-stream' },
    });
  }) as typeof fetch;
  try {
    await streamAiChat('Biraz anlatır mısın?', { contextIsbns: ['9780451524935', '', '9780452284234'] });
    assert.deepStrictEqual(sentBody, { query: 'Biraz anlatır mısın?', context_isbns: ['9780451524935', '9780452284234'] });
    await streamAiChat('Books like Dune');
    assert.deepStrictEqual(sentBody, { query: 'Books like Dune' }, 'no context field when there is no previous answer');
  } finally {
    global.fetch = originalFetch;
  }
});
