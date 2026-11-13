#!/usr/bin/env bash
# Libris — Development Stack Health & Status Inspector (Unix/macOS/Linux)
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="${REPO_ROOT}/.libris_pids.json"

if [ ! -f "${PID_FILE}" ]; then
    echo "[WARN] No .libris_pids.json found. The stack is not running via launch_dev."
    exit 0
fi

echo "=== LIBRIS SPRINT 15 — STACK STATUS INSPECTOR (BASH) ==="

check_status() {
    local name=$1
    local port=$2
    local probe_url=$3
    echo -n "[$name on port $port]: "
    if curl -s -f "$probe_url" >/dev/null 2>&1; then
        echo "RUNNING & HEALTHY (HTTP 200)"
    else
        echo "NOT RESPONDING or DOWN"
    fi
}

check_status "Backend" "5000" "http://127.0.0.1:5000/api/health"
check_status "Web" "3000" "http://127.0.0.1:3000"
