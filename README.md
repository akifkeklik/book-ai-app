# BookAI

> **Goodreads meets machine learning** — an AI-powered book recommendation mobile app built with Flask, TF-IDF, Flutter, and Supabase.

---

## Architecture

```
Flutter App
  ├── Provider state management
  ├── Dio → Flask API (books, search, recommendations)
  └── Supabase SDK (auth, favorites, activity)

Flask Backend
  ├── TF-IDF + Cosine Similarity engine
  ├── Hybrid scoring (content + popularity)
  ├── Google Books API (cover enrichment)
  └── books.csv → tfidf.pkl (auto-trained on startup)

Supabase (cloud)
  ├── Auth (email/password)
  ├── favorites table
  └── user_activity table
```

---

## Features

| Feature | Status |
|---------|--------|
| TF-IDF content-based recommendations | Done |
| Hybrid scoring (content + popularity) | Done |
| Full-text book search | Done |
| Google Books cover enrichment | Done |
| OpenLibrary cover fallback | Done |
| Email/password authentication | Done |
| Favorites with Supabase RLS | Done |
| Personalised home feed | Done |
| Dark / light theme | Done |
| Similarity score badges | Done |
| Swipe-to-remove favorites | Done |
| Activity tracking | Done |

---

## Quick Start

### Backend

```bash
cd backend
python -m venv venv && venv\Scripts\activate   # Windows
pip install -r requirements.txt
cp env.example .env                             # fill in keys
python app.py
```

### Flutter

```bash
cd mobile/flutter_app
flutter pub get
# edit lib/config.dart with your backend URL + Supabase keys
flutter run
```

Full instructions: [docs/setup.md](docs/setup.md)

---

## API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Liveness probe |
| GET | `/api/books?page=1&per_page=20` | Paginated book list |
| GET | `/api/books/popular?limit=20` | Popular books |
| GET | `/api/books/<isbn>` | Single book by ISBN |
| GET | `/api/search?q=tolkien` | Search by title/author/genre |
| GET | `/api/recommend?book=Dune&top_n=10` | AI recommendations |
| POST | `/api/track` | Log user activity |

---

## Project Structure

```
book-ai-app/
├── backend/
│   ├── app.py              Flask factory
│   ├── config.py           Env-driven settings
│   ├── model/
│   │   └── recommender.py  TF-IDF + cosine similarity engine
│   ├── routes/routes.py    API endpoints
│   ├── services/
│   │   └── book_service.py Orchestration + Google Books
│   ├── utils/preprocess.py Text cleaning + feature engineering
│   ├── data/books.csv      80+ book dataset
│   └── saved_model/        tfidf.pkl (auto-generated)
│
├── mobile/flutter_app/
│   └── lib/
│       ├── main.dart           App entry
│       ├── config.dart         Constants
│       ├── router.dart         GoRouter + auth guard
│       ├── theme/app_theme.dart Dark/light theme
│       ├── models/             Book, FavoriteBook
│       ├── providers/          Auth, Book, Favorites
│       ├── services/           ApiService, SupabaseService
│       ├── screens/            7 screens
│       └── widgets/            BookCard, ShimmerLoader
│
└── docs/
    ├── setup.md
    ├── supabase_setup.md
    └── google_api_setup.md
```

---

## ML Recommendation Engine

```
Input: book title
  ↓
TfidfVectorizer (max_features=10k, ngram_range=(1,2), sublinear_tf)
  applied to: title×3 + categories×2 + authors + description
  ↓
cosine_similarity(query_vector, all_book_vectors)
  ↓
Hybrid scoring:
  0.60 × content_similarity
  0.25 × log_normalised(ratings_count)
  0.15 × normalised(average_rating)
  ↓
Top-10 results with similarity_score badge
```

---

## Deployment

### Flask on Render

1. Push `backend/` to a GitHub repo
2. Render Dashboard → **New Web Service**
3. Connect repo, set **Root Directory** to `backend`
4. Build command: `pip install -r requirements.txt`
5. Start command: `gunicorn app:app --bind 0.0.0.0:$PORT`
6. Add environment variables in **Environment** tab
7. Deploy

### Flask on Railway

```bash
npm install -g @railway/cli
railway login
cd backend
railway init
railway up
railway env set GOOGLE_BOOKS_API_KEY=your-key
railway env set SECRET_KEY=your-secret
```

### Flutter (Android APK)

```bash
cd mobile/flutter_app
# Update lib/config.dart with your deployed backend URL
flutter build apk --release
# APK at: build/app/outputs/flutter-apk/app-release.apk
```

---

## Extending the Dataset

The sample `books.csv` contains ~85 books. For a real production deployment:

1. Download from Kaggle: **7k books dataset** (ISBN, title, authors, categories, description, ratings)
2. Drop the file at `backend/data/books.csv`
3. Delete `backend/saved_model/tfidf.pkl`
4. Restart the server — model retrains automatically

---

## License

MIT
