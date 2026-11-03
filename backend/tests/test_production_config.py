import pytest
from backend.app import create_app
from backend.config import Config
from werkzeug.middleware.proxy_fix import ProxyFix


class MissingSecretProdConfig(Config):
    IS_PRODUCTION = True
    TESTING = False
    DEBUG = False
    SECRET_KEY = ""
    LIBRIS_API_KEY = "test-api-key"

class PlaceholderSecretProdConfig(Config):
    IS_PRODUCTION = True
    TESTING = False
    DEBUG = False
    SECRET_KEY = "replace-with-a-long-random-string"
    LIBRIS_API_KEY = "test-api-key"

class ValidProdConfig(Config):
    IS_PRODUCTION = True
    TESTING = False
    DEBUG = False
    SECRET_KEY = "strong-random-production-secret-key-32chars"
    LIBRIS_API_KEY = "test-api-key"
    NUM_PROXIES = 1
    ALLOWED_ORIGINS = ["https://app.example.com"]

class WildcardCorsProdConfig(ValidProdConfig):
    ALLOWED_ORIGINS = ["*"]

class DevConfig(Config):
    TESTING = True
    DEBUG = True
    SECRET_KEY = ""
    LIBRIS_API_KEY = "test-api-key"

class DebugEnabledProdConfig(Config):
    IS_PRODUCTION = True
    TESTING = False
    DEBUG = True
    SECRET_KEY = "strong-random-production-secret-key-32chars"
    LIBRIS_API_KEY = "valid-production-libris-api-key"

class MissingApiKeyProdConfig(Config):
    IS_PRODUCTION = True
    TESTING = False
    DEBUG = False
    SECRET_KEY = "strong-random-production-secret-key-32chars"
    LIBRIS_API_KEY = ""

class PlaceholderApiKeyProdConfig(Config):
    IS_PRODUCTION = True
    TESTING = False
    DEBUG = False
    SECRET_KEY = "strong-random-production-secret-key-32chars"
    LIBRIS_API_KEY = "replace-with-a-secure-random-api-key"

class DevSecretInProdConfig(Config):
    IS_PRODUCTION = True
    TESTING = False
    DEBUG = False
    SECRET_KEY = "dev-insecure-secret-key"
    LIBRIS_API_KEY = "valid-production-libris-api-key"

class DevApiKeyInProdConfig(Config):
    IS_PRODUCTION = True
    TESTING = False
    DEBUG = False
    SECRET_KEY = "strong-random-production-secret-key-32chars"
    LIBRIS_API_KEY = "dev-insecure-api-key"

def test_production_fails_when_secret_key_missing():
    with pytest.raises(ValueError, match="SECRET_KEY environment variable must be set"):
        create_app(MissingSecretProdConfig)

def test_production_fails_when_secret_key_is_placeholder():
    with pytest.raises(ValueError, match="SECRET_KEY environment variable must be set"):
        create_app(PlaceholderSecretProdConfig)

def test_production_fails_when_secret_key_is_dev_secret():
    with pytest.raises(ValueError, match="SECRET_KEY environment variable must be set"):
        create_app(DevSecretInProdConfig)

def test_production_fails_when_debug_enabled():
    with pytest.raises(ValueError, match="DEBUG mode cannot be enabled when running in production"):
        create_app(DebugEnabledProdConfig)

def test_production_fails_when_api_key_missing():
    with pytest.raises(ValueError, match="LIBRIS_API_KEY environment variable must be set"):
        create_app(MissingApiKeyProdConfig)

def test_production_fails_when_api_key_is_placeholder():
    with pytest.raises(ValueError, match="LIBRIS_API_KEY environment variable must be set"):
        create_app(PlaceholderApiKeyProdConfig)

def test_production_fails_when_api_key_is_dev_secret():
    with pytest.raises(ValueError, match="LIBRIS_API_KEY environment variable must be set"):
        create_app(DevApiKeyInProdConfig)

def test_production_rejects_wildcard_cors_origins():
    with pytest.raises(ValueError, match="ALLOWED_ORIGINS must contain explicit trusted origins"):
        create_app(WildcardCorsProdConfig)

def test_production_succeeds_with_strong_secret():
    app = create_app(ValidProdConfig)
    assert app.config["SECRET_KEY"] == "strong-random-production-secret-key-32chars"
    assert app.config["LIBRIS_API_KEY"] == "test-api-key"
    assert isinstance(app.wsgi_app, ProxyFix)

def test_dev_mode_permits_startup_without_custom_secret():
    app = create_app(DevConfig)
    assert app is not None

