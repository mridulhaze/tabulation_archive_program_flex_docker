@echo off
title NU Tabulation Web Server
color 0A

echo.
echo  ============================================
echo   NU TABULATION ARCHIVE - Web Server
echo  ============================================
echo.

:: ── SET YOUR PATHS HERE ──────────────────────────
set PROJECT_DIR=%~dp0
set VENV_DIR=%PROJECT_DIR%venv
set SCRIPT=tabulation_web.py
:: ─────────────────────────────────────────────────

echo  [1/3] Checking virtual environment...

if not exist "%VENV_DIR%\Scripts\activate.bat" (
    echo.
    echo  [!] Virtual environment not found at:
    echo      %VENV_DIR%
    echo.
    echo  Creating new virtual environment...
    python -m venv "%VENV_DIR%"
    if errorlevel 1 (
        echo  [ERROR] Failed to create venv. Is Python installed?
        pause
        exit /b 1
    )
    echo  [OK] Virtual environment created.
)

echo  [2/3] Activating virtual environment...
call "%VENV_DIR%\Scripts\activate.bat"
if errorlevel 1 (
    echo  [ERROR] Failed to activate virtual environment.
    pause
    exit /b 1
)
echo  [OK] Environment activated.

echo  [3/3] Starting server...
echo.
echo  ============================================
echo   Running: python %SCRIPT%
echo   Project: %PROJECT_DIR%
echo  ============================================
echo.

cd /d "%PROJECT_DIR%"
python "%SCRIPT%"

if errorlevel 1 (
    echo.
    echo  [ERROR] Server stopped with an error.
    echo  Check the output above for details.
)

echo.
echo  Server has stopped. Press any key to exit.
pause >nul
