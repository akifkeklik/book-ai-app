import os
import sys
from supabase import create_client, Client
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import Config

def test_supabase():
    url: str = Config.SUPABASE_URL
    key: str = Config.SUPABASE_ANON_KEY
    if not url or not key:
        print("HATA: SUPABASE_URL veya SUPABASE_ANON_KEY eksik.")
        return
    
    try:
        supabase: Client = create_client(url, key)
        # Tablo boş bile olsa select'in çalışması lazım
        res = supabase.table('books').select('isbn13', count='exact').limit(1).execute()
        print(f"BAĞLANTI TAMAM. Satır sayısı tahmini: {res.count}")
    except Exception as e:
        print(f"HATA: {e}")

if __name__ == "__main__":
    test_supabase()
