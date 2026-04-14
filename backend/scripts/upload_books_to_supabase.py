import os
import sys
import pandas as pd
from supabase import create_client, Client

# Üst klasördeki config.py'ye ulaşmak için yolu ekleyelim
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import Config

def log(msg):
    print(msg)
    with open("upload_log.txt", "a", encoding="utf-8") as f:
        f.write(str(msg) + "\n")

def upload_to_supabase():
    if os.path.exists("upload_log.txt"):
        os.remove("upload_log.txt")
    log("Başladı...")
    url: str = Config.SUPABASE_URL
    key: str = Config.SUPABASE_ANON_KEY
    if not url or not key:
        log("HATA: SUPABASE_URL veya SUPABASE_ANON_KEY bulunamadı.")
        return

    # Supabase isimli kütüphaneyi initialize ediyoruz
    supabase: Client = create_client(url, key)

    data_path = Config.DATA_PATH
    if not os.path.exists(data_path):
        log(f"HATA: {data_path} bulunamadı.")
        return

    log("CSV dosyası okunuyor...")
    df = pd.read_csv(data_path)
    
    # Null veya NaN olan verileri SQL için None (null) tipine dönüştürelim
    df = df.where(pd.notnull(df), None)

    records = df.to_dict(orient="records")
    
    import math
    for row in records:
        for k, v in row.items():
            if isinstance(v, float) and math.isnan(v):
                row[k] = None

    total = len(records)
    log(f"Toplam {total} kayıt bulundu. Supabase'e yükleniyor...")

    batch_size = 500  # 500'erli yığınlar halinde yükleyelim ki timeout olmasın
    for i in range(0, total, batch_size):
        batch = records[i:i + batch_size]
        try:
            # upsert metodu sayesinde aynı isbn'den varsa üzerine yazar
            response = supabase.table('books').upsert(batch).execute()
            log(f"Yüklendi: {i + len(batch)} / {total}")
        except Exception as e:
            log(f"Hata oluştu ({i}. kayıtta): {e}")

    log("Yükleme başarıyla tamamlandı!")

if __name__ == "__main__":
    upload_to_supabase()
