@echo off
title NU Tabulation Archive - Docker Deploy
color 0B
cls

echo.
echo ================================================================
echo  NU TABULATION ARCHIVE  -  Docker Deploy Script
echo  Installs Docker Desktop (if needed) + Builds + Runs Container
echo ================================================================
echo.

:: ── CONFIGURATION ────────────────────────────────────────────────────
set IMAGE_NAME=nu-tabulation
set CONTAINER_NAME=nu-tabulation-app
set HOST_PORT=5000
set CONTAINER_PORT=5000
set PROJECT_DIR=%~dp0
:: ─────────────────────────────────────────────────────────────────────

echo [INFO] Project directory: %PROJECT_DIR%
echo.

:: ════════════════════════════════════════════════════════════════════
:: STEP 1 — CHECK / INSTALL DOCKER
:: ════════════════════════════════════════════════════════════════════
echo [1/5] Checking Docker installation...
docker --version >nul 2>&1
if %errorlevel% EQU 0 (
    echo [OK] Docker is already installed.
    docker --version
    goto :check_running
)

echo [!] Docker not found. Starting automatic installation...
echo.

:: Check if winget is available (Windows 10/11)
winget --version >nul 2>&1
if %errorlevel% EQU 0 (
    echo [INFO] Installing Docker Desktop via winget...
    winget install -e --id Docker.DockerDesktop --silent --accept-package-agreements --accept-source-agreements
    if %errorlevel% NEQ 0 (
        goto :manual_install
    )
    echo [OK] Docker Desktop installed via winget.
    goto :wait_docker
)

:manual_install
echo [INFO] winget not available. Downloading Docker Desktop installer...
echo.
set DOCKER_INSTALLER=%TEMP%\DockerDesktopInstaller.exe
curl -L "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" -o "%DOCKER_INSTALLER%"
if %errorlevel% NEQ 0 (
    echo [ERROR] Download failed. Please install Docker Desktop manually:
    echo         https://www.docker.com/products/docker-desktop/
    pause
    exit /b 1
)
echo [INFO] Running Docker Desktop installer (follow the GUI)...
"%DOCKER_INSTALLER%" install --quiet
echo [OK] Docker Desktop installed.

:wait_docker
echo.
echo [INFO] Docker Desktop needs to start. Waiting 45 seconds...
echo        (If it prompts for WSL2 update, approve it)
timeout /t 45 /nobreak >nul

:: Try to start Docker service
net start com.docker.service >nul 2>&1
timeout /t 15 /nobreak >nul

:: Verify docker is now responsive
docker --version >nul 2>&1
if %errorlevel% NEQ 0 (
    echo.
    echo [!] Docker is installed but not yet running.
    echo     Please:
    echo       1. Launch "Docker Desktop" from the Start Menu
    echo       2. Wait for the whale icon in the taskbar to stop animating
    echo       3. Re-run this script
    echo.
    pause
    exit /b 1
)
echo [OK] Docker is running.

:check_running
:: ════════════════════════════════════════════════════════════════════
:: STEP 2 — ENSURE DOCKER DAEMON IS RUNNING
:: ════════════════════════════════════════════════════════════════════
echo.
echo [2/5] Checking Docker daemon status...
docker info >nul 2>&1
if %errorlevel% NEQ 0 (
    echo [!] Docker daemon is not running. Attempting to start Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    echo [INFO] Waiting 40 seconds for Docker to start...
    timeout /t 40 /nobreak >nul
    docker info >nul 2>&1
    if %errorlevel% NEQ 0 (
        echo [ERROR] Docker daemon still not responding.
        echo         Please start Docker Desktop manually and re-run this script.
        pause
        exit /b 1
    )
)
echo [OK] Docker daemon is running.

:: ════════════════════════════════════════════════════════════════════
:: STEP 3 — STOP & REMOVE OLD CONTAINER (if exists)
:: ════════════════════════════════════════════════════════════════════
echo.
echo [3/5] Cleaning up old container (if any)...
docker stop %CONTAINER_NAME% >nul 2>&1
docker rm   %CONTAINER_NAME% >nul 2>&1
echo [OK] Old container removed (or did not exist).

:: ════════════════════════════════════════════════════════════════════
:: STEP 4 — BUILD IMAGE
:: ════════════════════════════════════════════════════════════════════
echo.
echo [4/5] Building Docker image: %IMAGE_NAME%
echo       (This may take 2-5 minutes on first run — downloading layers)
echo.
cd /d "%PROJECT_DIR%"
docker build -t %IMAGE_NAME% .
if %errorlevel% NEQ 0 (
    echo.
    echo [ERROR] Docker build failed!
    echo         Common causes:
    echo           - Missing requirements.txt
    echo           - Missing Dockerfile
    echo           - No internet connection during first build
    echo.
    pause
    exit /b 1
)
echo.
echo [OK] Image built successfully: %IMAGE_NAME%

:: ════════════════════════════════════════════════════════════════════
:: STEP 5 — RUN CONTAINER
:: ════════════════════════════════════════════════════════════════════
echo.
echo [5/5] Starting container: %CONTAINER_NAME%
echo       Port mapping: localhost:%HOST_PORT% → container:%CONTAINER_PORT%
echo.

docker run -d ^
    --name %CONTAINER_NAME% ^
    --restart unless-stopped ^
    -p %HOST_PORT%:%CONTAINER_PORT% ^
    -v "%PROJECT_DIR%temp_cache:/app/temp_cache" ^
    %IMAGE_NAME%

if %errorlevel% NEQ 0 (
    echo [ERROR] Failed to start container.
    docker logs %CONTAINER_NAME%
    pause
    exit /b 1
)

:: ════════════════════════════════════════════════════════════════════
:: SUCCESS
:: ════════════════════════════════════════════════════════════════════
echo.
echo ================================================================
echo  SUCCESS! Container is running.
echo ================================================================
echo.
echo  App URL  :  http://localhost:%HOST_PORT%
echo  Container:  %CONTAINER_NAME%
echo  Image    :  %IMAGE_NAME%
echo.
echo  Useful commands:
echo    View logs   :  docker logs -f %CONTAINER_NAME%
echo    Stop app    :  docker stop %CONTAINER_NAME%
echo    Restart app :  docker restart %CONTAINER_NAME%
echo    Shell inside:  docker exec -it %CONTAINER_NAME% bash
echo    Remove all  :  docker stop %CONTAINER_NAME% ^& docker rm %CONTAINER_NAME%
echo.

:: Auto-open browser after 3 seconds
echo [INFO] Opening browser in 3 seconds...
timeout /t 3 /nobreak >nul
start http://localhost:%HOST_PORT%

echo.
echo Press any key to exit this window (container keeps running).
pause >nul