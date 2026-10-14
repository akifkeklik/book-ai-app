# Libris Database Hardening Draft SQL Scripts

> [!CAUTION]
> **BU DİZİNDEKİ DOSYALAR HAZIRLANMIŞ MIGRATION ADAYLARIDIR (STAGING CANDIDATES / NOT AUTOMATICALLY EXECUTED ON PROD).**  
> Bu betikler henüz canlı üretim veritabanında çalıştırılmamıştır. Yetkilendirilmiş bakım penceresinde Supabase SQL Editor üzerinden kontrollü şekilde uygulanmalıdır.

---

## 1. Dizin İçeriği ve Durum Matrisi

| Dosya | Durum | Amaç | Rollback Dosyası | Doğrulama Testi | Risk Seviyesi |
|---|:---:|---|---|---|:---:|
| [`01_DRAFT_revoke_dangerous_privileges.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/01_DRAFT_revoke_dangerous_privileges.sql) | **HAZIR** | `TRUNCATE` yetkilerinin kaldırılması, `books` anonim yazma politikalarının silinmesi, en az yetki matrisinin uygulanması. | `01_DRAFT_revoke_dangerous_privileges_rollback.sql` | CI Automated | Düşük (Sıfır veri riski) |
| [`02_DRAFT_reconcile_user_profiles.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/02_DRAFT_reconcile_user_profiles.sql) | **HAZIR** (Aşamalı) | Canlıdaki tek kayıt korunarak aşamalı çift-kolon (`user_id` + `id`) uyumluluğu ve eksik kolonların eklenmesi. | `02_DRAFT_reconcile_user_profiles_rollback.sql` | [`test_02_user_profiles_rollback_runtime.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/test_02_user_profiles_rollback_runtime.sql) (10 Senaryo) | Düşük (Geriye dönük uyumlu) |
| [`03_DRAFT_reconcile_interactions_and_trigger.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/03_DRAFT_reconcile_interactions_and_trigger.sql) | **HAZIR** (Model A) | Model A mimarisi: `favorites` kanonik tablosu ile `user_interactions` okuma durumlarının tam ayrıştırılması; okuma durumlarını ezmeyen/silmeyen koruyucu trigger. | `03_DRAFT_reconcile_interactions_and_trigger_rollback.sql` | [`test_03_interactions_and_trigger_runtime.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/test_03_interactions_and_trigger_runtime.sql) (8 Senaryo) | Düşük (Sıfır veri kaybı, Model A) |
| [`04_DRAFT_harden_vector_rpcs.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/04_DRAFT_harden_vector_rpcs.sql) | **HAZIR** | `match_query_embeddings`'e sabit `search_path` ve limit eklenmesi (`SECURITY INVOKER` korunur); canlıda eksik `match_book_embeddings` RPC'sinin tanımlanması. | `04_DRAFT_harden_vector_rpcs_rollback.sql` | [`test_04_vector_rpc_catalog_lifecycle.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/test_04_vector_rpc_catalog_lifecycle.sql) | Düşük (Fonksiyon DDL) |

---

## 2. Kritik Güvenlik ve Mimari Kararlar

1. **`01_DRAFT` Güvenliği:** Rollback betiği, RLS'i etkisiz kılan `TRUNCATE` yetkisini ASLA geri vermez (Fail-Safe Rollback).
2. **`02_DRAFT` Aşamalı Uyumluluğu:** Doğrudan `ALTER RENAME` yerine `user_id` kolonu eklenmiş, mevcut `id` ile doldurulmuş ve çift yönlü senkronizasyon trigger'ı kurulmuştur. Böylece eski `id` sorgulayan ve yeni `user_id` sorgulayan tüm istemciler sıfır kesintiyle çalışır.
3. **`03_DRAFT` Model A Mimarisi:** `favorites` tablosu favori üyeliğinin kanonik deposudur. `user_interactions` okuma durumlarını (`want_to_read`, `reading`, `finished`) ve ML sinyallerini (`like`, `dislike`) bağımsız yönetir. Favorileme veya favoriden çıkarma okuma durumunu asla ezmez ve silmez.
4. **`04_DRAFT` Invoker Tercihi:** `match_query_embeddings` superuser haklarıyla çalıştırılmaması için `SECURITY INVOKER` olarak korunmuş; arama yolu ve bellek güvenliği `SET search_path` ve girdi tavanı (`safe_limit <= 100`) ile sağlanmıştır.

---

## 3. Uygulama Öncesi Zorunlu Kontroller (Gates)

1. **Yedekleme Kapısı:** Supabase Dashboard -> Database -> Backups üzerinden tam snapshot alınmalıdır.
2. **Preflight Kapısı:** [`backend/scripts/preflight_database_hardening.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/preflight_database_hardening.sql) çalıştırılarak ön durum kanıtları kaydedilmelidir.
3. **Sıralı Uygulama:** Dosyalar yetkilendirilmiş sırayla (01 -> 02 -> 03 -> 04) uygulanmalı ve her adım sonrası doğrulama sorguları çalıştırılmalıdır.
