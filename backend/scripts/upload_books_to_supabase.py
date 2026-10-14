import os
import sys

import pandas as pd
from supabase import Client, create_client

# Üst klasördeki config.py'ye ulaşmak için yolu ekleyelim
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import Config


def log(msg):
    print(msg)
    with open("upload_log.txt", "a", encoding="utf-8") as f:
        f.write(str(msg) + "\n")


def upload_to_supabase(csv_path=None):
    if os.path.exists("upload_log.txt"):
        try:
            os.remove("upload_log.txt")
        except OSError:
            pass
    log("Başladı...")
    url: str = os.getenv("SUPABASE_URL") or Config.SUPABASE_URL
    service_role_key: str = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")

    if not url:
        log("HATA: SUPABASE_URL tanımlı değil.")
        raise ValueError("SUPABASE_URL environment variable is required.")

    if not service_role_key:
        log("HATA: SUPABASE_SERVICE_ROLE_KEY bulunamadı. Anonim anahtarla yükleme yapılamaz (Fail-closed).")
        raise ValueError("SUPABASE_SERVICE_ROLE_KEY is required for administrative book catalog ingestion.")

    # Ayrıcalıklı Supabase istemcisi yalnızca bu script kapsamında oluşturulur
    supabase: Client = create_client(url, service_role_key)

    data_path = csv_path or Config.DATA_PATH
    if not os.path.exists(data_path):
        log(f"HATA: {data_path} bulunamadı.")
        raise FileNotFoundError(f"Data file not found: {data_path}")

    log("CSV dosyası okunuyor...")
    df = pd.read_csv(data_path)

    # Null veya NaN olan verileri SQL için None (null) tipine dönüştürelim
    df = df.where(pd.notnull(df), None)

    records = df.to_dict(orient="records")

    import math

    for row in records:
        for k, v in row.items():
            if isinstance(v, float):
                if math.isnan(v):
                    row[k] = None
                elif v.is_integer():
                    row[k] = int(v)

    total = len(records)
    log(f"Toplam {total} kayıt bulundu. Supabase'e yükleniyor...")

    batch_size = 500  # 500'erli yığınlar halinde yükleyelim ki timeout olmasın
    for i in range(0, total, batch_size):
        batch = records[i : i + batch_size]
        try:
            # upsert metodu sayesinde aynı isbn'den varsa üzerine yazar
            supabase.table("books").upsert(batch).execute()
            log(f"Yüklendi: {i + len(batch)} / {total}")
        except Exception as e:
            # Secret sızıntısını önlemek için hata mesajından servis anahtarını maskele
            err_msg = str(e)
            if service_role_key and service_role_key in err_msg:
                err_msg = err_msg.replace(service_role_key, "[REDACTED]")
            log(f"Hata oluştu ({i}. kayıtta): {err_msg}")
            raise

    log("Yükleme başarıyla tamamlandı!")
    return total


if __name__ == "__main__":
    upload_to_supabase()
