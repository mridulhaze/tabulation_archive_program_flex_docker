@echo off
title NU Tabulation - Register Auto-Start Task
color 0A

:: ── Must run as Administrator ────────────────────────────────────
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo [ERROR] Please run this script as Administrator!
    echo Right-click the bat file → "Run as administrator"
    pause
    exit /b 1
)

set TASK_NAME=NU_Tabulation_Autostart
set PROJECT_DIR=%~dp0
set SCRIPT_PATH=%PROJECT_DIR%autostart_container.bat
set CONTAINER_NAME=nu-tabulation-app
set IMAGE_NAME=nu-tabulation
set HOST_PORT=5000

echo.
echo ================================================================
echo  NU TABULATION ARCHIVE - Register Windows Auto-Start Task
echo ================================================================
echo.

:: ── Create the actual launcher bat ───────────────────────────────
echo [1/3] Creating launcher script: autostart_container.bat
(
echo @echo off
echo :: Wait for Docker daemon to be ready after boot
echo :waitloop
echo docker info ^>nul 2^>^&1
echo if %%errorlevel%% NEQ 0 (
echo     timeout /t 5 /nobreak ^>nul
echo     goto :waitloop
echo ^)
echo.
echo :: Stop old container if running
echo docker stop %CONTAINER_NAME% ^>nul 2^>^&1
echo docker rm   %CONTAINER_NAME% ^>nul 2^>^&1
echo.
echo :: Start fresh container
echo docker run -d ^
echo     --name %CONTAINER_NAME% ^
echo     --restart unless-stopped ^
echo     -p %HOST_PORT%:5000 ^
echo     -v "%PROJECT_DIR%temp_cache:/app/temp_cache" ^
echo     %IMAGE_NAME%
echo.
echo exit
) > "%SCRIPT_PATH%"
echo [OK] Launcher created: %SCRIPT_PATH%

:: ── Delete old task if exists ─────────────────────────────────────
echo.
echo [2/3] Removing old task (if exists)...
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1
echo [OK] Done.

:: ── Register Task Scheduler job ───────────────────────────────────
echo.
echo [3/3] Registering Task Scheduler job...
echo       Task name   : %TASK_NAME%
echo       Trigger     : At system startup (run whether user logged in or not)
echo       Action      : %SCRIPT_PATH%
echo.

schtasks /create ^
    /tn "%TASK_NAME%" ^
    /tr "cmd.exe /c \"%SCRIPT_PATH%\"" ^
    /sc ONSTART ^
    /delay 0002:00 ^
    /ru "SYSTEM" ^
    /rl HIGHEST ^
    /f

if %errorlevel% NEQ 0 (
    echo [ERROR] Failed to register task.
    pause
    exit /b 1
)

echo.
echo ================================================================
echo  SUCCESS! Auto-start task registered.
echo ================================================================
echo.
echo  Task Name   : %TASK_NAME%
echo  Runs        : 2 minutes after every Windows startup
echo  Runs as     : SYSTEM (no login required)
echo  Container   : %CONTAINER_NAME%
echo  App URL     : http://localhost:%HOST_PORT%
echo.
echo  To manage the task:
echo    View   : schtasks /query /tn "%TASK_NAME%" /fo LIST /v
echo    Delete : schtasks /delete /tn "%TASK_NAME%" /f
echo    Run now: schtasks /run /tn "%TASK_NAME%"
echo.
echo  You can also see it in:
echo    Task Scheduler (taskschd.msc) → Task Scheduler Library
echo.
pause