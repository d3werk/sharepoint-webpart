# Annahmen, offene Prüfpunkte und Änderungsprotokoll

## Annahmen
1. Kundendaten, Lizenzmengen, Vertragsart (EA/CSP/MCA) und Preise liegen nicht vor, deshalb sind alle Preise mit `[prüfen]` gekennzeichnet.
2. Der Fachbereich stammt aus dem Entra-Attribut `department`. Azure-Kosten werden über ein Kostenstellen-Tag zugeordnet, Copilot Studio über die Zuordnung Umgebung → Fachbereich.
3. Die Agent-Nutzung per PAYG (Copilot Chat und Copilot Studio) wird über eine Billing Policy einem Azure-Abonnement belastet und ist dort als Meter sichtbar. Die Meter-Namen werden nach der ersten Abrechnung in den Katalog übernommen.
4. Monatliche Granularität reicht aus.
5. GitHub-Kosten werden pauschal einem Fachbereich zugeordnet.
6. Security Copilot ist im Katalog deaktiviert (`aktiv: false`).
7. Nicht im Scope: Lizenzpreisverhandlung, Microsoft Sentinel, allgemeines Azure-FinOps.

## Offene Prüfpunkte [prüfen]
- Graph-Endpunkt des Copilot-Nutzungsberichts (v1.0 oder beta) und dessen Feldnamen
- `skuPartNumber` der Copilot-Lizenzen im Tenant
- Meter-Namen für Copilot-PAYG, Copilot Studio und Azure OpenAI in eurer Azure-Abrechnung
- Spaltennamen des Azure-Cost-Management-Exports (abhängig von der Exportversion) und des PPAC-Exports
- GitHub-Billing-Endpunkte und SKU-Bezeichnungen
- Credits je Copilot Studio Capacity Pack und aktuelle Preise

## Selbstprüfung
- **Erweiterbarkeit:** Neue Produkte aus bestehenden Quellen funktionieren ohne Code-Änderung. Collector, Dashboard und DAX lesen ausschließlich den Katalog, und die Produkt-IDs für Sonderlogik stehen in `config.json` (`ProduktIds`).
- **Konsistenz:** Die Feldnamen der Faktentabelle sind in Collector, HTML und Power Query identisch, ebenso die Preislogik in HTML und DAX.
- **Lokal getestet ab 1.2:** Browserfunktionen, Schema-Fehlerfälle, Collector-Funktionen und echte CSV-Läufe mit PowerShell sowie M-Syntaxprüfung; Details und Grenzen im [Prüfbericht](06_Pruefbericht.md).
- **Nicht live getestet:** Anmeldung/Reportdaten im Zieltenant, aktuelle Abrechnungs-APIs und Power-BI-Refresh/DAX/RLS. Preise und Zuordnungsschlüssel bleiben kundenseitig zu verifizieren.

## Änderungsprotokoll

### Version 1.2 (11.11.2026)
- Dashboard: eigene Daten ersetzen Demo vollständig; Dateiimporte validiert und als Einheit übernommen; unbekannte Nutzung bleibt unbekannt; Währungen getrennt ohne Umrechnung.
- Monatsanfangs-Preisgültigkeit, Jahrespreise pro User und kalendermonatsabhängiger Forecast vereinheitlicht; unvollständige Kosten und fehlende Historie werden ausgewiesen.
- Produktindex statt wiederholter Katalogsuche, begrenzte Tabellen-/Diagrammausgabe, sichere Schlüsselaggregation, Tastaturbedienung und Excel-sichere CSV-Ausgabe.
- Konfiguration: keine stille Zahlenkorrektur, typgeprüfte Importe ohne Altwerte, keine Tenant-Anmeldung für reine CSV-Workflows, Dublettenprüfung für Zuordnungen.
- Collector: Quellenfehler erhalten bisherige Ergebnisse; Dezimalzahlen/Datum/Spalten geprüft; unbekannte Aktivität bleibt `null`; tatsächliche ältere Lizenz-Snapshots erhalten; Währungen und Summen bleiben bei der Gruppierung erhalten.
- Power BI: kanonische `facts.json` statt Excel-CSV, null-erhaltende Typprüfung, korrigierte DAX-Filter sowie währungs- und kapazitätsgeprüfte Measures.
- Reproduzierbare Browser-, Schema-, Collector- und Syntaxprüfungen ergänzt.

### Version 1.1 (02.11.2026)
- Ordnerstruktur eingeführt; relative Pfade in `config.json` gelten jetzt ab dem Ordner `02_Konfiguration`
- Azure: Export-Import als Standard; die Query API ist auf 2 Gruppierungen korrigiert (Meter + Kostenstellen-Tag) und unterstützt jetzt Seitenumbruch (`nextLink`)
- `CostApiVersion` ohne den Zusatz „[prüfen]“, Format wird geprüft
- Fest verdrahtete Produkt-IDs ersetzt durch `ProduktIds` in `config.json`
- Nicht genutzte Pseudonymisierung entfernt, stattdessen `MinGroupSize`
- Prüfung auf nicht ersetzte Platzhalter, Zertifikat und Spaltennamen der Importdateien
- GitHub-Seats mit Seitenumbruch
- Exit-Code 1 bei Fehlern (für die Überwachung)
- Konfigurationsmaske: Azure-Verfahren, Mindestgruppengröße; unbekannte Felder bleiben beim Laden erhalten
- Neu: `Install-Voraussetzungen.ps1`, `New-AppZertifikat.ps1`, Power-Query-Dateien, Schnellstart

### Version 1.0
- Erstfassung: Konzept, Lizenzkatalog, Collector, HTML-Dashboard, Power-BI-Anleitung, Betriebsleitfaden
