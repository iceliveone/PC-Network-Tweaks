@echo off
:: Admin-Rechte prüfen
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administratorrechte erforderlich. Starte neu mit Admin-Rechten...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit
)

:: Auto-Update von GitHub
set "GitHubURL=https://raw.githubusercontent.com/iceliveone/PC-Network-Tweaks/main/Netzwerk_Tweaks_Toolkit.bat"
set "LocalFile=%~f0"
echo Prüfe auf Updates...
powershell -Command "(Invoke-WebRequest -Uri '%GitHubURL%').Content" > "%temp%\\update.bat"
fc "%temp%\\update.bat" "%LocalFile%" >nul
if %errorlevel% neq 0 (
    echo Neue Version gefunden! Aktualisiere...
    copy /Y "%temp%\\update.bat" "%LocalFile%"
    echo Update abgeschlossen. Starte neu...
    start "" "%LocalFile%"
    exit
)

:menu
cls
echo ============================================
echo Netzwerk-Tweaks Toolkit (Batch)
echo ============================================
echo [1] DNS-Cache leeren
echo [2] IP-Adresse erneuern
echo [3] Netzwerkadapter neu starten
echo [4] TCP/IP-Stack zurücksetzen
echo [5] Winsock zurücksetzen
echo [6] MTU-Wert anpassen
echo [0] Beenden
echo ============================================
set /p choice="Bitte wähle eine Option: "

if "%choice%"=="1" ipconfig /flushdns
if "%choice%"=="2" (ipconfig /release & ipconfig /renew)
if "%choice%"=="3" (netsh interface set interface "Ethernet" admin=disable & timeout /t 5 & netsh interface set interface "Ethernet" admin=enable)
if "%choice%"=="4" netsh int ip reset
if "%choice%"=="5" netsh winsock reset
if "%choice%"=="6" goto mtu
if "%choice%"=="0" exit
goto menu

:mtu
cls
echo Aktuelle MTU-Werte:
netsh interface ipv4 show subinterfaces
set /p mtuvalue="Neuen MTU-Wert eingeben (z.B. 1500): "
set /p adaptername="Adaptername eingeben (z.B. Ethernet): "
netsh interface ipv4 set subinterface "%adaptername%" mtu=%mtuvalue% store=persistent
echo MTU angepasst!
pause
goto menu
