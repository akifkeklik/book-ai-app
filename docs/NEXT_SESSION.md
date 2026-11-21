# Sonraki oturum — devir notu (2026-11-20 gecesi)

Branch: `ai-subsystem-audit` · Ana commit: `9bc8f0a` (bu notu ekleyen docs commit'i hemen arkasından gelir) · `main` ile birleştirilmedi.

## 1. Bu gece tamamlananlar

- AI alt sistem audit'indeki tüm kaynak kod, test, değerlendirme (evaluation) verisi ve raporlar tek commit'te toplandı (`9bc8f0a`, 69 dosya).
- `backend/env.example` → `backend/.env.example` taşıması tamamlandı. Dosya çalışma ağacında eksikti; index'teki kopyasından geri yüklendi.
- Tek env şablonu: `backend/.env.example` (kökteki eski, eksik `.env.example` kaldırıldı). Doküman ve script'ler artık doğru hedefi, yani kök `.env`'i gösteriyor (PR #95).
- Kökteki `launch_dev.ps1`, `status_dev.ps1`, `stop_dev.ps1` sarmalayıcıları kaldırıldı. Asıl betikler `scripts/` altında duruyor ve README de onları gösteriyor.
- `ruff check backend/` hatasız geçecek şekilde yeni test/script dosyalarındaki 13 lint hatası düzeltildi (import sırası, kullanılmayan import, `;` ile birleştirilmiş satırlar, fixture re-export için `# ruff: noqa: F811`). Davranış değişmedi.
- Yerel `.env` içindeki `LLM_API_KEY` ve `GEMINI_API_KEY` yeni anahtara güncellendi. `.env` git'te ignore ediliyor, commit edilmedi.

## 2. Test sonuçları

| Kontrol | Sonuç |
|---|---|
| Backend `pytest backend/tests` | **848 geçti**, 0 başarısız, 22 deselected (önceki audit ile aynı: 848) |
| Deselected 22 test | `integration` / `external` / `e2e` marker'ları; `pytest.ini` varsayılan olarak hariç tutuyor. Bu gece **çalıştırılmadı**. |
| `ruff check backend/` | Geçti (düzeltmelerden sonra) |
| Web `npm run lint` | Geçti |
| Web `npm test` | 217 / 217 geçti |
| Web `npm run build` | Geçti |
| Web `npm run test:e2e` (Playwright) | Çalıştırılmadı |

## 3. Gemini API — gerçek test

- `backend.config.Config` üzerinden anahtar yüklendi; `LLM_API_KEY == GEMINI_API_KEY` doğrulandı.
- `generateContent` (`gemini-3.5-flash-lite`): **başarılı**, beklenen cevap döndü.
- `embedContent` (`models/gemini-embedding-2`): **başarılı**, 3072 boyutlu vektör (DB şemasıyla uyumlu).
- Güncel kodla backend 5001 portunda yerel olarak başlatıldı ve `POST /api/ai/chat` çağrıldı: HTTP 200, cevap üretildi, **ama `status: lexical_fallback`, `degraded: true`, `degraded_reason: semantic_unavailable`**. Embedding (~850 ms) ve LLM (~1,3 s) çalıştı; semantik arama çalışmadı (sebep madde 7 ve 10'da).

## 4. Commit ve push

- `9bc8f0a`: AI subsystem audit commit'i.
- Ardından bu dosya ayrı bir docs commit'iyle eklendi.
- Push: `origin/ai-subsystem-audit` (force push yok). PR: #95 (merge edilmedi). Dependabot PR'ları #87–#94 merge edildi, #91 (gotrue) supabase pini yüzünden kapatıldı.

## 5. Commit edilmeyen değişiklikler

- `.env` (kök): gizli bilgi, ignore ediliyor, asla commit edilmez.
- `backend/evaluation/cache/` (`book_embeddings.npz`, `embedding_consistency.json`): üretim embedding snapshot'ı, ignore ediliyor.
- `web/node_modules`, `web/.next`: `npm ci` / build çıktısı, ignore ediliyor.

## 6. Migration ve veritabanı işleri (bu gece hiçbiri uygulanmadı)

- `backend/scripts/05_phase3_performance.sql`, `09_learning_notes.sql`, `10_learning_notes_idempotency_and_review.sql`: yarın ayrıca incelenecek, uygulanmadı.
- Audit notuna göre üretim DB'sinde `public.match_book_embeddings` RPC'si yoktu (bkz. `backend/tests/test_personalized_degraded_status.py` docstring'i). Kişisel öneriler bu yüzden TF-IDF'e düşüyor.
- `backend/scripts/hardening/*_DRAFT_*` dosyaları taslak; uygulanmadı.
- Embedding backfill başlatılmadı.

## 7. RAG / semantik arama: hâlâ doğrulanmamış noktalar

- **Yerelde semantik arama hiç çalışmadı.** Supabase istemcisi başlatılamıyor: `.env`'deki `SUPABASE_ANON_KEY` yeni tip publishable key (`sb_publishable_...`), kurulu `supabase-py 2.3.8` ise yalnızca legacy JWT anahtarı kabul ediyor (`requirements.txt`: `supabase~=2.3.0`). `/api/health/ready` → 503 "Database unavailable".
- Vector RPC'lerin (`match_book_embeddings`, `match_query_embeddings`) üretimde var olduğu ve doğru sonuç döndürdüğü uçtan uca doğrulanmadı.
- `gemini-embedding-2` + `taskType` alanı: istemci docstring'i modelin bu alanı desteklemediğini söylüyor, ama `RETRIEVAL_DOCUMENT` ile yapılan çağrı hata vermedi. Alanın yok sayılıp sayılmadığı, dolayısıyla query/document embedding tutarlılığı doğrulanmadı.
- Değerlendirme etiketlerinin tamamı (1.184 satır) geçici LLM etiketi; insan tarafından gözden geçirilmiş etiket yok (`backend/evaluation/README.md`).
- `integration` / `external` / `e2e` testleri (22 adet) çalıştırılmadı.

## 8. Yarın ilk 3 iş

1. **Supabase anahtar uyumsuzluğunu çöz:** ya `.env`'e Dashboard → Project Settings → API Keys → *Legacy API keys* altındaki `anon` JWT'yi koy, ya da `supabase-py`'yi ≥ 2.18'e yükselt (requirements'taki `gotrue`/`httpx` notuna dikkat). Sonra `/api/health/ready` 200 dönmeli.
2. **Migration 05 / 09 / 10'u ve eksik vector RPC'yi incele**, staging'de dene, sonra üretime uygula. Ardından `/api/ai/chat` yanıtında `retrieval_mode` artık lexical olmamalı, `degraded` false olmalı.
3. **PR #95'i gözden geçir ve merge et** (CI yeşilse), ardından `integration` / `external` testlerini çalıştır.

## 9. Yerelde başlatma

~~~powershell
# Kök dizinde .env olmalı (config.py kök .env'i okur)
pip install -r backend/requirements-test.txt
python -m backend.app                      # http://localhost:5000

cd web; npm ci; npm run dev                # http://localhost:3000

# Ya da ikisi birden (Windows):
.\scripts\launch_dev.ps1                   # durdurmak: .\scripts\stop_dev.ps1
~~~

Kontroller:

~~~bash
ruff check backend/ && python -m pytest backend/tests -q
cd web && npm run lint && npm test && npm run build
~~~

Not: `.env`'de `DEBUG=False` ve gerçek bir `SECRET_KEY` yoksa backend production kontrolüne takılıp açılmıyor. Bu gece test için yalnızca o sürece `DEBUG=True` ve geçici `SECRET_KEY` verildi; `.env` değiştirilmedi.

## 10. Bilinen hatalar / dikkat

- **Port 5000'deki Docker konteyneri** (`libris_backend`, imaj 2026-11-04 tarihli) eski kodu çalıştırıyor; bu branch'in değişikliklerini içermiyor. Güncel kodu denemek için ya imajı yeniden build edin (`docker compose up --build`) ya da başka portta yerel çalıştırın (`PORT=5001`).
- `backend/saved_model/tfidf.pkl` (~11,7 MB) yeniden eğitilip commit edildi; ayarlar değişirse yeniden üretilmeli (`test_model_artifact_validation.py`).
- Gemini anahtarı bu gece sohbete yapıştırıldı; gerekirse Google AI Studio'da yenisini oluşturup `.env`'de güncelleyin.
- Windows'ta testler bittikten sonra pgserver'dan zararsız bir "I/O operation on closed file" log hatası çıkıyor; test sonucunu etkilemiyor.
