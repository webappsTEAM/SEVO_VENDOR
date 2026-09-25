@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo  Starting CalTrack Workforce (API + Dispatch Worker + UI)
echo ========================================================

:: Detect Python executable
set "PYTHON_EXE="
if exist "%~dp0backend\venv\Scripts\python.exe" (
    set "PYTHON_EXE=%~dp0backend\venv\Scripts\python.exe"
) else if exist "%~dp0backend\.venv\Scripts\python.exe" (
    set "PYTHON_EXE=%~dp0backend\.venv\Scripts\python.exe"
) else (
    set "PYTHON_EXE=python"
)

echo [1/3] Starting Django API on 127.0.0.1:8001...
cd /d "%~dp0backend"
start "Vendor-Backend-API" /min "%PYTHON_EXE%" manage.py runserver 127.0.0.1:8001

echo [2/3] Starting Authoritative Dispatch Worker (Continuous Loop)...
start "Vendor-Dispatch-Worker" /min "%PYTHON_EXE%" manage.py dispatch_pending_workforce_jobs --loop --interval 3

echo [3/3] Starting Frontend Vite Dev Server on http://localhost:5176...
cd /d "%~dp0frontend"
start "Vendor-Frontend" /min cmd /c "npm run dev"

echo.
echo ========================================================
echo  All 3 CalTrack services launched in background:
echo   - Backend API:       http://127.0.0.1:8001/api/
echo   - Dispatch Worker:   Continuous Database Reconciliation (3s)
echo   - Frontend App:      http://localhost:5176/
echo ========================================================
