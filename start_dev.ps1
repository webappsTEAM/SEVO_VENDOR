<#
.SYNOPSIS
    CalTrack Workforce Unified Local Development Launcher.
    Starts:
      1. Django API Server (Port 8001)
      2. Authoritative Dispatch Worker (Continuous Loop)
      3. Frontend Vite Server (Port 5176)
#>

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackendDir = Join-Path $ScriptDir "backend"
$FrontendDir = Join-Path $ScriptDir "frontend"

# Find Python executable
$PythonExe = "python"
if (Test-Path (Join-Path $BackendDir "venv\Scripts\python.exe")) {
    $PythonExe = (Join-Path $BackendDir "venv\Scripts\python.exe")
} elseif (Test-Path (Join-Path $BackendDir ".venv\Scripts\python.exe")) {
    $PythonExe = (Join-Path $BackendDir ".venv\Scripts\python.exe")
}

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " CalTrack Workforce Unified Development Launcher" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Python Executable: $PythonExe" -ForegroundColor Gray

# 1. Start Django API
Write-Host "[1/3] Starting Django API on http://127.0.0.1:8001..." -ForegroundColor Green
Start-Process -FilePath $PythonExe -ArgumentList "manage.py runserver 127.0.0.1:8001" -WorkingDirectory $BackendDir -WindowStyle Minimized

# 2. Start Dispatch Worker
Write-Host "[2/3] Starting Authoritative Dispatch Worker (Loop: 3s)..." -ForegroundColor Green
Start-Process -FilePath $PythonExe -ArgumentList "manage.py dispatch_pending_workforce_jobs --loop --interval 3" -WorkingDirectory $BackendDir -WindowStyle Minimized

# 3. Start Frontend
Write-Host "[3/3] Starting Frontend Vite Server on http://localhost:5176..." -ForegroundColor Green
Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm run dev" -WorkingDirectory $FrontendDir -WindowStyle Minimized

Write-Host "`nAll 3 processes are now running in the background." -ForegroundColor Yellow
Write-Host "  - API Backend:     http://127.0.0.1:8001/api/" -ForegroundColor White
Write-Host "  - Dispatch Worker: Supervised continuous reconciliation" -ForegroundColor White
Write-Host "  - Frontend App:    http://localhost:5176/" -ForegroundColor White
Write-Host "========================================================`n" -ForegroundColor Cyan
