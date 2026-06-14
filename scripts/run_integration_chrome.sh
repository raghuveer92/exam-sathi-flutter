#!/usr/bin/env bash
# Run ExamSaathi integration tests on Chrome only (via flutter drive + chromedriver).
# Starts the local backend automatically unless it is already running.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend_springboot"
cd "$ROOT"

API_URL="${API_BASE_URL:-http://localhost:8080/api/v1}"
TEST_ENV="${TEST_ENV:-dev}"
CHROMEDRIVER_PORT="${CHROMEDRIVER_PORT:-4444}"
HEALTH_URL="${API_URL%/}/actuator/health"
SKIP_BACKEND_START="${SKIP_BACKEND_START:-0}"
KEEP_BACKEND_RUNNING="${KEEP_BACKEND_RUNNING:-0}"

CD_PID=""
BACKEND_PID=""
STARTED_BACKEND=false

backend_is_up() {
  curl -sf "$HEALTH_URL" 2>/dev/null | grep -q '"status":"UP"'
}

wait_for_backend() {
  local timeout="${1:-120}"
  local end=$((SECONDS + timeout))
  while (( SECONDS < end )); do
    if backend_is_up; then
      return 0
    fi
    sleep 2
  done
  return 1
}

start_backend() {
  if [ "$SKIP_BACKEND_START" = "1" ]; then
    echo "==> SKIP_BACKEND_START=1 — assuming backend is managed externally"
    if ! backend_is_up; then
      echo "ERROR: Backend is not reachable at $HEALTH_URL"
      exit 1
    fi
    return
  fi

  if backend_is_up; then
    echo "==> Backend already running ($HEALTH_URL)"
    return
  fi

  if [ ! -f "$BACKEND_DIR/.env" ]; then
    echo "ERROR: Missing $BACKEND_DIR/.env"
    echo "       Copy backend_springboot/.env.example → .env and fill in Supabase credentials."
    exit 1
  fi

  if ! command -v mvn >/dev/null 2>&1; then
    echo "ERROR: Maven (mvn) is required to start the backend."
    exit 1
  fi

  echo "==> Starting backend (dev profile — OTP 999999)..."
  (
    cd "$BACKEND_DIR"
    set -a
    set +u  # .env secrets may contain $ — avoid unbound variable errors
    # shellcheck disable=SC1091
    source .env
    set -u
    set +a
    mvn spring-boot:run -Dspring-boot.run.profiles=dev -q
  ) &
  BACKEND_PID=$!
  STARTED_BACKEND=true

  echo "==> Waiting for backend health at $HEALTH_URL ..."
  if ! wait_for_backend 120; then
    echo "ERROR: Backend did not become healthy within 120s."
    echo "       Check logs in backend_springboot/ or run manually:"
    echo "       cd backend_springboot && set -a && source .env && set +a && mvn spring-boot:run -Dspring-boot.run.profiles=dev"
    exit 1
  fi
  echo "==> Backend is UP"
}

cleanup() {
  if [ -n "$CD_PID" ]; then
    kill "$CD_PID" 2>/dev/null || true
  fi
  if [ "$STARTED_BACKEND" = true ] && [ "$KEEP_BACKEND_RUNNING" != "1" ] && [ -n "$BACKEND_PID" ]; then
    echo "==> Stopping backend (pid $BACKEND_PID)"
    kill "$BACKEND_PID" 2>/dev/null || true
  elif [ "$STARTED_BACKEND" = true ] && [ "$KEEP_BACKEND_RUNNING" = "1" ]; then
    echo "==> KEEP_BACKEND_RUNNING=1 — backend left running (pid $BACKEND_PID)"
  fi
}
trap cleanup EXIT

echo "==> ExamSaathi integration tests (Chrome only)"
echo "    API_BASE_URL=$API_URL"
echo "    TEST_ENV=$TEST_ENV"
echo ""

start_backend

# Flutter web integration tests need chromedriver matching the installed Chrome major version.
CHROME_MAJOR=""
if [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
  CHROME_MAJOR="$(/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --version | grep -oE '[0-9]+' | head -1)"
fi
CHROME_MAJOR="${CHROME_MAJOR:-149}"

CHROMEDRIVER_BIN=""
if [ -x "$REPO_ROOT/node_modules/.bin/chromedriver" ]; then
  CHROMEDRIVER_BIN="$REPO_ROOT/node_modules/.bin/chromedriver"
else
  echo "==> Installing chromedriver@${CHROME_MAJOR} (matching Chrome)..."
  (cd "$REPO_ROOT" && npm install "chromedriver@${CHROME_MAJOR}.0.2" --no-save)
  CHROMEDRIVER_BIN="$REPO_ROOT/node_modules/.bin/chromedriver"
fi

# Verify chromedriver major matches Chrome; reinstall if stale.
CD_MAJOR="$("$CHROMEDRIVER_BIN" --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
if [ "$CD_MAJOR" != "$CHROME_MAJOR" ]; then
  echo "==> chromedriver v${CD_MAJOR:-?} ≠ Chrome v$CHROME_MAJOR — reinstalling..."
  (cd "$REPO_ROOT" && npm install "chromedriver@${CHROME_MAJOR}.0.2" --no-save)
  CHROMEDRIVER_BIN="$REPO_ROOT/node_modules/.bin/chromedriver"
fi

echo "==> Starting chromedriver on port $CHROMEDRIVER_PORT"
if lsof -ti:"$CHROMEDRIVER_PORT" >/dev/null 2>&1; then
  echo "    Port $CHROMEDRIVER_PORT in use — stopping existing chromedriver"
  lsof -ti:"$CHROMEDRIVER_PORT" | xargs kill -9 2>/dev/null || true
  sleep 1
fi
"$CHROMEDRIVER_BIN" --port="$CHROMEDRIVER_PORT" &
CD_PID=$!

sleep 2

flutter pub get

TEST_TARGET="${TEST_TARGET:-integration_test/app_test.dart}"

# flutter test does NOT support web; flutter drive + chromedriver is the Chrome path.
# INTEGRATION_TEST enables wizard store bypass. Use ONE testWidgets / ONE app.main()
# per drive session — multiple app.main() calls break Chrome (stuck on "Test Starting...").
echo "==> Running flutter drive (INTEGRATION_TEST=true, target=$TEST_TARGET)"
flutter drive \
  --driver=integration_test/driver.dart \
  --target="$TEST_TARGET" \
  -d chrome \
  --dart-define=INTEGRATION_TEST=true \
  --dart-define=TEST_ENV="$TEST_ENV" \
  --dart-define=API_BASE_URL="$API_URL"
