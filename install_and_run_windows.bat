@echo off
title NU Tabulation Archive - Full Setup
color 0B
cls

echo.
echo ================================================================
echo  NU TABULATION ARCHIVE  -  Full Windows Setup
echo  Installs: Python + pip deps  OR  Docker (your choice)
echo ================================================================
echo.

set PROJECT_DIR=%~dp0
cd /d "%PROJECT_DIR%"

echo Choose setup mode:
echo   [1] Run with Python directly (install pip dependencies)
echo   [2] Run with Docker (recommended for deployment)
echo.
set /p CHOICE="Enter 1 or 2: "

if "%CHOICE%"=="1" goto :python_mode
if "%CHOICE%"=="2" goto :docker_mode
echo Invalid choice.
pause
exit /b 1

:: ════════════════════════════════════════════════════════════════════
:python_mode
:: ════════════════════════════════════════════════════════════════════
echo.
echo [MODE] Python direct mode selected.
echo.

:: ── Check Python ──────────────────────────────────────────────────
echo [1/4] Checking Python installation...
python --version >nul 2>&1
if %errorlevel% NEQ 0 (
    echo [!] Python not found. Installing via winget...
    winget install -e --id Python.Python.3.11 --silent --accept-package-agreements --accept-source-agreements
    if %errorlevel% NEQ 0 (
        echo [!] winget failed. Downloading Python 3.11 installer...
        curl -L "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" -o "%TEMP%\python_installer.exe"
        "%TEMP%\python_installer.exe" /quiet InstallAllUsers=1 PrependPath=1
        echo [OK] Python installed. Refreshing PATH...
        set "PATH=%PATH%;C:\Python311;C:\Python311\Scripts"
    )
    echo [OK] Python installed.
) else (
    python --version
    echo [OK] Python found.
)

:: ── Create venv ───────────────────────────────────────────────────
echo.
echo [2/4] Setting up virtual environment...
if not exist "%PROJECT_DIR%venv\Scripts\activate.bat" (
    python -m venv "%PROJECT_DIR%venv"
    echo [OK] Virtual environment created.
) else (
    echo [OK] Virtual environment already exists.
)

call "%PROJECT_DIR%venv\Scripts\activate.bat"

:: ── Install dependencies ──────────────────────────────────────────
echo.
echo [3/4] Installing Python dependencies...
python -m pip install --upgrade pip

pip install flask==3.1.3
pip install oracledb==3.4.2
pip install pillow==12.1.1
pip install werkzeug==3.1.5
pip install cryptography==46.0.5
pip install gunicorn==23.0.0

echo.
echo [OK] All dependencies installed:
pip list | findstr /i "flask oracledb pillow werkzeug cryptography"

:: ── Run app ───────────────────────────────────────────────────────
echo.
echo [4/4] Starting Flask app...
echo ================================================================
echo  App running at: http://localhost:5000
echo  Press CTRL+C to stop
echo ================================================================
echo.
mkdir temp_cache 2>nul
python tabulation_web.py
goto :end

:: ════════════════════════════════════════════════════════════════════
:docker_mode
:: ════════════════════════════════════════════════════════════════════
echo.
echo [MODE] Docker mode selected.
echo.

set IMAGE_NAME=nu-tabulation
set CONTAINER_NAME=nu-tabulation-app
set HOST_PORT=5000

:: ── Check Docker ──────────────────────────────────────────────────
echo [1/5] Checking Docker...
docker --version >nul 2>&1
if %errorlevel% NEQ 0 (
    echo [!] Docker not found. Installing via winget...
    winget install -e --id Docker.DockerDesktop --silent --accept-package-agreements --accept-source-agreements
    if %errorlevel% NEQ 0 (
        echo [INFO] Downloading Docker Desktop installer...
        curl -L "https://desktop.docker.com/win/main/amd64/Docker%%20Desktop%%20Installer.exe" -o "%TEMP%\DockerInstaller.exe"
        echo [INFO] Running installer (follow the GUI prompts)...
        "%TEMP%\DockerInstaller.exe" install --quiet
    )
    echo [INFO] Waiting 45s for Docker to start...
    timeout /t 45 /nobreak >nul
)

docker info >nul 2>&1
if %errorlevel% NEQ 0 (
    echo [!] Docker daemon not running. Starting Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    timeout /t 40 /nobreak >nul
    docker info >nul 2>&1
    if %errorlevel% NEQ 0 (
        echo [ERROR] Docker still not ready. Please start Docker Desktop manually and re-run.
        pause
        exit /b 1
    )
)
echo [OK] Docker is ready.
docker --version

:: ── Verify required files ─────────────────────────────────────────
echo.
echo [2/5] Checking required files...
if not exist "Dockerfile" (
    echo [ERROR] Dockerfile not found in %PROJECT_DIR%
    echo         Make sure Dockerfile and requirements.txt are in the project root.
    pause
    exit /b 1
)
if not exist "requirements.txt" (
    echo [ERROR] requirements.txt not found.
    pause
    exit /b 1
)
echo [OK] Dockerfile and requirements.txt found.

:: ── Stop old container ────────────────────────────────────────────
echo.
echo [3/5] Removing old container...
docker stop %CONTAINER_NAME% >nul 2>&1
docker rm   %CONTAINER_NAME% >nul 2>&1
echo [OK] Done.

:: ── Build ─────────────────────────────────────────────────────────
echo.
echo [4/5] Building Docker image (first time takes 2-5 min)...
docker build -t %IMAGE_NAME% .
if %errorlevel% NEQ 0 (
    echo [ERROR] Build failed. Check errors above.
    pause
    exit /b 1
)
echo [OK] Image built: %IMAGE_NAME%

:: ── Run ───────────────────────────────────────────────────────────
echo.
echo [5/5] Starting container...
docker run -d ^
    --name %CONTAINER_NAME% ^
    --restart unless-stopped ^
    -p %HOST_PORT%:5000 ^
    -v "%PROJECT_DIR%temp_cache:/app/temp_cache" ^
    %IMAGE_NAME%

if %errorlevel% NEQ 0 (
    echo [ERROR] Container failed to start.
    docker logs %CONTAINER_NAME%
    pause
    exit /b 1
)

echo.
echo ================================================================
echo  SUCCESS!  App running at: http://localhost:%HOST_PORT%
echo ================================================================
echo  docker logs -f %CONTAINER_NAME%   <- view live logs
echo  docker stop %CONTAINER_NAME%      <- stop app
echo  docker restart %CONTAINER_NAME%   <- restart
echo ================================================================
timeout /t 3 /nobreak >nul
start http://localhost:%HOST_PORT%

:end
echo.
pause