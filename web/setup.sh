#!/usr/bin/env bash
# GolemGarden Web UI — macOS/Linux setup script
# Installs gateway (uv sync) and client (npm install) dependencies.
# Usage: bash web/setup.sh
# Requirements: uv (https://docs.astral.sh/uv/), node/npm, bash 4+
#   macOS: brew install bash uv node

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── helpers ──────────────────────────────────────────────────────────────────

step()  { echo ""; echo ">>> $*"; }
ok()    { echo "  [OK] $*"; }
warn()  { echo "  [WARN] $*"; }
err()   { echo "  [ERR] $*" >&2; }

# ── banner ───────────────────────────────────────────────────────────────────

echo ""
echo "=================================================="
echo "  GolemGarden Web UI — macOS/Linux Setup"
echo "=================================================="

GATEWAY_DIR="$SCRIPT_DIR/gateway"
CLIENT_DIR="$SCRIPT_DIR/client"

# ── STEP 1: required tools check ─────────────────────────────────────────────

step "Step 1/3: Required tools check"

missing=()

if command -v uv >/dev/null 2>&1; then
    ok "uv found ($(uv --version 2>/dev/null || echo 'version unknown'))"
else
    warn "uv not found"
    missing+=("uv")
fi

if command -v npm >/dev/null 2>&1; then
    ok "npm found ($(npm --version))"
else
    warn "npm not found"
    missing+=("npm")
fi

if command -v node >/dev/null 2>&1; then
    ok "node found ($(node --version))"
else
    warn "node not found — needed by npm"
fi

# claude CLI — optional
if command -v claude >/dev/null 2>&1; then
    ok "claude CLI found"
else
    warn "claude CLI not found (needed for SOUL chat — install via: npm i -g @anthropic-ai/claude-code)"
fi

if [ ${#missing[@]} -gt 0 ]; then
    echo ""
    err "Missing required tools: ${missing[*]}"
    echo "  Install guide:"
    for tool in "${missing[@]}"; do
        case "$tool" in
            uv)  echo "    uv:  https://docs.astral.sh/uv/  (macOS: brew install uv)" ;;
            npm) echo "    npm: https://nodejs.org/          (macOS: brew install node)" ;;
        esac
    done
    echo ""
    exit 1
fi

# ── STEP 2: gateway uv sync ──────────────────────────────────────────────────

step "Step 2/3: Gateway dependencies (uv sync)"

if [ -d "$GATEWAY_DIR" ]; then
    (
        cd "$GATEWAY_DIR"
        uv sync
    )
    ok "Gateway deps installed"
else
    warn "Gateway dir not found: $GATEWAY_DIR — skipping"
fi

# ── STEP 3: client npm install ───────────────────────────────────────────────

step "Step 3/3: Client dependencies (npm install)"

if [ -d "$CLIENT_DIR" ]; then
    (
        cd "$CLIENT_DIR"
        npm install
    )
    ok "Client deps installed"
else
    warn "Client dir not found: $CLIENT_DIR — skipping"
fi

# ── done ─────────────────────────────────────────────────────────────────────

echo ""
echo "=================================================="
echo "  Setup complete!"
echo "=================================================="
echo ""
echo "  Start servers:"
echo "    All-in-one:  bash $SCRIPT_DIR/start-all.sh"
echo "    Or separate: bash $SCRIPT_DIR/start-gateway.sh"
echo "                 bash $SCRIPT_DIR/start-ui.sh"
echo ""
echo "  Browser: http://localhost:5173"
echo ""
