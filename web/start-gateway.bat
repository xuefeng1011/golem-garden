@echo off
REM GolemGarden Gateway - FastAPI server (port 8642)
REM Requires env vars set by setup.ps1 (MSYS_NO_PATHCONV, GOLEM_FORGE_SH_BASH, etc.)

title GolemGarden Gateway

cd /d "%~dp0gateway"

echo.
echo  GolemGarden Gateway
echo  Port: 8642
echo  Press Ctrl+C to stop.
echo.

python -m uv run python -m uvicorn golem_gateway.main:app --host 127.0.0.1 --port 8642 --app-dir "%~dp0gateway\src"
