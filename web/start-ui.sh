#!/usr/bin/env bash
# GolemGarden Web UI — start Vite dev server on port 5173
# Mirrors: web/start-ui.bat
# Usage: bash web/start-ui.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "  GolemGarden Web UI"
echo "  Port: 5173"
echo "  Open: http://localhost:5173"
echo "  Press Ctrl+C to stop."
echo ""

cd "$SCRIPT_DIR/client"

exec npm run dev
