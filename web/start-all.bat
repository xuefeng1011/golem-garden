@echo off
REM GolemGarden - Start both servers in separate windows

echo.
echo  Starting GolemGarden...
echo.

start "GolemGarden Gateway" "%~dp0start-gateway.bat"
timeout /t 2 >nul
start "GolemGarden UI" "%~dp0start-ui.bat"

echo  Both servers starting in separate windows.
echo  Open http://localhost:5173 in your browser.
echo.
echo  To stop: close the Gateway and UI windows.
echo.
pause
