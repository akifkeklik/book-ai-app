#!/usr/bin/env bash
# Libris — Safe Development Stack Terminator (Unix/macOS/Linux)
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="${REPO_ROOT}/.libris_pids.json"

if [ ! -f "${PID_FILE}" ]; then
    echo "[WARN] No .libris_pids.json found. No tracked launcher processes to terminate."
    exit 0
fi

stop_pid() {
    local pid=$1
    local name=$2
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "[INFO] Terminating $name (PID $pid)..."
        kill "$pid" 2>/dev/null || true
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
        echo "[PASS] $name terminated."
    else
        echo "[INFO] $name (PID $pid) is not running."
    fi
}

BACKEND_PID=$(grep -o '"backend": *{[^}]*' "${PID_FILE}" | grep -o '"pid": *[0-9]*' | grep -o '[0-9]*' || true)
WEB_PID=$(grep -o '"web": *{[^}]*' "${PID_FILE}" | grep -o '"pid": *[0-9]*' | grep -o '[0-9]*' || true)
FLUTTER_PID=$(grep -o '"flutter": *{[^}]*' "${PID_FILE}" | grep -o '"pid": *[0-9]*' | grep -o '[0-9]*' || true)

stop_pid "$BACKEND_PID" "Backend"
stop_pid "$WEB_PID" "Web"
stop_pid "$FLUTTER_PID" "Flutter Web"

rm -f "${PID_FILE}"
echo "[PASS] All Libris development services stopped safely."
