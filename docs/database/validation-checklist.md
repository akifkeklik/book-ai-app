# Libris Database Hardening — Validation & Verification Checklist

**Tarih:** 2026-10-13  
**Kapsam:** Canlı Veritabanı Düzeltme Doğrulama Protokolü  
**İlke:** Canlı üretim verisi üzerinde yıkıcı test yapılmaz; testler izole senaryolar ve yetkilendirilmiş roller üzerinden doğrulanır.

---

## 1. SENARYO DOĞRULAMA PROTOKOLÜ

### Senaryo 1: Anonim Kullanıcı Kitap Kataloğu Okuma Erişimi
- **Amaç:** Anonim istemcinin kitap listesini ve arama sonuçlarını okuyabilmesi, ancak yazma yetkisinin olmaması.
- **Doğrulama Adımı:**
  ```sql
  -- Anon rolü taklit edilerek test edilir:
  SET ROLE anon;
  SELECT isbn13, title, authors FROM public.books LIMIT 5; -- Başarılı olmalı
  INSERT INTO public.books (isbn13, title) VALUES ('test-isbn', 'Test Book'); -- PERMISSION DENIED hatası vermeli!
  TRUNCATE TABLE public.books; -- PERMISSION DENIED hatası vermeli!
  RESET ROLE;
  ```
- **Beklenen Sonuç:** `SELECT` veriyi döner; `INSERT` ve `TRUNCATE` yetki hatası ile reddedilir (`permission denied for table books`).

---

### Senaryo 2: Kimliği Doğrulanmamış Kullanıcı Kişisel Veri İzolasyonu
- **Amaç:** Anonim rolün kullanıcı profillerine, favorilerine veya etkileşimlerine erişememesi.
- **Doğrulama Adımı:**
  ```sql
  SET ROLE anon;
  SELECT count(*) FROM public.favorites;          -- 0 satır dönmeli veya permission denied
  SELECT count(*) FROM public.user_profiles;       -- 0 satır dönmeli veya permission denied
  SELECT count(*) FROM public.user_interactions;   -- 0 satır dönmeli veya permission denied
  RESET ROLE;
  ```
- **Beklenen Sonuç:** Anonim istemci hiçbir kullanıcının kişisel kaydını göremez veya değiştiremez.

---

### Senaryo 3: Kullanıcı Kendi Favorilerini ve Etkileşimlerini Yönetebilir
- **Amaç:** Kimliği doğrulanmış bir kullanıcının RLS üzerinden yalnızca kendi satırlarını okuyup yazabilmesi.
- **Doğrulama Adımı:**
  ```sql
  -- auth.uid() simülasyonu ile test edilir:
  SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
  SET ROLE authenticated;
  -- Kendi kaydını ekleme
  INSERT INTO public.favorites (user_id, book_id, book_title) 
  VALUES ('00000000-0000-0000-0000-000000000001'::uuid, '9780441013593', 'Dune');
  -- Başkasının kaydını okumayı deneme
  SELECT * FROM public.favorites WHERE user_id = '00000000-0000-0000-0000-000000000002'::uuid; -- Boş dönmeli
  RESET ROLE;
  ```
- **Beklenen Sonuç:** Sadece kendi kaydını ekler ve listeler; başkasına ait veriye erişemez.

---

### Senaryo 4: Profil Yönetimi (Aşamalı Çift-Kolon Uyumluluğu)
- **Amaç:** Flutter ve Flask'in `user_id` alanı üzerinden sorgu ve upsert yapabilmesi, eski istemcilerin `id` ile çalışabilmesi.
- **Doğrulama Adımı:**
  ```sql
  -- 1. user_id ile sorgu
  SELECT user_id, preferred_genres, preferred_authors, preferred_vibe, reading_frequency 
  FROM public.user_profiles 
  LIMIT 1;

  -- 2. id ile sorgu (Eski istemci uyumluluğu)
  SELECT id, preferred_genres 
  FROM public.user_profiles 
  LIMIT 1;

  -- 3. Çift yönlü senkronizasyon trigger testi:
  -- Yeni istemci user_id ile yazarsa:
  INSERT INTO public.user_profiles (user_id, preferred_genres) 
  VALUES ('00000000-0000-0000-0000-000000000099'::uuid, '{"Sci-Fi"}')
  RETURNING id, user_id; -- id kolonu da otomatik dolmuş olmalıdır!
  ```
- **Beklenen Sonuç:** Her iki kolon da çalışır; canlıdaki tek kayıt korunur.

---

### Senaryo 5: Favori ve Okuma Durumu Regresyonu (BLOKE GRUP 3)
- **Amaç:** `user_interactions` tablosunda `reading` veya `finished` olarak işaretlenmiş bir kitabın durumunun ezilmemesi.
- **Ön Koşul:** Bu test Grup 3 mimari modeli (Model A vs Model B) onaylanana kadar canlıda çalıştırılamaz.
- **Senaryo Mantığı:**
  1. Kullanıcı kitaba `interaction_type = 'reading'` kaydeder.
  2. Kullanıcı kitabı `favorites` tablosuna ekler (`INSERT`).
  3. `SELECT interaction_type FROM user_interactions` kontrol edilir -> Değer **'reading'** olarak kalmalıdır (ezilmemelidir).
  4. Kullanıcı kitabı `favorites` tablosundan siler (`DELETE`).
  5. `SELECT interaction_type FROM user_interactions` kontrol edilir -> Satır silinmemiş, 'reading' olarak kalmalıdır.

---

### Senaryo 6: Idempotency (Tekrarlanabilirlik)
- **Amaç:** Migration dosyaları arka arkaya iki kez çalıştırıldığında hata üretmemesi ve durumu bozmaması.
- **Doğrulama Adımı:**
  `01_DRAFT_...`, `02_DRAFT_...` ve `04_DRAFT_...` dosyaları ikinci kez çalıştırılır.
- **Beklenen Sonuç:** Tüm `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION` ve `DROP POLICY IF EXISTS` ifadeleri sorunsuz tamamlanır.

---

### Senaryo 7: Vektör Arama ve RPC Yetkileri (INVOKER Modeli)
- **Amaç:** `match_query_embeddings` fonksiyonunun `SECURITY INVOKER` olarak güvenle çalışabilmesi.
- **Doğrulama Adımı:**
  ```sql
  SET ROLE anon;
  SELECT * FROM match_query_embeddings(
      (SELECT embedding FROM public.book_embeddings LIMIT 1), 
      0.0, 
      5
  );
  RESET ROLE;
  ```
- **Beklenen Sonuç:** Fonksiyon HNSW indeksini kullanarak ilk 5 benzer kitabı başarıyla döner; `safe_limit <= 100` sınırını korur.

---

### Senaryo 8: Rollback Güvenliği ve Tersinirlik
- **Amaç:** Geri dönüş betiklerinin tehlikeli yetkileri (`TRUNCATE`) geri vermeden güvenli duruma dönmesi.
- **Doğrulama Adımı:**
  Staging veritabanında `01_DRAFT_..._rollback.sql` çalıştırılır; `preflight_database_hardening.sql` Bölüm 2 ile TRUNCATE yetkisinin kapalı kaldığı teyit edilir.
- **Beklenen Sonuç:** TRUNCATE kapalı kalır, DML izinleri önceki duruma döner.

---

### Senaryo 9: Yerel CI ve Kod Testleri Uyumu
- **Amaç:** Yapılan şema ve yetki düzenlemelerinin yerel ve CI testlerini kırmaması.
- **Doğrulama Adımı:**
  1. Backend testleri: `PYTHONPATH=backend python -m pytest backend/tests/ -v --tb=short`
  2. Web testleri: `cd web && npm test`
- **Mevcut Sonuç:**
  - Backend: **198 test PASSED** (0 failed).
  - Web: **37 test PASSED** (0 failed).

---

## 2. CANLI UYGULAMA İÇİN GO/NO-GO İMZA KONTROLÜ

| Kontrol Maddesi | Durum | Doğrulayan |
|---|:---:|---|
| Canlı veritabanı yedeği alındı mı? | [ ] BEKLİYOR | Kullanıcı Onayı |
| Salt okunur preflight sorguları çalıştırıldı mı? | [ ] BEKLİYOR | Kullanıcı Onayı |
| Grup 1 (Yetkiler) uygulanması onaylandı mı? | [ ] BEKLİYOR | Kullanıcı Onayı |
| Grup 2 (user_profiles Aşamalı Uyumluluk) onaylandı mı? | [ ] BEKLİYOR | Kullanıcı Onayı |
| Grup 3 (user_interactions Model A / B) kararı verildi mi? | [ ] **BLOKE** | Kullanıcı Onayı |
| Grup 4 (Vektör RPC Güçlendirmesi) onaylandı mı? | [ ] BEKLİYOR | Kullanıcı Onayı |
| Sıfır canlı değişiklik kuralına uyuldu mu? | [x] TAMAMLANDI | Senior DB Engineer |
