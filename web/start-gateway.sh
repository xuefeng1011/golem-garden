#!/usr/bin/env bash
# GolemGarden Gateway — start FastAPI server on 127.0.0.1:8642
# Mirrors: web/start-gateway.bat
# Usage: bash web/start-gateway.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "  GolemGarden Gateway"
echo "  Port: 8642"
echo "  Press Ctrl+C to stop."
echo ""

cd "$SCRIPT_DIR/gateway"

exec uv run python -m uvicorn golem_gateway.main:app \
    --host 127.0.0.1 \
    --port 8642 \
    --app-dir src
