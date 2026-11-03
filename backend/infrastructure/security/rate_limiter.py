"""
Rate Limiter Infrastructure for Libris API.

Provides tiered rate limiting across single-worker and multi-worker deployments:
- InMemoryRateLimiter: Thread-safe, sliding-window in-memory limiter with bounded capacity guard.
- RedisRateLimiter: Distributed sliding-window limiter using atomic Redis sorted sets,
  enabling strict rate-limit enforcement across multiple WSGI/Gunicorn worker processes
  and horizontally scaled container replicas.
"""

import logging
import os
import threading
import time
from abc import ABC, abstractmethod
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


class BaseRateLimiter(ABC):
    """Abstract rate limiter interface."""

    @abstractmethod
    def check(
        self, bucket_key: str, limit: int, window: int = 60
    ) -> Tuple[bool, int, bool]:
        """
        Check whether the request is allowed under the rate limit.

        Returns:
            (allowed: bool, retry_after: int, is_overloaded: bool)
            - allowed: True if request is within limit, False otherwise.
            - retry_after: Seconds until next slot is available (if allowed is False).
            - is_overloaded: True if the limiter reached its hard capacity cap (returns 503).
        """
        pass

    @abstractmethod
    def clear(self) -> None:
        """Reset all rate limiter state (used for testing isolation)."""
        pass

    @abstractmethod
    def get_active_buckets_count(self) -> int:
        """Return the number of active tracked buckets."""
        pass


class InMemoryRateLimiter(BaseRateLimiter):
    """
    Thread-safe in-memory sliding window rate limiter.
    Bounded capacity guard protects against memory exhaustion under unique IP attacks.
    """

    def __init__(self, max_capacity: int = 10000):
        self._buckets: Dict[str, List[float]] = {}
        self._lock = threading.Lock()
        self._cleanup_time = time.time()
        self.max_capacity = max_capacity

    @property
    def buckets(self) -> Dict[str, List[float]]:
        """Expose raw dictionary for backwards-compatible test fixture access."""
        return self._buckets

    def check(
        self, bucket_key: str, limit: int, window: int = 60
    ) -> Tuple[bool, int, bool]:
        now = time.time()

        with self._lock:
            # 1. Periodic cleanup (at most once every 60s) to keep memory bounded
            if now - self._cleanup_time > window:
                for k in list(self._buckets.keys()):
                    self._buckets[k] = [t for t in self._buckets[k] if now - t < window]
                    if not self._buckets[k]:
                        del self._buckets[k]
                self._cleanup_time = now

            # 2. Hard capacity cap guard (DoS / IP spoofing protection)
            if len(self._buckets) > self.max_capacity:
                logger.warning(
                    f"Rate limiter capacity reached ({len(self._buckets)} > {self.max_capacity}). Service overloaded."
                )
                return False, 0, True

            # 3. Check existing bucket
            if bucket_key in self._buckets:
                reqs = [t for t in self._buckets[bucket_key] if now - t < window]
                if len(reqs) >= limit:
                    retry_after = max(1, int(window - (now - reqs[0])))
                    return False, retry_after, False
                reqs.append(now)
                self._buckets[bucket_key] = reqs
                return True, 0, False
            else:
                self._buckets[bucket_key] = [now]
                return True, 0, False

    def clear(self) -> None:
        with self._lock:
            self._buckets.clear()
            self._cleanup_time = time.time()

    def get_active_buckets_count(self) -> int:
        with self._lock:
            return len(self._buckets)


class RedisRateLimiter(BaseRateLimiter):
    """
    Distributed Redis-backed sliding window rate limiter.
    Ensures multi-worker Gunicorn and multi-pod deployments enforce identical rate limits.

    Uses an atomic Redis Lua script to eliminate race conditions across concurrent workers.
    Supports explicit failure policies:
    - 'fail_closed' (default): Rejects requests (503) when distributed Redis is unavailable,
      preventing silent degradation into multiplied per-worker quotas on protected endpoints.
    - 'fallback_local': Falls back to localized InMemoryRateLimiter per worker process.
    - 'fail_open': Allows requests when Redis is unavailable.
    """

    # Atomic Lua script for sliding window rate limiting
    LUA_SLIDING_WINDOW = """
    local key = KEYS[1]
    local now = tonumber(ARGV[1])
    local window = tonumber(ARGV[2])
    local limit = tonumber(ARGV[3])
    local clear_before = now - window
    local member = ARGV[4]
    local expire_ttl = window + 10

    -- 1. Remove expired entries outside sliding window
    redis.call('ZREMRANGEBYSCORE', key, 0, clear_before)

    -- 2. Count active entries in current window
    local current_count = redis.call('ZCARD', key)

    if current_count >= limit then
        local earliest = redis.call('ZRANGE', key, 0, 0, 'WITHSCORES')
        local earliest_score = 0
        if earliest and #earliest > 0 then
            earliest_score = tonumber(earliest[2])
        end
        return {0, current_count, earliest_score}
    else
        -- 3. Atomically add current request and refresh key expiration
        redis.call('ZADD', key, now, member)
        redis.call('EXPIRE', key, expire_ttl)
        return {1, current_count + 1, 0}
    end
    """

    def __init__(
        self,
        redis_url: str,
        key_prefix: str = "libris:ratelimit:",
        failure_policy: Optional[str] = None,
    ):
        self.redis_url = redis_url
        self.key_prefix = key_prefix
        if failure_policy:
            self.failure_policy = failure_policy.strip().lower()
        else:
            self.failure_policy = os.getenv(
                "RATE_LIMITER_FAILURE_POLICY", "fail_closed"
            ).strip().lower()

        self._client = None
        self._fallback = InMemoryRateLimiter()
        self._init_client()

    def _init_client(self):
        try:
            import redis

            self._client = redis.from_url(
                self.redis_url,
                socket_timeout=2.0,
                socket_connect_timeout=2.0,
                decode_responses=True,
            )
            self._client.ping()
            logger.info("Distributed Redis rate limiter connected successfully.")
        except Exception as exc:
            logger.warning(
                f"Redis rate limiter connection failed ({exc}). "
                f"Failure policy is '{self.failure_policy}'."
            )
            self._client = None

    def check(
        self, bucket_key: str, limit: int, window: int = 60
    ) -> Tuple[bool, int, bool]:
        if not self._client:
            return self._handle_failure(bucket_key, limit, window, "Redis client not initialized")

        now = time.time()
        redis_key = f"{self.key_prefix}{bucket_key}"
        member = f"{now}:{time.perf_counter_ns()}"

        try:
            # Execute atomic sliding-window check via Lua script
            res = self._client.eval(
                self.LUA_SLIDING_WINDOW,
                1,
                redis_key,
                str(now),
                str(window),
                str(limit),
                member,
            )

            # res: [allowed (0 or 1), current_count, earliest_score]
            allowed = bool(res[0])
            _current_count = int(res[1])
            earliest_score = float(res[2]) if len(res) > 2 and res[2] else 0.0

            if not allowed:
                if earliest_score > 0:
                    retry_after = max(1, int(window - (now - earliest_score)))
                else:
                    retry_after = window
                return False, retry_after, False

            return True, 0, False

        except Exception as exc:
            return self._handle_failure(bucket_key, limit, window, str(exc))

    def _handle_failure(
        self, bucket_key: str, limit: int, window: int, reason: str
    ) -> Tuple[bool, int, bool]:
        """Enforces configured failure policy when Redis is unavailable."""
        if self.failure_policy == "fail_closed":
            logger.error(
                f"Redis rate limiter error ({reason}). "
                "Enforcing fail-closed policy (503 Service Overloaded/Degraded)."
            )
            return False, window, True
        elif self.failure_policy == "fail_open":
            logger.warning(
                f"Redis rate limiter error ({reason}). Enforcing fail-open policy."
            )
            return True, 0, False
        else:
            # 'fallback_local'
            logger.warning(
                f"Redis rate limiter error ({reason}). "
                "Falling back to local in-memory rate limiter."
            )
            return self._fallback.check(bucket_key, limit, window)

    def clear(self) -> None:
        if self._client:
            try:
                keys = self._client.keys(f"{self.key_prefix}*")
                if keys:
                    self._client.delete(*keys)
            except Exception as exc:
                logger.warning(f"Failed clearing Redis rate limiter keys: {exc}")
        if hasattr(self, "_fallback"):
            self._fallback.clear()

    def get_active_buckets_count(self) -> int:
        if self._client:
            try:
                keys = self._client.keys(f"{self.key_prefix}*")
                return len(keys)
            except Exception:
                return 0
        if hasattr(self, "_fallback"):
            return self._fallback.get_active_buckets_count()
        return 0


# Singleton instance
_limiter_instance: Optional[BaseRateLimiter] = None
_limiter_lock = threading.Lock()


def get_rate_limiter() -> BaseRateLimiter:
    """Factory returning the active rate limiter singleton."""
    global _limiter_instance
    if _limiter_instance is None:
        with _limiter_lock:
            if _limiter_instance is None:
                redis_url = os.getenv("REDIS_URL", "").strip()
                if redis_url:
                    try:
                        import redis  # noqa: F401

                        _limiter_instance = RedisRateLimiter(redis_url)
                    except ImportError:
                        logger.warning(
                            "REDIS_URL is configured but 'redis' package is not installed. "
                            "Using InMemoryRateLimiter."
                        )
                        _limiter_instance = InMemoryRateLimiter()
                else:
                    _limiter_instance = InMemoryRateLimiter()
    return _limiter_instance
