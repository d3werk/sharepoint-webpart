# Betriebsleitfaden

## 1. Regelbetrieb

| Wann | Was | Wer |
|---|---|---|
| täglich 05:00 | Collector-Lauf (Aufgabenplanung) | automatisch |
| täglich 07:00 | Power-BI-Aktualisierung | automatisch |
| täglich | Protokoll `06_Daten\out\collector_*.log` auf `ERROR` prüfen (oder Exit-Code 1 überwachen) | IT/FinOps |
| monatlich bis 3. Werktag | CSV-Export Copilot Studio aus PPAC nach `06_Daten\import\ppac` | Power-Platform-Admin |
| monatlich | Preise/Budgets prüfen, Einsparpotenziale an Fachbereiche melden | Controlling |
| jährlich / vor Ablauf | Zertifikat erneuern (`New-AppZertifikat.ps1`, neue `.cer` hochladen, Fingerabdruck in der Maske ändern) | IT/FinOps |

## 2. Neues Lizenzmodell ergänzen – ohne Code-Änderung
1. `02_Konfiguration\lizenzkatalog.json` öffnen, z. B. in VS Code (dort mit Schema-Prüfung).
2. Einen bestehenden Eintrag kopieren und anpassen:
   - eindeutige `produktId`
   - `produkt`, `produktfamilie`
   - `abrechnungsart`: `ProUser`, `Kapazitaet`, `Verbrauch` oder `Kostenfrei`
   - `einheit`, `waehrung`, `gueltigAb`
3. Den **Zuordnungsschlüssel** passend zur Datenquelle setzen:

| Datenquelle | Feld im `zuordnungsschluessel` |
|---|---|
| Graph (Lizenz) | `graphSkuPartNumber` |
| Azure | `azureMeterCategory`, `azureServiceName` oder `azureMeterNameContains` |
| GitHub | `githubSku` |
| PPAC-CSV | Produkt-ID in der Maske unter „Produkt-ID im Lizenzkatalog“ |

4. `kundenpreis` eintragen oder `[prüfen]` stehen lassen.
5. **Preisänderung:** Pro Produkt-ID ist genau ein Preisstand erlaubt (Groß-/Kleinschreibung unterscheidet keine IDs). Für historische Preisstände neue eindeutige IDs und passende Faktenzuordnungen verwenden. Mehrere Zeilen mit derselben ID werden abgewiesen; automatische Preisversionierung nach Datum ist nicht implementiert. Das bloße Kopieren eines Katalogeintrags reicht für die Collector-Zuordnung nicht aus (siehe Power-BI-Anleitung).
6. Den nächsten Collector-Lauf abwarten. Das Dashboard und Power BI übernehmen das Produkt automatisch.

**Grenze:** Für eine **neue Datenquelle**, etwa einen Fremdhersteller mit eigener API, wird eine zusätzliche Collector-Funktion benötigt.

## Datenqualität und Wiederanlauf

- Nur vollständige, nicht überlappende Exporte in den Importordnern bereitstellen. Tägliche kumulative Exporte für denselben Monat dürfen nicht nebeneinander liegen: ohne eindeutige Quell-IDs kann der Collector inhaltliche Dubletten nicht zuverlässig erkennen. Gleiche Eingabeordner werden bei einem erneuten Lauf neu aggregiert, nicht an die Ergebnisdatei angehängt.
- Bei Fehlern einer aktivierten Quelle bleiben die bisherigen Ergebnisdateien erhalten und der Collector endet mit Exit-Code 1. Ein altes Ergebnis ist dadurch nicht aktuell; immer Protokoll, Laufzeit und Datenstand prüfen. Schreibfehler beim Export und Prozessabbrüche benötigen ebenfalls Überwachung und eine Sicherung des Ausgabeordners.
- Der Nutzungsbericht kann fehlen oder anonymisierte UPNs liefern. Dann bleibt die Aktivität unbekannt. Daraus keine Deaktivierungen oder Einsparversprechen ableiten.
- `MonthsBack = 12` umfasst die zwölf vorherigen Kalendermonate plus den aktuellen Monat. Graph und GitHub-Seats liefern Momentaufnahmen: nur tatsächlich früher gesammelte Monatsstände bleiben erhalten; fehlende Monate werden nicht nachträglich erfunden. Vor Migration den Ausgabeordner sichern. Beschädigte Historie blockiert einen neuen Export, bis sie geprüft oder aus einer Sicherung wiederhergestellt wurde.
- Die drei Ergebnisdateien werden vorbereitet und vor dem Ersetzen gesichert. Erkannte Schreibfehler lösen eine Wiederherstellung aus; parallele Läufe verwenden eine exklusive Schreibsperre. Verbraucher sollten erst nach erfolgreichem Lauf lesen. Nach hartem Prozess-/Systemabbruch gegebenenfalls `.finops-*` im Ausgabeordner auf Wiederherstellungssicherungen prüfen; das mehrteilige Ergebnis ist keine Dateisystemtransaktion.
- Importzahlen benötigen Dezimalkomma oder Dezimalpunkt ohne Tausendertrennzeichen. PPAC-Datumswerte: ISO (`2026-11-02`) oder deutsches Punktformat (`02.11.2026`); Azure unterstützt zusätzlich US-Schrägstrichdaten (`11/2/2026`). Mehrdeutige PPAC-Schrägstrichdaten werden abgewiesen.
- Preis- und Budgetangaben sind kundenseitig zu pflegen. Fehlende Preise zählen als 0 und unterschätzen die Gesamtkosten. Gemischte Währungen werden getrennt; es findet keine automatische Währungsumrechnung statt.
- Rohdatenordner, Konfiguration und Ausgaben nur berechtigten Konten zugänglich machen. Protokolle und Aggregate können Organisationsinformationen enthalten.

## 3. RACI

| Aufgabe | IT/FinOps | Controlling | Fachbereich | DSB/Betriebsrat |
|---|---|---|---|---|
| Collector, App-Registrierung, Zertifikat | R/A | I | – | I |
| Lizenzkatalog (technisch) | R/A | C | – | – |
| Kundenpreise & Budgets | C | R/A | C | – |
| PPAC-/Azure-Exporte | R/A | I | – | – |
| Berichte nutzen, Maßnahmen ableiten | C | R | R/A | – |
| Berechtigungen / RLS | R/A | C | I | C |
| Datenschutz, Betriebsvereinbarung, Mindestgruppengröße | C | I | I | R/A |
