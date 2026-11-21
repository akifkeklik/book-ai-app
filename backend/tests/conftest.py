"""
Default test runs never reach external services.

backend/config.py loads the repository's .env at import, so on a developer machine the global
container is wired to the real Gemini, Supabase and Google Books clients. Without this guard,
API tests that go through that container would call those services (spending quota and
touching real data), and importing the routes module would read the catalog ISBNs from
Supabase; CI only stayed offline because it has no secrets.

External (non-loopback) connections and DNS lookups are refused
- while tests are collected (module imports build the global container), and
- in every test not marked integration / external / e2e.
The adapters then take their normal offline fallbacks. Loopback stays open for the local
PostgreSQL used by integration tests and for in-process servers.
"""

import socket

import pytest

_LIVE_MARKERS = ("integration", "external", "e2e")
_LOOPBACK = {"127.0.0.1", "::1", "localhost", "0.0.0.0", None}
_REAL = (socket.socket.connect, socket.socket.connect_ex, socket.getaddrinfo)


def _host(address):
    return address[0] if isinstance(address, tuple) else address


def _connect(sock, address):
    if _host(address) not in _LOOPBACK:
        raise OSError(f"external network refused in tests: {_host(address)}")
    return _REAL[0](sock, address)


def _connect_ex(sock, address):
    if _host(address) not in _LOOPBACK:
        raise OSError(f"external network refused in tests: {_host(address)}")
    return _REAL[1](sock, address)


def _getaddrinfo(host, *args, **kwargs):
    if host not in _LOOPBACK:
        raise socket.gaierror(f"external DNS refused in tests: {host}")
    return _REAL[2](host, *args, **kwargs)


def _install():
    socket.socket.connect, socket.socket.connect_ex, socket.getaddrinfo = _connect, _connect_ex, _getaddrinfo


def _restore():
    socket.socket.connect, socket.socket.connect_ex, socket.getaddrinfo = _REAL


def pytest_collectstart(collector):
    _install()


def pytest_collection_finish(session):
    _restore()


@pytest.fixture(autouse=True)
def _refuse_external_network(request):
    if any(request.node.get_closest_marker(m) for m in _LIVE_MARKERS):
        yield
        return
    _install()
    try:
        yield
    finally:
        _restore()
