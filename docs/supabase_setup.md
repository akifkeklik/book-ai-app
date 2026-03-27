# Supabase Setup Guide

## Step 1: Create a Supabase Project

1. Go to https://supabase.com and sign up / log in
2. Click **New Project**
3. Fill in:
   - **Name**: `book-ai-app`
   - **Database Password**: choose a strong password
   - **Region**: pick closest to your users
4. Click **Create new project** — takes ~2 minutes

---

## Step 2: Create Database Tables

1. In your project dashboard, click **SQL Editor** in the left sidebar
2. Click **New Query**
3. Paste the following SQL and click **Run**:

```sql
-- ────────────────────────────────────────────────
-- FAVORITES
-- ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS favorites (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  isbn13      text NOT NULL,
  book_title  text NOT NULL DEFAULT '',
  thumbnail   text NOT NULL DEFAULT '',
  added_at    timestamptz DEFAULT now(),
  UNIQUE(user_id, isbn13)
);

-- ────────────────────────────────────────────────
-- USER ACTIVITY
-- ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_activity (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  book_name   text NOT NULL,
  action      text NOT NULL DEFAULT 'view',
  created_at  timestamptz DEFAULT now()
);

-- ────────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ────────────────────────────────────────────────
ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own favorites"
  ON favorites
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users manage own activity"
  ON user_activity
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
```

4. You should see **Success. No rows returned** — that's correct.

---

## Step 3: Configure Auth

1. Go to **Authentication → Settings** in the left sidebar
2. Under **User Signups**, make sure "Allow new users to sign up" is **enabled**
3. Optional: Under **Email Auth**, disable "Confirm email" for development

---

## Step 4: Get Your API Keys

1. Go to **Settings → API** (gear icon in left sidebar)
2. Copy:
   - **Project URL** → `https://xxxxx.supabase.co`
   - **anon / public** key → `eyJhbGci...` (long JWT)

---

## Step 5: Insert Keys into the App

### Flutter (`lib/config.dart`):
```dart
static const String supabaseUrl = 'https://YOUR_PROJECT_ID.supabase.co';
static const String supabaseAnonKey = 'YOUR_ANON_PUBLIC_KEY';
```

### Flask backend (`.env`):
```env
SUPABASE_URL=https://YOUR_PROJECT_ID.supabase.co
SUPABASE_ANON_KEY=YOUR_ANON_PUBLIC_KEY
```

---

## Step 6: Verify

1. Run the Flutter app
2. Go to **Register** and create an account
3. In Supabase dashboard → **Authentication → Users** — you should see the new user
4. Add a book to favorites in the app
5. In Supabase → **Table Editor → favorites** — you should see the row

---

## Table Reference

### `favorites`
| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid | Primary key (auto) |
| `user_id` | uuid | FK to `auth.users` |
| `isbn13` | text | Book ISBN-13 identifier |
| `book_title` | text | Cached title for display |
| `thumbnail` | text | Cached cover URL |
| `added_at` | timestamptz | When saved |

### `user_activity`
| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid | Primary key (auto) |
| `user_id` | uuid | FK to `auth.users` |
| `book_name` | text | Book title viewed/searched |
| `action` | text | `view`, `search`, `recommend` |
| `created_at` | timestamptz | Event timestamp |
