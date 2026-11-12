@echo off
rem Startet den Copilot-FinOps-Collector per Doppelklick (PowerShell 7.2+ erforderlich)
chcp 65001 >nul
cd /d "%~dp0"
where pwsh >nul 2>&1 || (echo PowerShell 7 ^(pwsh^) ist nicht installiert: https://aka.ms/powershell & pause & exit /b 1)
if not exist "..\02_Konfiguration\config.json" (echo config.json fehlt - bitte zuerst mit 02_Konfiguration\Konfiguration-CopilotFinOps.html erstellen. & pause & exit /b 1)
pwsh -NoProfile -File "%~dp0Collect-CopilotCosts.ps1" -ConfigPath "%~dp0..\02_Konfiguration\config.json"
set "COLLECTOR_EXIT=%ERRORLEVEL%"
echo.
if not "%COLLECTOR_EXIT%"=="0" (echo Es sind Fehler aufgetreten. Details im Protokoll unter 06_Daten\out\collector_*.log) else (echo Fertig. Ergebnisse unter 06_Daten\out)
pause
exit /b %COLLECTOR_EXIT%
