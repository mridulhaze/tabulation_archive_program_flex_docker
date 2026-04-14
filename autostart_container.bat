@echo off
:: Wait for Docker daemon to be ready after boot
:waitloop
docker info >nul 2>&1
if %errorlevel% NEQ 0 (
    timeout /t 5 /nobreak >nul
    goto :waitloop
)

:: Stop old container if running
docker stop nu-tabulation-app >nul 2>&1
docker rm   nu-tabulation-app >nul 2>&1

:: Start fresh container
docker run -d echo     --name nu-tabulation-app echo     --restart unless-stopped echo     -p 5000:5000 echo     -v "C:\Users\User\Desktop\Tabulation_archive_program\webapp-mem -docker\temp_cache:/app/temp_cache" echo     nu-tabulation

exit
