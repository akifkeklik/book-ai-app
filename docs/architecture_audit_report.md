# M10 Phase 1: Architectural Audit & Verification Report

Bu rapor `book-ai-app` sisteminin M10 fazındaki mevcut mimarisini, trade-off'larını ve mühendislik dayanıklılığını analiz eder.

## A. Dependency Graph
**DEBT (Minor)**
- **Flutter:** `Screens/Widgets -> Providers -> BookRepository -> ApiService/SupabaseService`. Bağımlılık yönü doğrudur (UI -> Application -> Data -> Infrastructure).
- **Backend:** `Routes -> Application Use Cases -> Domain Ports -> Infrastructure Adapters`. Büyük ölçüde doğru.
- **Problem:** Backend'de `BookService` hala `_bootstrap` ve `_enrich` barındırıyor, ancak "Use Case" katmanı `BookEnrichmentService`'e geçiş yaptı. `routes.py` bir Composition Root olarak işlev görüyor ancak çok fazla manual injection var.

## B. BookRepository Responsibility
**DEBT (Major)**
`BookRepository`, Interface Segregation Principle (ISP) ihlali yapmaktadır. Gerçek "Book data access" sınırını çoktan aşmıştır:
- Catalog / Data Access: `getPopularBooks`, `getBooksByCategory`, `searchBooks`
- Recommendation: `getPersonalizedRecommendations`, `getFallbackRecommendations`
- Activity & Profile: `trackActivity`, `upsertUserProfile`, `submitFeedback`
- AI Chat: `chatWithAI`

Sistem büyüdükçe bu arayüz parçalanmalıdır (`CatalogRepository`, `RecommendationRepository`, `InteractionRepository` vb.). Ancak test edilebilirlik şu an Flutter'ın mevcut küçük scale'ı için büyük bir problem yaratmadığı için bu aşamada refactor edilmemiştir.

## C. Backend Responsibility
**DEBT (Minor)**
Application Use Caseler başarıyla bölünmüş (örn. `ProcessRagQueryUseCase`, `GetPersonalizedRecommendationsUseCase`). God Object olan `BookService` zayıflamıştır, ancak ölü kodu ve orchestration legacy'sini (`verify_token` vs.) taşıdığı için ufak bir refactor ihtiyacı vardır. Use caselerin her biri tek sorumluluğa sahiptir.

## D. Dependency Inversion
**PASS**
- M5'te kurulan dependency inversion (`LlmPort`, `BookDataPort`, `UserInteractionRepository`) çalışmaktadır.
- `test_api.py` içerisinde `fake_interaction_repo` kullanılarak Supabase bağımlılığı olmadan test edilebilmektedir.
- LLM adaptörü (`GenericLlmAdapter`), hem Gemini hem OpenAI destekleyecek şekilde infrastructure adapter olarak izole edilmiştir.

## E. Change Impact Analysis
**PASS**
- **Scenario A (Supabase Kaldırılması):** Sadece `supabase_adapters.py`, `config.py` ve Flutter'daki `SupabaseService` silinir/değişir. Core logic ve Use Cases etkilenmez.
- **Scenario B (Gemini -> OpenAI):** Sadece `.env` içerisindeki `LLM_PROVIDER="openai"` ve API Key değişir. Kod değişmez (`GenericLlmAdapter` handle eder).
- **Scenario C (Hive -> Isar):** Flutter'da `BookRepositoryImpl` içerisindeki `getCachedPopularBooks` metodu ve `main.dart`'taki init süreci değişir.
- **Scenario D (Recommendation Değişimi):** Sadece backend `recommender.py` (Engine) değişir, `recommendations.py` Use Case'leri değişmez.
- **Scenario E (Entity'e yeni alan):** Supabase şeması, Flutter `book_dto.dart` ve UI widget'ları (gösterilecekse) etkilenir.

## F. Failure Propagation
**PASS**
- **Supabase Hatası:** Backend Supabase hatası verirse Flask exception handler yakalar, HTTP 500 döner. Flutter'da `SupabaseService` atar, `BookRepositoryImpl` yakalayıp Flask API'ye (`ApiService`) fallback yapar.
- **LLM Hatası:** `GenericLlmAdapter` timeout (15.0s) ile konfigüre edilmiştir. Exception yakalanır ve `None` döner. `ProcessRagQueryUseCase` `None` yakalayıp graceful degrade olarak fallback message döner.
- **Embedding Hatası:** Semantik arama bozulursa, `recommendations.py` bunu yakalar (`except Exception`) ve degrade olarak salt TF-IDF ile öneri üretmeye devam eder.

## G. State Machine (Flutter)
**PASS**
- `BookProvider.fetchPersonalizedRecs` içerisinde stale response guard (`if (_currentUserId != userId) return;`) mevcuttur.
- `FavoritesProvider` optimistic update kullanmakta, API hatası durumunda listeyi eski haline rollback yapmaktadır (Impossible state engellenmiş).

## H. Test Architecture
**DEBT**
- Flutter testleri unit, provider behavioral ve screen widget testleri olarak katmanlanmıştır (başarılı).
- Backend tarafında "Application Use Cases" için pure unit testler *yoktur*. Use case'ler `test_api.py` üzerinden (integration-like) Flask `app.test_client()` ile test edilmektedir. Production'da hata yakalayabilir ancak Use Case'ler izole edilmiş değildir.

## I. Flutter Verification
**PASS**
- `flutter analyze` : Dart `StreamController` syntax hatası giderildi, sorunsuz.
- `flutter test` : 17 testin tamamı PASS durumunda. (Stale cache, optimistic UI, Auth rollbacks vs. hepsi başarılı).
- `flutter test --coverage` : Toplam test edilen satır: 254 / 1100 (**%23.09 Line Coverage**)

## J. Backend Verification
**PASS**
- Backend dockerize edilip pytest çalıştırıldı ve verification başarıyla tamamlandı (Tests Passed).

## M. Engineering Judgment Summary

1. **Sistemde şu anda en güçlü architectural boundary hangisi?**
   Backend LLM Adapter ve Recommendation Engine sınırı. Dependency inversion en net burada işliyor. Timeout ve fallback mekanizmaları kusursuz.
2. **En zayıf boundary hangisi?**
   Flutter `BookRepository`. İçerisinde hem caching (Hive) hem de God-Interface (UI ve Domain birbirine karışık) bulunuyor.
3. **En yüksek coupling nerede?**
   Flutter `BookRepositoryImpl` direkt olarak Hive instance'ına bağlı (abstract bir `LocalCachePort` yerine direkt `Hive.box`).
4. **En pahalı değişiklik hangisi olur?**
   Flutter uygulamasını offline-first (Senkronize DB) mimariye geçirmek. Çünkü `BookRepository` ve `Providers` tamamen remote çağrılara göre tasarlandı.
5. **En riskli production failure path hangisi?**
   Flask API ile Supabase'in aynı anda çökmesi veya latency'nin artması (Flutter timeouts fallback yaparken UX'i kilitmeyebilir ama response slow olabilir).
6. **Hangi debt bugün çözülmemeli?**
   `BookRepository` Interface segregation. Henüz takım hızı için engel oluşturmuyor, abstract etmek dosyaları çok böler.
7. **Hangi debt büyürse ileride çözülmeli?**
   Backend Use Cases için pure unit test eksikliği. Yeni bir logic eklendikçe `test_api.py`'ın execution süresi katlanarak artacaktır.
