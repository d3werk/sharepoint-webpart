# Copilot-FinOps – Kostenmanagement für die Microsoft-Copilot-Produktfamilie

Version 1.2 · Stand 11.11.2026

Das Paket schafft Transparenz über Lizenzen, Credits und Verbrauchskosten von M365 Copilot Chat, Microsoft 365 Copilot, Copilot Studio, Azure OpenAI/Foundry und GitHub Copilot. Die Kosten werden je Fachbereich ausgewiesen.

## Ordnerstruktur

```
Copilot-FinOps/
├── README.md                          ← diese Datei
├── 01_Dokumentation/
│   ├── 01_Schnellstart.md             ← Einrichtung Schritt für Schritt (hier beginnen)
│   ├── 02_Konzept.md                  ← Architektur, Datenquellen, Berechtigungen, Datenschutz
│   ├── 03_PowerBI-Bauanleitung.md     ← Datenmodell, Measures, Seiten, RLS
│   ├── 04_Betriebsleitfaden.md        ← Aktualisierung, neue Lizenzmodelle, RACI
│   └── 05_Annahmen-und-Aenderungen.md ← Annahmen, offene Prüfpunkte, Änderungsprotokoll
├── 02_Konfiguration/
│   ├── Konfiguration-CopilotFinOps.html  ← Konfigurationsmaske (im Browser öffnen)
│   ├── config.json                       ← Einstellungen (Platzhalter ersetzen)
│   ├── lizenzkatalog.json                ← Produkte, SKUs, Preise – ohne Code erweiterbar
│   ├── lizenzkatalog.schema.json         ← Prüfschema für den Katalog
│   └── Beispiele/ budget.json, kapazitaet.json
├── 03_Collector/
│   ├── Start-Collector.cmd               ← Datensammlung per Doppelklick
│   ├── Collect-CopilotCosts.ps1          ← PowerShell-Collector
│   ├── Install-Voraussetzungen.ps1       ← einmalig: Modul + Zertifikat prüfen
│   └── New-AppZertifikat.ps1             ← einmalig: Zertifikat für App-Registrierung
├── 04_Dashboard/
│   └── copilot-cost-dashboard.html       ← Offline-Dashboard (mit Beispieldaten)
├── 05_PowerBI/
│   ├── PowerQuery_*.pq                   ← Abfragen für Power BI Desktop
│   ├── DAX_Measures.dax, DimDatum.dax    ← Spalten, Measures, RLS
└── 06_Daten/
    ├── out/                              ← Ergebnis: facts.json, facts.csv, Protokolle
    └── import/ ppac/, azure-export/      ← manuelle CSV-Exporte ablegen
```

Zusätzlich: `tests/` enthält ausführbare Regressionstests; der [Prüfbericht](01_Dokumentation/06_Pruefbericht.md) beschreibt Änderungen und Prüfgrenzen.

## In 5 Schritten zum ersten Ergebnis
1. ZIP z. B. nach `C:\FinOps\` entpacken. Die Ordnerstruktur dabei nicht verändern.
2. `03_Collector\New-AppZertifikat.ps1` ausführen und die erzeugte `.cer`-Datei in der App-Registrierung hochladen (siehe Schnellstart).
3. `02_Konfiguration\Konfiguration-CopilotFinOps.html` öffnen, die Felder ausfüllen und die Datei als `config.json` in `02_Konfiguration` speichern.
4. Doppelklick auf `03_Collector\Start-Collector.cmd`.
5. `04_Dashboard\copilot-cost-dashboard.html` öffnen, auf **Daten laden** klicken und `06_Daten\out\facts.json` sowie `lizenzkatalog.json` auswählen.

> Alle Preise, SKU-Namen, Meter-Namen und API-Angaben mit **[prüfen]** vor der Produktivsetzung verifizieren. Das Paket enthält bewusst keine Microsoft-Preise.

## Auswertung mit eigenen Daten

`facts.json` ist das unveränderte maschinenlesbare Austauschformat für Dashboard und Power BI. `facts.csv` ist für Excel abgesichert; formelähnliche Texte erhalten dort ein vorangestelltes Apostroph. Deshalb die CSV nicht als Datenquelle für Produkt- oder Berechtigungszuordnungen verwenden.

Beim ersten eigenen Import entfernt das Dashboard sämtliche Demodaten, Demobudgets und Demokapazitäten. Fakten, Katalog, Budget und Kapazität können gemeinsam oder nacheinander geladen werden. Ein fehlerhafter Import lässt den bisherigen Zustand bestehen. Fehlende Preise und unbekannte Nutzungsdaten werden ausgewiesen; sie dürfen nicht als vollständige Kosten oder als Einsparnachweis interpretiert werden.

Die Auswertung trennt Währungen ohne Umrechnung. Budgets sind Jahresbudgets in `waehrungStandard` des Katalogs; dieselbe Budgetdatei nicht unverändert für andere Geschäftsjahre verwenden. Preisstände gelten für Monatsfakten am Monatsersten. Jahrespreise für `ProUser` werden durch zwölf geteilt. Der Forecast benötigt mindestens zwei Ist-Monate innerhalb der letzten drei Kalendermonate desselben Jahres.

## Entwicklung und Tests

Für die beiden HTML-Oberflächen ist keine Installation erforderlich. Der Collector benötigt PowerShell 7.2+, bei Zertifikatsanmeldung Windows und `Az.Accounts`. Reine CSV-Importe funktionieren auch unter PowerShell auf Linux ohne Tenant-Anmeldung. Siehe [Testanleitung](tests/README.md) für reproduzierbare lokale Prüfungen. Live-Zugriffe und Power-BI-Refresh sind gesondert in der Zielumgebung zu testen.
