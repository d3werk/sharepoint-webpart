# Lokale Regressionstests

Die Tests verwenden synthetische Daten, temporäre Ordner und API-Mocks. Sie melden sich nicht an Microsoft-/GitHub-Konten an und verändern keine Cloud-Daten. Der Einrichtungsassistent wird mit Mocks bzw. ohne Discovery geprüft. Während der Browserläufe werden externe HTTP-Anfragen als Fehler gewertet; der lokale Testserver wird nach dem Lauf beendet.

Alle folgenden Befehle werden aus dem Ordner `Copilot-FinOps` ausgeführt.

## Browser, Konfigurationsablauf und Datenschema

Voraussetzungen: Python 3.10+ und Chromium bzw. der Playwright-Browser.

```sh
python -m pip install -r tests/requirements.txt
python -m playwright install chromium
python -m unittest discover -s tests -p 'test_*.py' -v
```

Ist `chromium` bereits installiert, wird es automatisch verwendet. Alternativ `CHROMIUM_PATH` auf die ausführbare Datei setzen. Die Browserprüfungen umfassen Dashboard, Importe, Schema und Konfigurationsablauf. Der Collector-zu-Dashboard-Test verwendet `pwsh` aus dem Suchpfad oder `PWSH_PATH`. Fehlt PowerShell, wird dieser Test ausdrücklich übersprungen; für die vollständige lokale Prüfung PowerShell installieren und den Lauf wiederholen.

Der Browser startet für die automatisierten Prüfungen mit `--no-sandbox`; ausschließlich lokal erzeugte Testdaten auf einer isolierten Entwicklungsmaschine verwenden. Die ausgelieferte Anwendung benötigt diesen Schalter nicht. Die Tests verwenden einen kurzlebigen lokalen HTTP-Server; damit funktionieren sie auch in Browserumgebungen, die lokale `file://`-Navigation sperren.

## PowerShell-Collector und Einrichtungsassistent

Voraussetzung: PowerShell 7.2+. Für die Mocktests werden weder Pester, `Az.Accounts`, Zertifikat noch Token benötigt.

```sh
pwsh -NoProfile -File tests/collector.Tests.ps1
pwsh -NoProfile -File tests/setup.Tests.ps1
```

Geprüft werden echte Collector-Funktionen und CSV-Collector-Aufrufe als Unterprozess sowie die lokale Konfigurationserstellung, Validierung und Sicherung. API-Antworten und Discovery werden nachgebildet. Fehler führen zu einem von null verschiedenen Prozessstatus.

Wenn PowerShell außerhalb des Suchpfads liegt, `PWSH_PATH` auf die tatsächlich installierte ausführbare Datei setzen. Für die PowerShell-Testskripte dieselbe ausführbare Datei direkt aufrufen. Frühere Prüfberichte können Pfade aus einer anderen Entwicklungsumgebung nennen; sie sind keine Voraussetzung der Anwendung.

## JavaScript- und Power-Query-Syntax

Node.js 22+; diese Abhängigkeiten werden nur für die Prüfung benötigt:

```sh
cd tests
npm ci --ignore-scripts
npm run test:syntax
```

Die Inline-JavaScript-Anwendungen werden vom Node-Parser geprüft, die drei M-Abfragen vom offiziellen `@microsoft/powerquery-parser`. Dieser Lauf führt weder M-Abfragen noch DAX aus.

## Konfiguration vor einem echten Lauf lokal prüfen

Mit einer eigenen vorhandenen Konfiguration:

```sh
pwsh -NoProfile -File 03_Collector/Collect-CopilotCosts.ps1 -ConfigPath 02_Konfiguration/config.json -ValidateOnly
```

Das prüft die Werte ohne Anmeldung oder Ergebnisdateien. Beim Assistenten ist `-WhatIf` dagegen nur eine Aktionsvorschau: keine Anmeldung, keine Rückfragen, keine Dateien und keine formale Konfigurationsprüfung.

## Grenzen und Ergebnisnachweis

Die Tests bestätigen keine aktuellen Kundenpreise, echten Tenant-Berechtigungen, Report-Feldnamen im Zieltenant, API-Verfügbarkeit oder Power-BI-Refresh/RLS. Sie ersetzen auch keinen Windows-Test des privaten Zertifikatsschlüssels unter dem späteren Collector-Konto. Diese Abnahme benötigt die Zielumgebung.

Ausgeführte Läufe und verbleibende Grenzen gehören in den [Prüfbericht](../01_Dokumentation/06_Pruefbericht.md). Frühere Ergebnisse der Version 1.2 bleiben historische Nachweise; sie belegen keine unveränderte Funktionsfähigkeit der aktuellen Version.
