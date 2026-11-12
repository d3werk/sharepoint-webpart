# Lokale Regressionstests

Die Tests verwenden synthetische Daten, temporäre Ordner und API-Mocks. Sie melden sich nicht an Microsoft-/GitHub-Konten an und verändern keine Cloud-Daten. Während der Browserläufe werden externe HTTP-Anfragen als Fehler gewertet. Der lokale Testserver wird nach dem Lauf beendet.

## Browser, Datenschema und Collector-Integration

Voraussetzungen: Python 3.10+ und Chromium bzw. der Playwright-Browser.

Aus dem Ordner `Copilot-FinOps`:

```sh
python -m pip install -r tests/requirements.txt
python -m playwright install chromium
python -m unittest discover -s tests -p test_app.py -v
```

Ein bereits installiertes `chromium` wird automatisch verwendet. Alternativ `CHROMIUM_PATH` auf die ausführbare Datei setzen. Der zusätzliche Collector-zu-Dashboard-Test verwendet `pwsh` aus dem Suchpfad oder `PWSH_PATH`; fehlt PowerShell, wird dieser eine Test ausdrücklich übersprungen. Die übrigen Browser-/Schematests laufen weiter. Für vollständige lokale Prüfung PowerShell installieren und den Lauf wiederholen.

Der Browser wird für den automatisierten Lauf mit `--no-sandbox` gestartet; ausschließlich lokal erzeugte Testdaten auf einer isolierten Entwicklungsmaschine verwenden. Die Anwendung selbst benötigt diesen Schalter nicht. In der verwalteten Cloud ist `file://` im Browser durch die Richtlinie gesperrt; der Test verwendet deshalb einen kurzlebigen lokalen HTTP-Server. Dies ändert die Offline-Funktion der ausgelieferten HTML-Dateien nicht.

## PowerShell-Collector

Voraussetzung: PowerShell 7.2+. Kein Pester, `Az.Accounts`, Zertifikat oder Token nötig.

```sh
pwsh -NoProfile -File tests/collector.Tests.ps1
```

Geprüft werden die echten Collector-Funktionen sowie echte CSV-Collector-Aufrufe als Unterprozess. API-Antworten werden lokal nachgebildet. Fehler führen zu einem von null verschiedenen Prozessstatus.

In der aktuellen Cloud-Instanz liegt die geprüfte PowerShell-Version unter `/workspace/tools/powershell-7.4.13/pwsh`. Dort vor beiden Testläufen setzen:

```sh
export PWSH_PATH=/workspace/tools/powershell-7.4.13/pwsh
export XDG_CACHE_HOME=/workspace/tools/xdg-cache
export XDG_CONFIG_HOME=/workspace/tools/xdg-config
export XDG_DATA_HOME=/workspace/tools/xdg-data
"$PWSH_PATH" -NoProfile -File tests/collector.Tests.ps1
python -m unittest discover -s tests -p test_app.py -v
```

Diese Pfade sind lokale Entwicklungswerkzeuge, keine Voraussetzung der ausgelieferten Anwendung.

## JavaScript- und Power-Query-Syntax

Node.js 22+; die Abhängigkeiten werden nur für die Prüfung benötigt:

```sh
cd tests
npm ci --ignore-scripts
npm run test:syntax
```

Die beiden Inline-JavaScript-Anwendungen werden vom Node-Parser geprüft, alle drei M-Abfragen vom offiziellen `@microsoft/powerquery-parser`. Dieser Lauf führt weder M-Abfragen noch DAX aus.

## Grenzen

Die Tests bestätigen keine aktuellen Kundenpreise, Tenant-Berechtigungen, Report-Feldnamen im Zieltenant, echte API-Verfügbarkeit oder Power-BI-Refresh/RLS. Diese Prüfungen benötigen die jeweilige Zielumgebung. Ein grüner lokaler Lauf ist kein Nachweis für einen vollständigen produktiven Datenbestand.
