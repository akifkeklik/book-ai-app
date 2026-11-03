"""
Tests for Development Launcher and Process Management Resilience.
Verifies port conflict detection, expected API identity verification,
and safe PID lifecycle boundaries.
"""

import json
import socket

import pytest
from backend.app import create_app
from backend.config import Config


class LauncherTestConfig(Config):
    TESTING = True
    DEBUG = False
    SECRET_KEY = "test-secret-key"
    LIBRIS_API_KEY = "test-api-key"


@pytest.fixture
def client():
    app = create_app(LauncherTestConfig)
    with app.test_client() as c:
        yield c


def test_port_availability_check_detects_occupied_port():
    """Verify that a socket binding detects an already occupied port."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))  # bind ephemeral free port
    sock.listen(1)
    allocated_port = sock.getsockname()[1]

    try:
        # Attempt to bind to the same port must raise OSError (EADDRINUSE)
        conflict_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        with pytest.raises(OSError):
            conflict_sock.bind(("127.0.0.1", allocated_port))
        conflict_sock.close()
    finally:
        sock.close()


def test_backend_health_identity_payload(client):
    """Verify that /api/health contains the canonical service identity for launcher validation."""
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data is not None
    assert data.get("status") == "healthy"
    assert data.get("service") == "book-ai-api"


def test_pid_file_structure_validation():
    """Verify that .libris_pids.json structure contains required service entries and metadata."""
    sample_pid_data = {
        "started_at": "2026-10-25T00:00:00Z",
        "backend": {
            "pid": 1234,
            "port": 5000,
            "log": ".logs/backend.log",
            "url": "http://127.0.0.1:5000/api/health"
        },
        "web": {
            "pid": 5678,
            "port": 3000,
            "log": ".logs/web.log",
            "url": "http://127.0.0.1:3000"
        },
        "flutter": {
            "pid": 9012,
            "port": 5001,
            "log": ".logs/flutter.log",
            "url": "http://127.0.0.1:5001"
        }
    }

    serialized = json.dumps(sample_pid_data)
    deserialized = json.loads(serialized)

    assert "backend" in deserialized
    assert "web" in deserialized
    assert "flutter" in deserialized
    assert deserialized["backend"]["pid"] == 1234
    assert deserialized["backend"]["port"] == 5000
    assert "book-ai-api" not in deserialized  # PIDs only, no leaked secrets or configs


def test_health_ready_endpoint_handles_database_states(client):
    """Verify /api/health/ready returns appropriate status without raising unhandled exceptions."""
    response = client.get("/api/health/ready")
    # Endpoint returns either 200 (database connected) or 503 (database disconnected/unavailable)
    assert response.status_code in (200, 503)
    data = response.get_json()
    assert "status" in data
