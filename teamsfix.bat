@echo off
:: ==========================================================================
:: TEAMS & WINDOWS UPDATE DEEP REPAIR SCRIPT
:: MUST BE RUN AS ADMINISTRATOR
:: ==========================================================================

:: Check for administrative privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Please right-click this script and select "Run as administrator".
    pause
    exit /b
)

echo [1/6] Stopping background Windows services...
net stop bits /y
net stop wuauserv /y

echo [2/6] Killing all hung Teams and Office processes...
taskkill /f /im Teams.exe >nul 2>&1
taskkill /f /im msteams.exe >nul 2>&1
taskkill /f /im msteamsupdate.exe >nul 2>&1

echo [3/6] Cleaning Windows system temp and update caches...
del /s /q /f C:\Windows\temp\*.* >nul 2>&1
del /s /q /f C:\Windows\prefetch\*.* >nul 2>&1
del /s /q /f C:\Windows\SoftwareDistribution\*.* >nul 2>&1

echo [4/6] Purging Teams, Identity, and Token caches...
:: Classic Teams Cache
if exist "%appdata%\Microsoft\Teams" (
    del /s /q /f "%appdata%\Microsoft\Teams\*.*" >nul 2>&1
    rmdir /s /q "%appdata%\Microsoft\Teams" >nul 2>&1
)
:: New Teams LocalCache
if exist "%userprofile%\appdata\local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams" (
    del /s /q /f "%userprofile%\appdata\local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\*.*" >nul 2>&1
)
:: Identity & Token Broker Caches (Fixes login/splash loops)
if exist "%localappdata%\Microsoft\IdentityCache" del /s /q /f "%localappdata%\Microsoft\IdentityCache\*.*" >nul 2>&1
if exist "%localappdata%\Microsoft\TokenBroker" del /s /q /f "%localappdata%\Microsoft\TokenBroker\*.*" >nul 2>&1

echo [5/6] Programmatically resetting the Teams App package...
:: This replaces the manual step of going to Settings -> Apps -> Reset
powershell -Command "Get-AppxPackage *MSTeams* | Reset-AppxPackage" >nul 2>&1

echo [6/6] Restarting Windows services...
net start bits /y
net start wuauserv /y

echo ==========================================================================
echo [SUCCESS] Script actions completed. 
echo [NOTE] If login errors persist, manually clear "msteams" keys from Credential Manager.
echo ==========================================================================

set /p choice="The machine needs to restart to apply all changes. Reboot now? (Y/N): "
if /i "%choice%"=="Y" shutdown -f -r -t 00
exit /b
