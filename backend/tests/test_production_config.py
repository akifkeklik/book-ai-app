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

class DevConfig(Config):
    TESTING = True
    DEBUG = True
    SECRET_KEY = ""
    LIBRIS_API_KEY = "test-api-key"

def test_production_fails_when_secret_key_missing():
    with pytest.raises(ValueError, match="SECRET_KEY environment variable must be set"):
        create_app(MissingSecretProdConfig)

def test_production_fails_when_secret_key_is_placeholder():
    with pytest.raises(ValueError, match="SECRET_KEY environment variable must be set"):
        create_app(PlaceholderSecretProdConfig)

def test_production_succeeds_with_strong_secret():
    app = create_app(ValidProdConfig)
    assert app.config["SECRET_KEY"] == "strong-random-production-secret-key-32chars"
    assert isinstance(app.wsgi_app, ProxyFix)

def test_dev_mode_permits_startup_without_custom_secret():
    app = create_app(DevConfig)
    assert app is not None
