# 📚 Libris: The Sovereign of Digital Epics

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)
[![AI Powered](https://img.shields.io/badge/AI-Powered-FF6F61?style=for-the-badge&logo=openai&logoColor=white)](https://openai.com)

**Libris** is not just a book app; it is a premium, AI-driven gateway to your next literary obsession. Built with a "Zero-Overflow" engineering philosophy and an Apple-inspired aesthetic, Libris combines the power of **RAG (Retrieval-Augmented Generation)** with a seamless mobile experience to help you discover books that truly resonate with your soul.

---

## ✨ Key Features

### 🧠 AI-Powered Discoverability
- **RAG Architecture:** Real-time semantic analysis of over 6,000 titles to provide insights that go beyond simple metadata.
- **Personalized Recommendations:** Onboarding that learns your reading rhythm, interests, and "vibe" to curate a unique library.
- **AI Insights:** Quick, intelligent summaries and "Why you should read this" notes for every book.

### 💎 Premium Experience (Elite UI)
- **Zero-Overflow Design:** Surgically hardened layouts that adapt gracefully to any device size (iPhone Mini to iPad Pro).
- **Apple-Inspired Aesthetic:** Glassmorphism, subtle micro-animations, and a sophisticated pastel-dark theme.
- **Infinite Discovery:** High-performance infinite scroll through a massive catalog of world classics and modern masterpieces.

### 🌍 Global & Accessible
- **Full Localization:** Native support for English and Turkish, switchable at runtime.
- **Offline Resilience:** Advanced caching using Hive to ensure your library is always accessible.
- **Smart Filters:** Filter by author, page count, or genre with a single tap.

---

## 🛠️ Technical Stack

### Mobile (Flutter)
- **State Management:** Provider (Senior-grade architectural separation).
- **Database:** Supabase (Real-time sync) & Hive (Local cache).
- **Navigation:** GoRouter (Modular routing).
- **UI:** Custom "Libris Design System" built on Material 3 with premium styling.

### Backend (Python/Flask)
- **AI Core:** RAG implementation for deep semantic searches.
- **API:** Fast, scalable endpoints for recommendation generation.
- **Integration:** Seamless bridge between Supabase data and AI models.

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.16+)
- Python 3.9+
- Supabase Project

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/akifkeklik/book-ai-app.git
   cd book-ai-app
   ```

2. **Frontend Setup:**
   ```bash
   cd mobile/flutter_app
   flutter pub get
   flutter run
   ```

3. **Backend Setup:**
   ```bash
   cd backend
   pip install -r requirements.txt
   python app.py
   ```

---

## 🏗️ Architecture Detail

Libris follows a **Clean Architecture** pattern:
- **Presentation Layer:** Highly responsive Flutter widgets and Providers.
- **Domain Layer:** Business logic for recommendation matching.
- **Data Layer:** Supabase services with robust error handling and localized fallback mechanisms.

---

## 🛡️ Engineering Excellence (Zero-Overflow Phase)
We recently completed a surgical strike on UI stability:
- ✅ **Dynamic Constraints:** Replaced all fixed-dimension containers with `Flexible` and `Expanded` wrappers.
- ✅ **Empty State Management:** Integrated `LibrisEmptyState` and `ErrorView` to ensure the UI never feels broken, even without a connection.
- ✅ **Title Resilience:** Implemented multi-line text guards to prevent layout breakage from long book titles.

---

## 🎨 UI Showcase

> Use the **System Theme** to experience the adaptive glassmorphism effects in both Light and Dark modes.

---
