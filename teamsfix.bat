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

:: Prompt for the target username
echo ==========================================================================
set /p TARGET_USER="Enter the Windows username of the affected account (or press Enter for current user): "
if "%TARGET_USER%"=="" set TARGET_USER=%username%
echo [INFO] Targeting profile path: C:\Users\%TARGET_USER%
echo ==========================================================================
echo.

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
if exist "C:\Users\%TARGET_USER%\AppData\Roaming\Microsoft\Teams" (
    del /s /q /f "C:\Users\%TARGET_USER%\AppData\Roaming\Microsoft\Teams\*.*" >nul 2>&1
    rmdir /s /q "C:\Users\%TARGET_USER%\AppData\Roaming\Microsoft\Teams" >nul 2>&1
)
:: New Teams LocalCache
if exist "C:\Users\%TARGET_USER%\AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams" (
    del /s /q /f "C:\Users\%TARGET_USER%\AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\*.*" >nul 2>&1
)
:: Identity & Token Broker Caches (Fixes login/splash loops)
if exist "C:\Users\%TARGET_USER%\AppData\Local\Microsoft\IdentityCache" del /s /q /f "C:\Users\%TARGET_USER%\AppData\Local\Microsoft\IdentityCache\*.*" >nul 2>&1
if exist "C:\Users\%TARGET_USER%\AppData\Local\Microsoft\TokenBroker" del /s /q /f "C:\Users\%TARGET_USER%\AppData\Local\Microsoft\TokenBroker\*.*" >nul 2>&1

echo [5/6] Programmatically resetting the Teams App package...
:: Triggers the AppxPackage reset for the specified target user context
powershell -Command "Get-AppxPackage -AllUsers *MSTeams* | Where-Object {$_.PackageUserInformation.UserSecurityId -ne $null} | Reset-AppxPackage" >nul 2>&1

echo [6/6] Restarting Windows services...
net start bits /y
net start wuauserv /y

echo ==========================================================================
echo [SUCCESS] Script actions completed for user: %TARGET_USER%
echo [NOTE] If login errors persist, manually clear "msteams" keys from Credential Manager.
echo ==========================================================================

set /p choice="The machine needs to restart to apply all changes. Reboot now? (Y/N): "
if /i "%choice%"=="Y" shutdown /f /r /t 00
exit /b
