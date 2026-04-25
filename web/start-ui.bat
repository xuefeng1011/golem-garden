@echo off
REM GolemGarden Web UI - Vite dev server (port 5173)

title GolemGarden UI

cd /d "%~dp0client"

echo.
echo  GolemGarden Web UI
echo  Port: 5173
echo  Open: http://localhost:5173
echo  Press Ctrl+C to stop.
echo.

npm run dev
