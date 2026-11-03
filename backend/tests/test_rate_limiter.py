import concurrent.futures

import pytest
from backend.routes.routes import _ai_rate_limits, rate_limit_ai
from flask import Flask, jsonify

app = Flask(__name__)


@app.before_request
def setup_test_auth():
    from flask import g, request

    if request.headers.get("X-Test-User"):
        g.user_id = request.headers.get("X-Test-User")
    if request.headers.get("X-Test-Server"):
        g.is_server = True


@app.route("/test_limit", methods=["GET"])
@rate_limit_ai
def dummy_route():
    return jsonify({"success": True}), 200


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        # Reset the dict before each test
        _ai_rate_limits.clear()
        yield client


def test_rate_limiter_allows_under_limit(client):
    for _ in range(5):
        resp = client.get("/test_limit", environ_base={"REMOTE_ADDR": "127.0.0.1"})
        assert resp.status_code == 200


def test_rate_limiter_blocks_over_limit(client):
    for _ in range(5):
        resp = client.get("/test_limit", environ_base={"REMOTE_ADDR": "127.0.0.1"})
        assert resp.status_code == 200

    # 6th request should fail
    resp = client.get("/test_limit", environ_base={"REMOTE_ADDR": "127.0.0.1"})
    assert resp.status_code == 429
    assert "Retry-After" in resp.headers


def test_rate_limiter_isolates_users(client):
    for _ in range(5):
        resp = client.get("/test_limit", environ_base={"REMOTE_ADDR": "127.0.0.1"})
        assert resp.status_code == 200

    # Another user should succeed
    resp = client.get("/test_limit", environ_base={"REMOTE_ADDR": "127.0.0.2"})
    assert resp.status_code == 200


def test_rate_limiter_proxy_header(client):
    # Verify that X-Forwarded-For is ignored to prevent IP spoofing bypass
    for _ in range(5):
        resp = client.get(
            "/test_limit",
            headers={"X-Forwarded-For": "10.0.0.1, 192.168.1.1"},
            environ_base={"REMOTE_ADDR": "127.0.0.1"},
        )
        assert resp.status_code == 200

    resp = client.get(
        "/test_limit",
        headers={"X-Forwarded-For": "10.0.0.1"},
        environ_base={"REMOTE_ADDR": "127.0.0.1"},
    )
    assert resp.status_code == 429

    # Even with a different spoofed IP in header, it should still be blocked because REMOTE_ADDR is the same
    resp = client.get(
        "/test_limit",
        headers={"X-Forwarded-For": "10.0.0.2"},
        environ_base={"REMOTE_ADDR": "127.0.0.1"},
    )
    assert resp.status_code == 429


def test_rate_limiter_authenticated_user_tier(client):
    # Authenticated users have a limit of 10 requests / 60 seconds
    for _ in range(10):
        resp = client.get(
            "/test_limit",
            headers={"X-Test-User": "auth-user-99"},
            environ_base={"REMOTE_ADDR": "127.0.0.1"},
        )
        assert resp.status_code == 200

    # 11th request for this user is rate-limited
    resp = client.get(
        "/test_limit",
        headers={"X-Test-User": "auth-user-99"},
        environ_base={"REMOTE_ADDR": "127.0.0.1"},
    )
    assert resp.status_code == 429


def test_rate_limiter_server_tier(client):
    # Server callers have a limit of 30 requests / 60 seconds
    for _ in range(30):
        resp = client.get(
            "/test_limit",
            headers={"X-Test-Server": "true"},
            environ_base={"REMOTE_ADDR": "10.0.0.5"},
        )
        assert resp.status_code == 200

    # 31st request is rate-limited
    resp = client.get(
        "/test_limit",
        headers={"X-Test-Server": "true"},
        environ_base={"REMOTE_ADDR": "10.0.0.5"},
    )
    assert resp.status_code == 429


def test_rate_limiter_capacity_guard_returns_503(client):
    # When bucket capacity exceeds 10000, returns 503 Service Overloaded
    try:
        for i in range(10001):
            _ai_rate_limits[f"fake_bucket:{i}"] = [1000.0]
        resp = client.get("/test_limit", environ_base={"REMOTE_ADDR": "127.0.0.1"})
        assert resp.status_code == 503
        data = resp.get_json()
        assert "Rate limiter capacity reached" in data.get("error", "")
    finally:
        _ai_rate_limits.clear()


def test_rate_limiter_concurrency():
    _ai_rate_limits.clear()

    def make_req():
        with app.test_request_context("/test_limit", environ_base={"REMOTE_ADDR": "127.0.0.1"}):
            return dummy_route()[1]

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        results = list(executor.map(lambda _: make_req(), range(10)))

    successes = results.count(200)
    failures = results.count(429)
    assert successes == 5
    assert failures == 5


def test_in_memory_rate_limiter_interface():
    from backend.infrastructure.security.rate_limiter import InMemoryRateLimiter

    limiter = InMemoryRateLimiter(max_capacity=5)
    assert limiter.get_active_buckets_count() == 0

    # Bucket 1: 3 requests allowed with limit=3
    for _ in range(3):
        allowed, retry_after, overloaded = limiter.check("user:1", limit=3, window=60)
        assert allowed is True
        assert overloaded is False

    # 4th request blocked
    allowed, retry_after, overloaded = limiter.check("user:1", limit=3, window=60)
    assert allowed is False
    assert retry_after > 0
    assert overloaded is False
    assert limiter.get_active_buckets_count() == 1

    # Clear resets
    limiter.clear()
    assert limiter.get_active_buckets_count() == 0


def test_redis_rate_limiter_lua_eval_mock():
    """Verify that RedisRateLimiter executes sliding window atomic Lua script and enforces limits."""
    import time
    from unittest.mock import MagicMock

    from backend.infrastructure.security.rate_limiter import RedisRateLimiter

    mock_client = MagicMock()

    # 1. Simulate request within quota: eval returns [1 (allowed), current_count=1, earliest=0]
    mock_client.eval.return_value = [1, 1, 0]

    limiter = RedisRateLimiter("redis://mock:6379/0", failure_policy="fail_closed")
    limiter._client = mock_client

    allowed, retry_after, overloaded = limiter.check("test:ip", limit=5, window=60)
    assert allowed is True
    assert retry_after == 0
    assert overloaded is False
    assert mock_client.eval.called

    # 2. Simulate blocked request: eval returns [0 (blocked), current_count=5, earliest=now-10]
    mock_client.eval.return_value = [0, 5, time.time() - 10]
    allowed, retry_after, overloaded = limiter.check("test:ip", limit=5, window=60)
    assert allowed is False
    assert retry_after > 0
    assert overloaded is False


def test_redis_rate_limiter_fail_closed_policy_on_failure():
    """
    Verify that under the default 'fail_closed' policy, Redis drops trigger overloaded=True (503).
    This prevents distributed security guarantees from silently collapsing into local bypasses.
    """
    from unittest.mock import MagicMock

    from backend.infrastructure.security.rate_limiter import RedisRateLimiter

    mock_client = MagicMock()
    mock_client.eval.side_effect = Exception("Connection refused to Redis cluster")

    limiter = RedisRateLimiter("redis://mock:6379/0", failure_policy="fail_closed")
    limiter._client = mock_client

    # Should enforce fail-closed security for protected AI endpoints
    allowed, retry_after, overloaded = limiter.check("user:strict", limit=5, window=60)
    assert allowed is False
    assert retry_after == 60
    assert overloaded is True


def test_redis_rate_limiter_fallback_local_policy():
    """Verify that under 'fallback_local' policy, Redis failures fall back to in-memory check."""
    from unittest.mock import MagicMock

    from backend.infrastructure.security.rate_limiter import RedisRateLimiter

    mock_client = MagicMock()
    mock_client.eval.side_effect = Exception("Redis cluster partition")

    limiter = RedisRateLimiter("redis://mock:6379/0", failure_policy="fallback_local")
    limiter._client = mock_client

    # In-memory limiter handles the check
    allowed, retry_after, overloaded = limiter.check("user:fallback", limit=2, window=60)
    assert allowed is True
    assert overloaded is False


def test_multi_worker_architectural_contract_atomic():
    """
    Simulates multi-worker Gunicorn behavior with atomic Lua script execution:
    - Worker 1 and Worker 2 sharing RedisRateLimiter enforce shared global bucket.
    - Concurrent requests across workers strictly enforce configured limit.
    """
    import threading
    from unittest.mock import MagicMock

    from backend.infrastructure.security.rate_limiter import RedisRateLimiter

    # Shared fake redis datastore simulating multi-process memory
    shared_redis_zset = {}
    redis_lock = threading.Lock()

    def fake_eval(script, numkeys, key, now_str, window_str, limit_str, member):
        now = float(now_str)
        window = float(window_str)
        limit = int(limit_str)
        clear_before = now - window

        with redis_lock:
            # 1. Clear before
            if key in shared_redis_zset:
                shared_redis_zset[key] = {
                    val: score
                    for val, score in shared_redis_zset[key].items()
                    if score > clear_before
                }
            else:
                shared_redis_zset[key] = {}

            # 2. Count
            count = len(shared_redis_zset[key])
            if count >= limit:
                # Find earliest
                sorted_items = sorted(shared_redis_zset[key].items(), key=lambda x: x[1])
                earliest_score = sorted_items[0][1] if sorted_items else 0
                return [0, count, earliest_score]
            else:
                shared_redis_zset[key][member] = now
                return [1, count + 1, 0]

    mock_shared_redis = MagicMock()
    mock_shared_redis.eval = fake_eval

    worker1_limiter = RedisRateLimiter("redis://mock:6379/0", failure_policy="fail_closed")
    worker1_limiter._client = mock_shared_redis

    worker2_limiter = RedisRateLimiter("redis://mock:6379/0", failure_policy="fail_closed")
    worker2_limiter._client = mock_shared_redis

    # Worker 1 takes 3 requests (limit is 4)
    for _ in range(3):
        allowed, _, _ = worker1_limiter.check("ip:192.168.1.1", limit=4, window=60)
        assert allowed is True

    # Worker 2 takes 1 request -> reaches limit 4
    allowed, _, _ = worker2_limiter.check("ip:192.168.1.1", limit=4, window=60)
    assert allowed is True

    # 5th request to either Worker 1 or Worker 2 is immediately blocked!
    allowed1, retry1, _ = worker1_limiter.check("ip:192.168.1.1", limit=4, window=60)
    allowed2, retry2, _ = worker2_limiter.check("ip:192.168.1.1", limit=4, window=60)
    assert allowed1 is False
    assert allowed2 is False
    assert retry1 > 0
    assert retry2 > 0


