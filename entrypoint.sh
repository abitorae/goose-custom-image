#!/bin/bash
set -euo pipefail

# Start headless-shell with CDP on port 9222 (localhost-only, security).
# chrome-headless-shell is a headless-only binary; the --headless flag is
# implicit. --disable-dev-shm-usage is kept because /dev/shm defaults to
# 64 MB in most containers, too small for Chromium rendering.
headless-shell \
    --disable-gpu \
    --disable-dev-shm-usage \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port=9222 \
    --user-data-dir=/tmp/chromium-profile \
    --no-first-run \
    &

HS_PID=$!

# Wait for the CDP endpoint to become ready.
CDP_READY=0
for i in $(seq 1 30); do
    if curl -sf http://localhost:9222/json/version >/dev/null 2>&1; then
        CDP_READY=1
        echo "headless-shell CDP ready on :9222"
        break
    fi
    if ! kill -0 "$HS_PID" 2>/dev/null; then
        echo "headless-shell exited early" >&2
        exit 1
    fi
    sleep 1
done

if [ "$CDP_READY" -eq 0 ]; then
    echo "ERROR: CDP endpoint not ready after 30s" >&2
    kill "$HS_PID" 2>/dev/null || true
    exit 1
fi

# exec goose under tini (PID 1). tini reaps headless-shell on exit.
exec goose "$@"
