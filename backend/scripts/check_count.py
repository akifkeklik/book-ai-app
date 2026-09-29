import os
import sys

from supabase import Client, create_client

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def load_dotenv(): pass  # noqa: E731
from config import Config  # noqa: E402


def check_count():
    url: str = Config.SUPABASE_URL
    key: str = Config.SUPABASE_ANON_KEY
    supabase: Client = create_client(url, key)
    res = supabase.table("books").select("isbn13", count="exact").execute()
    print(f"COUNT: {res.count}")


if __name__ == "__main__":
    check_count()
