# Copilot-FinOps – Kosten und Nutzung verständlich auswerten

Version 1.3 · Stand 12.11.2026

Copilot-FinOps führt Lizenzmengen, Nutzungsangaben und Verbrauchskosten für Microsoft 365 Copilot, Copilot Studio, Azure OpenAI/Foundry und GitHub Copilot zusammen. Das HTML-Dashboard läuft lokal im Browser. Der PowerShell-Collector bereitet eigene Daten für Dashboard und Power BI auf.

## Zuerst ansehen: ohne Installation oder Microsoft-Anmeldung

`04_Dashboard/copilot-cost-dashboard.html` im Browser öffnen. Die enthaltenen **Beispieldaten** zeigen Navigation und Auswertungen. Sie stammen nicht aus deinem Tenant. Dafür werden weder PowerShell noch Azure-Zugang oder eine App-Registrierung benötigt.

Eigene Daten später über **Daten laden** importieren: `06_Daten/out/facts.json` und den zugehörigen `lizenzkatalog.json` gemeinsam auswählen. Budget und Kapazität sind optional. Beim ersten eigenen Import entfernt das Dashboard die Beispieldaten samt Demobudgets und Demokapazitäten.

## Welchen Einrichtungsweg brauche ich?

| Ziel | Einfachster Einstieg | Anmeldung des Collectors |
|---|---|---|
| Dashboard kennenlernen | HTML-Datei öffnen | keine |
| Vorhandene Azure-Kosten-CSV auswerten | Quelle **Azure**, Verfahren **Export** | keine; Exportdateien lokal bereitstellen |
| Copilot-Studio-Verbrauch aus CSV auswerten | Quelle **PPAC** | keine; CSV aus dem Admin Center bereitstellen |
| M365-Lizenzen und Nutzung auslesen | Quelle **Graph** | Entra-App mit Zertifikat |
| Azure-Kosten direkt abrufen | Quelle **Azure**, Verfahren **Query** | Entra-App mit Zertifikat und Azure-Leserechten |
| GitHub Copilot auslesen | Quelle **GitHub** | separates Token in `FINOPS_GITHUB_TOKEN` |

Für reine CSV-Importe sind Tenant-ID, Client-ID und Zertifikat keine Pflichtangaben. Eine Quelle erst aktivieren, wenn ihre Einrichtung vollständig ist: Fehler einer aktivierten Quelle verhindern die Veröffentlichung neuer Ergebnisdateien.

## Einstellungen mit weniger Kopierarbeit

Das Paket bietet zwei Wege, die dieselbe `config.json` erzeugen:

- **Im Browser:** `02_Konfiguration/Konfiguration-CopilotFinOps.html` öffnen, zuerst Quellen wählen, anschließend die dafür benötigten Angaben eintragen. Der Download muss als `02_Konfiguration/config.json` im Paket gespeichert werden. Der Browser prüft Formate, nicht den Cloud-Zugang.
- **Mit lokalem Assistenten:** In PowerShell 7 vom Paketordner aus `./03_Collector/Einrichten-CopilotFinOps.ps1` ausführen. Der Assistent führt durch die Quellenwahl und kann unter Windows passende Zertifikate anbieten. Mit `-DiscoverAzure` liest er nach einer Benutzeranmeldung Tenant-ID und auswählbare Azure-Abonnements ein. App-Registrierung und Berechtigungen bleiben einmalige Administrationsaufgaben.

Der Assistent bewahrt vorhandene Einstellungen und zusätzliche JSON-Felder. Vor dem Ersetzen legt er eine datierte Sicherung an. Die Benutzeranmeldung zur Ermittlung der Azure-Angaben ersetzt nicht die App-Anmeldung des Collectors.

Die [Schritt-für-Schritt-Anleitung](01_Dokumentation/01_Schnellstart.md) erklärt beide Wege, benötigte Rechte und typische Fehler.

## Erster Lauf mit eigenen Daten

1. Das vollständige Paket entpacken und seine Ordnerstruktur erhalten.
2. Den passenden Einrichtungsweg aus der Tabelle wählen und `config.json` erstellen.
3. Preise, Zuordnungsschlüssel und CSV-Spalten im Lizenzkatalog bzw. in der Konfiguration prüfen.
4. Unter Windows `03_Collector/Start-Collector.cmd` starten. Alternativ unter PowerShell 7: `./03_Collector/Collect-CopilotCosts.ps1 -ConfigPath ./02_Konfiguration/config.json`.
5. Erfolgreichen Abschluss und Protokoll kontrollieren; anschließend `facts.json` und `lizenzkatalog.json` aus `06_Daten/out` in das Dashboard laden.

PowerShell 7.2+ wird für den Collector benötigt. CSV-Importe laufen auch unter Linux/macOS. Die Zertifikatsanmeldung benötigt Windows und `Az.Accounts`. Das Dashboard selbst benötigt keine Installation und keine externen Laufzeitabhängigkeiten.

## Ergebnisse richtig lesen

Fehlende Preise und unbekannte Nutzungsdaten werden ausgewiesen. Ein angezeigter Betrag kann deshalb unvollständig sein; unbekannte Aktivität ist kein Beleg für ungenutzte Lizenzen. Alle Angaben mit **[prüfen]** müssen vor der produktiven Nutzung anhand der Zielumgebung verifiziert werden. Das Paket enthält keine verbindlichen Microsoft-Preise.

Währungen werden getrennt ausgewertet, nicht umgerechnet. Budgets sind Jahresbudgets in der Standardwährung des Katalogs. Monatsfakten verwenden den am Monatsersten gültigen Preis; Jahrespreise für `ProUser` werden durch zwölf geteilt. Der Forecast braucht mindestens zwei Ist-Monate innerhalb der letzten drei Kalendermonate desselben Jahres.

`facts.json` ist das unveränderte Austauschformat für Dashboard und Power BI. `facts.csv` ist für Excel abgesichert: formelähnliche Texte erhalten ein vorangestelltes Apostroph. Daher die CSV nicht als Quelle für Produkt- oder Berechtigungszuordnungen verwenden.

## Dateien und weiterführende Hilfe

| Ordner | Inhalt |
|---|---|
| `01_Dokumentation` | [Schnellstart](01_Dokumentation/01_Schnellstart.md), [Konzept und Berechtigungen](01_Dokumentation/02_Konzept.md), [Power BI](01_Dokumentation/03_PowerBI-Bauanleitung.md), [Betrieb](01_Dokumentation/04_Betriebsleitfaden.md), [Prüfbericht](01_Dokumentation/06_Pruefbericht.md) |
| `02_Konfiguration` | Konfigurationsmaske, `config.json`, Lizenzkatalog, Schema und Beispiele |
| `03_Collector` | Einrichtungsassistent, Collector, Voraussetzungprüfung und Zertifikaterstellung |
| `04_Dashboard` | HTML-Dashboard |
| `05_PowerBI` | Power-Query-Abfragen und DAX |
| `06_Daten/import` | lokale CSV-Importordner für Azure und PPAC |
| `06_Daten/out` | erzeugte Fakten, kopierter Katalog und Protokolle |
| `tests` | [reproduzierbare lokale Prüfungen](tests/README.md) |

Lokale Tests verwenden synthetische Daten und API-Mocks. Echte Tenant-Berechtigungen, aktuelle Endpunkte und Power-BI-Refresh müssen zusätzlich in der Zielumgebung geprüft werden.
