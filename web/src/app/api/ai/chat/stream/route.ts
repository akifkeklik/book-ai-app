import { NextRequest, NextResponse } from 'next/server';
import { ApiService } from '@/lib/api';

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:5000';

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => null);
    if (!body || typeof body !== 'object' || !body.query) {
      return NextResponse.json({ error: "JSON body with 'query' is required" }, { status: 400 });
    }

    const rawQuery = body.query;
    if (typeof rawQuery !== 'string') {
      return NextResponse.json({ error: 'Query must be a string' }, { status: 400 });
    }

    const query = rawQuery.trim();
    if (!query) {
      return NextResponse.json({ error: 'Query cannot be empty' }, { status: 400 });
    }

    if (query.length > 1000) {
      return NextResponse.json(
        {
          error: 'Query exceeds maximum allowed length of 1000 characters',
          max_length: 1000,
          actual_length: query.length,
        },
        { status: 400 }
      );
    }

    // Securely retrieve server-side credentials and forwarded auth token.
    // Never expose LIBRIS_API_KEY to the client browser.
    const headers = await ApiService.getHeaders();

    const backendRes = await fetch(`${BACKEND_URL}/api/ai/chat/stream`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ query }),
      cache: 'no-store',
      signal: req.signal,
    });

    if (!backendRes.ok) {
      let errorMsg = `Backend stream error (${backendRes.status})`;
      try {
        const errJson = await backendRes.json();
        if (errJson?.error) {
          errorMsg = String(errJson.error);
        }
      } catch {
        // Fall back to status text
      }
      return NextResponse.json({ error: errorMsg }, { status: backendRes.status });
    }

    if (!backendRes.body) {
      return NextResponse.json({ error: 'No stream body returned by backend' }, { status: 502 });
    }

    // Proxy the event stream directly to the browser client
    return new Response(backendRes.body, {
      status: 200,
      headers: {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no',
      },
    });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === 'AbortError') {
      return new Response(null, { status: 499 });
    }
    const message = error instanceof Error ? error.message : 'Internal streaming gateway failure';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

