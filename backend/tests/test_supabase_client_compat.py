"""Guards against incompatible Supabase sub-package versions.

CI never configures SUPABASE_URL, so a broken client would otherwise only fail at runtime
(e.g. gotrue>=2.9 with httpx<0.26: "unexpected keyword argument 'proxy'").
"""

from supabase import create_client


def test_supabase_client_can_be_created_with_installed_versions():
    client = create_client("https://example.supabase.co", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.x")
    assert client is not None
