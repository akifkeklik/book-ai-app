# Google Books API Setup Guide

The Google Books API provides **cover images** and enriched metadata.
The app works without it (falls back to OpenLibrary covers) but a key gives better results.

---

## Step 1: Create a Google Cloud Project

1. Go to https://console.cloud.google.com
2. Click the project selector (top bar) → **New Project**
3. Name it `book-ai-app` → **Create**

---

## Step 2: Enable the Books API

1. In the left menu: **APIs & Services → Library**
2. Search for **Books API**
3. Click it → **Enable**

---

## Step 3: Create an API Key

1. Left menu: **APIs & Services → Credentials**
2. Click **+ Create Credentials → API key**
3. Copy the key shown (starts with `AIza...`)

---

## Step 4: Restrict the Key (Production)

1. Click **Edit API key** (pencil icon)
2. Under **API restrictions**: select **Restrict key**
3. Select **Books API** from the dropdown
4. Save

> For development you can skip restrictions, but always restrict before shipping.

---

## Step 5: Insert the Key

### Backend (`.env` at project root):
```env
GOOGLE_BOOKS_API_KEY=AIzaSy...YOUR_KEY_HERE
```

That's all — the backend's `BookService._google_cover()` reads this automatically.

### Verify it works

```bash
curl "https://www.googleapis.com/books/v1/volumes?q=intitle:Dune&key=YOUR_KEY&maxResults=1"
```

You should get a JSON response with a `thumbnail` URL in `imageLinks`.

---

## Quotas & Limits

| Tier | Requests / day | Cost |
|------|---------------|------|
| Free | 1,000 | $0 |
| Paid | up to 1,000 / second | Pay-as-you-go |

For an MVP the free tier is more than enough.
The backend also has `@lru_cache(maxsize=512)` so repeated lookups for the same book never hit the API twice per server session.

---

## Without an API Key

If `GOOGLE_BOOKS_API_KEY` is empty, `BookService._enrich()` automatically falls back to:

```
https://covers.openlibrary.org/b/isbn/{isbn13}-L.jpg
```

OpenLibrary covers are completely free with no key required.
