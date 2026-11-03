#!/usr/bin/env bash
# Libris — Sprint 15: Full-Stack Development Launcher (Unix/macOS/Linux)
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${REPO_ROOT}/.logs"
PID_FILE="${REPO_ROOT}/.libris_pids.json"

BACKEND_PORT="${1:-5000}"
WEB_PORT="${2:-3000}"
FLUTTER_PORT="${3:-5001}"
TIMEOUT_SEC="${4:-60}"

mkdir -p "${LOG_DIR}"

echo "=== LIBRIS SPRINT 15 — FULL-STACK DEVELOPMENT LAUNCHER (BASH) ==="
echo "Target Ports: Backend=${BACKEND_PORT}, Web=${WEB_PORT}, FlutterWeb=${FLUTTER_PORT}"

# Port check
for PORT in ${BACKEND_PORT} ${WEB_PORT} ${FLUTTER_PORT}; do
    if lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        echo "[FAIL] Port ${PORT} is already occupied."
        exit 1
    fi
done

# Start Backend
echo "[INFO] Starting Flask Backend on 127.0.0.1:${BACKEND_PORT}..."
(
    cd "${REPO_ROOT}"
    export DEBUG=true
    export HOST=127.0.0.1
    export PORT=${BACKEND_PORT}
    export PYTHONUNBUFFERED=1
    python -u -m backend.app > "${LOG_DIR}/backend.log" 2>&1
) &
BACKEND_PID=$!

# Start Web
echo "[INFO] Starting Next.js Web on 127.0.0.1:${WEB_PORT}..."
(
    cd "${REPO_ROOT}/web"
    export BACKEND_URL="http://127.0.0.1:${BACKEND_PORT}"
    npm run dev -- -p ${WEB_PORT} -H 127.0.0.1 > "${LOG_DIR}/web.log" 2>&1
) &
WEB_PID=$!

# Start Flutter Web
echo "[INFO] Starting Flutter Web on 127.0.0.1:${FLUTTER_PORT}..."
(
    cd "${REPO_ROOT}/mobile/flutter_app"
    flutter run -d web-server --web-port ${FLUTTER_PORT} --web-hostname 127.0.0.1 --dart-define=BACKEND_URL="http://127.0.0.1:${BACKEND_PORT}" > "${LOG_DIR}/flutter.log" 2>&1
) &
FLUTTER_PID=$!

# Record PIDs
cat <<EOF > "${PID_FILE}"
{
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "backend": { "pid": ${BACKEND_PID}, "port": ${BACKEND_PORT}, "log": "${LOG_DIR}/backend.log" },
  "web": { "pid": ${WEB_PID}, "port": ${WEB_PORT}, "log": "${LOG_DIR}/web.log" },
  "flutter": { "pid": ${FLUTTER_PID}, "port": ${FLUTTER_PORT}, "log": "${LOG_DIR}/flutter.log" }
}
EOF

echo "[PASS] Process metadata saved to .libris_pids.json"

# Readiness polling
poll_url() {
    local url=$1
    local name=$2
    local timeout=$3
    echo -n "[WAIT] Polling ${name} at ${url} "
    local count=0
    while [ $count -lt $timeout ]; do
        if curl -s -f "${url}" > /dev/null 2>&1; then
            echo " [READY]"
            return 0
        fi
        echo -n "."
        sleep 1
        count=$((count + 1))
    done
    echo " [FAILED]"
    return 1
}

poll_url "http://127.0.0.1:${BACKEND_PORT}/api/health" "Backend" 30
poll_url "http://127.0.0.1:${WEB_PORT}" "Web" 30
poll_url "http://127.0.0.1:${FLUTTER_PORT}" "Flutter Web" ${TIMEOUT_SEC}

echo ""
echo "=== LIBRIS — THREE-LINK LOCAL SHOWROOM ==="
echo "1. Backend health:               http://127.0.0.1:${BACKEND_PORT}/api/health"
echo "2. Web application:              http://127.0.0.1:${WEB_PORT}"
echo "3. Mobile application in Chrome: http://127.0.0.1:${FLUTTER_PORT}"
echo ""
echo "To stop: ./scripts/stop_dev.sh"
