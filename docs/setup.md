# Setup Guide — Book AI App

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Python | 3.11+ | https://python.org |
| Flutter | 3.16+ | https://flutter.dev |
| Git | any | https://git-scm.com |

---

## 1. Clone / Download

```bash
git clone https://github.com/your-username/book-ai-app.git
cd book-ai-app
```

---

## 2. Backend Setup (Flask)

### 2.1 Create virtual environment

```bash
cd backend
python -m venv venv

# Windows
venv\Scripts\activate

# macOS / Linux
source venv/bin/activate
```

### 2.2 Install dependencies

```bash
pip install -r requirements.txt
```

### 2.3 Configure environment variables

```bash
cp env.example .env
```

Open `.env` and fill in:

```env
DEBUG=True
SECRET_KEY=any-random-string-here

# Leave empty to use OpenLibrary covers (no key needed)
GOOGLE_BOOKS_API_KEY=

# Your Supabase project credentials (see supabase_setup.md)
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...
```

### 2.4 Start the server

```bash
python app.py
```

On first run the server will:
1. Load `data/books.csv`
2. Train the TF-IDF model (~2 seconds)
3. Save it to `saved_model/tfidf.pkl`
4. On subsequent starts, load from pickle (instant)

### 2.5 Verify it works

```
GET http://localhost:5000/api/health
→ {"status":"healthy","service":"book-ai-api"}

GET http://localhost:5000/api/books/popular?limit=5
→ {"books":[...], "total":5}

GET http://localhost:5000/api/recommend?book=Dune
→ {"book":"Dune","recommendations":[...],"total":10}

GET http://localhost:5000/api/search?q=tolkien
→ {"books":[...],"total":2,"query":"tolkien"}
```

---

## 3. Flutter App Setup

### 3.1 Install dependencies

```bash
cd ../mobile/flutter_app
flutter pub get
```

### 3.2 Configure endpoints

Open `lib/config.dart` and update:

```dart
static const String backendUrl = 'http://10.0.2.2:5000';  // Android emulator
// or
static const String backendUrl = 'http://localhost:5000';   // iOS simulator

static const String supabaseUrl = 'https://YOUR_PROJECT.supabase.co';
static const String supabaseAnonKey = 'YOUR_ANON_KEY';
```

> **Android physical device**: use your machine's local IP, e.g. `http://192.168.1.x:5000`

### 3.3 Run on device / emulator

```bash
# List available devices
flutter devices

# Run
flutter run

# Run on specific device
flutter run -d <device-id>

# Build release APK
flutter build apk --release
```

---

## 4. Running Both Together

Terminal 1 (backend):
```bash
cd backend && python app.py
```

Terminal 2 (Flutter):
```bash
cd mobile/flutter_app && flutter run
```

---

## 5. Common Issues

| Problem | Solution |
|---------|----------|
| `ModuleNotFoundError` | Activate venv: `venv\Scripts\activate` |
| `Connection refused` on emulator | Use `10.0.2.2` not `localhost` |
| Model training slow | Normal on first run — model is cached after |
| Flutter pub get fails | Run `flutter doctor` and fix SDK issues |
| `CORS error` in browser testing | Set `ALLOWED_ORIGINS=*` in `.env` |
