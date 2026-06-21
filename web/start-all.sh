#!/usr/bin/env bash
# GolemGarden — start gateway (background) + UI (foreground)
# Mirrors: web/start-all.bat
# Usage: bash web/start-all.sh
# Ctrl-C kills both servers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Track gateway PID for cleanup
GATEWAY_PID=""

cleanup() {
    echo ""
    echo "  Stopping servers..."
    if [ -n "$GATEWAY_PID" ] && kill -0 "$GATEWAY_PID" 2>/dev/null; then
        kill "$GATEWAY_PID"
    fi
    exit 0
}

trap cleanup INT TERM

echo ""
echo "  Starting GolemGarden..."
echo ""

# Start gateway in background
bash "$SCRIPT_DIR/start-gateway.sh" &
GATEWAY_PID=$!

# Brief pause so gateway has a moment to bind before the UI starts
sleep 2

echo "  Gateway PID: $GATEWAY_PID"
echo "  Both servers starting. Open http://localhost:5173 in your browser."
echo "  Press Ctrl+C to stop both."
echo ""

# Run UI in foreground; when it exits (Ctrl-C) cleanup fires via trap
bash "$SCRIPT_DIR/start-ui.sh"
