# Prüfbericht – Copilot-FinOps 1.2

Prüfdatum: 11.11.2026. Grundlage: unverändertes Originalarchiv `Copilot-FinOps_v1.1.zip`. Überarbeiteter Quellstand: `Copilot-FinOps` in diesem Repository.

## Ergebnis

Die lokalen Prüfungen des überarbeiteten Stands bestehen: **36 Browser-/Schema-/Integrationstests**, **56 Collector-Prüfungen** und die Syntaxprüfungen für **zwei JavaScript-Anwendungen und drei Power-Query-Abfragen**. Kein Test im abschließenden lokalen Funktionslauf wurde übersprungen. Der PPAC-Collector wurde tatsächlich als PowerShell-Unterprozess ausgeführt; seine JSON-Ausgabe anschließend im echten Chromium-Dashboard geladen.

Sieben gezielte Regressionstests wurden zusätzlich gegen das Originalarchiv ausgeführt. Alle sieben zeigen dort die ursprünglichen Fehler und bestehen im korrigierten Stand. Die Fehler in diesem gesonderten Baseline-Protokoll sind erwartete Nachweise des Ausgangszustands.

**Noch nicht bestätigt:** echte Tenant-/Billing-Zugriffe, Windows-Zertifikatsanmeldung sowie Ausführung von DAX, Power-BI-Refresh und RLS. Die Anwendung ist lokal geprüft; eine produktive Rechnungs- und Berechtigungsprüfung in der Zielumgebung bleibt erforderlich.

## Wesentliche Befunde und Korrekturen

| Bereich | Befund in 1.1 | Verhalten in 1.2 |
|---|---|---|
| Eigene Daten | Demo-Fakten, -Budgets und -Kapazitäten konnten nach Teilimporten erhalten bleiben. | Erster eigener Import entfernt Demo vollständig; fehlende Dateien werden kenntlich gemacht. |
| Dateiimport | Fehler nach der ersten Datei konnten den Zustand teilweise verändern. | Alle Dateien werden vor Übernahme geprüft, einschließlich abgeleiteter Zahlen; Fehler erhalten den vorherigen Stand. |
| Währungen | EUR-/USD-Werte wurden gemeinsam summiert oder mit dem falschen Währungssymbol versehen. | Einzelauswahl im Dashboard, Schutz in Power-BI-Measures, keine implizite Umrechnung; Preiswährung muss zur Faktwährung passen. |
| Preise/Zeitbezug | Jahrespreise, Monatsgültigkeit und YTD-Filter waren uneinheitlich. | Monatsanfangs-Gültigkeit, Jahrespreis pro User geteilt durch zwölf, YTD unabhängig vom sichtbaren Startmonat. |
| Forecast/Budget | Monatslücken und unzureichende Historie konnten irreführen; Budget 0 und fehlendes Budget waren nicht sauber getrennt. | Trend berücksichtigt Kalendermonatsabstände; mindestens zwei aktuelle Ist-Monate; explizite Behandlung von 0/fehlendem Budget. |
| Lizenznutzung | Fehlende Nutzungsdaten wurden als 0 aktiv behandelt, mit scheinbarem Einsparpotenzial. | Unbekannte Aktivität bleibt `null`; kein daraus abgeleitetes Einsparpotenzial. Unzugewiesene Pools unterdrücken bekannte Nutzungswerte nicht. |
| Historie | Frühere Lizenzmonate gingen beim monatlichen Überschreiben verloren. | Tatsächlich gesammelte Graph-/GitHub-Seat-Snapshots bleiben innerhalb des Zeitfensters erhalten; erneute Läufe sind idempotent. |
| Quellenfehler | Unvollständige Ergebnisse konnten gute Dateien ersetzen. | Fehler aktivierter Quellen erhalten die alten Dateien; vorbereitete Ausgabe mit Sicherung, Rücknahme bei erkannten Schreibfehlern und exklusiver Schreibsperre. |
| CSV-Importe | Ungültige Spalten/Zahlen/Daten wurden teilweise übersprungen; `|` in Dimensionen zerstörte Schlüssel. | Explizite Fehler, deterministische Zahlen-/Datumsformate, strukturierte Aggregationsschlüssel und erhaltene Quellwährungen. |
| Kapazität | Null Packs und fehlende Kapazitätsangaben waren uneindeutig; Verbrauch konnte ohne Kapazitätsdatei verschwinden. | Null Packs sind bekannte Kapazität 0. Ein eindeutig bestimmbares Verbrauchsprodukt bleibt ohne Packangabe sichtbar; verschiedene Einheiten werden nicht addiert. |
| Ausgabe/Sicherheit | Formelähnliche CSV-Texte und besondere JavaScript-Objektschlüssel konnten problematisch sein. | Excel-Formeln entschärft; HTML-Inhalte escaped; sichere Dictionaries/Produktindex; API-Ziele und HTTPS begrenzt. |
| Konfigurationsmaske | Zahlen wurden still gekürzt, ungültige Importe teilweise übernommen, alte Werte beibehalten. | Typprüfung vor Übernahme, explizite Fehler, frischer Formularzustand, erhaltene unbekannte Felder und Dublettenprüfung. |
| Power BI | Ungültige Measure-Vergleiche, unbekannte Aktivität und durch CSV-Schutz veränderte Join-/RLS-Schlüssel. | Skalare DAX-Variablen, null-erhaltende M-Abfrage, kanonische `facts.json`, Währungsprüfung und eindeutige Produkt-/Kapazitätsauswahl. |
| Bedienung/Leistung | Wiederholte Katalogsuche, unbegrenzte Tabellen und mobiler Formularüberlauf. | Produktindex, höchstens 500 Tabellenzeilen und 30 Balken, vollständiger CSV-Export, tastaturbedienbare Ladebuttons, mobile Breitenkorrektur. |

## Ausgeführte Prüfungen

### Browser, Schema und Integration – 36 bestanden

Die Tests verwenden echte Chromium-Seiten mit Dateiauswahl und Downloads. Geprüft sind Navigation, Theme, Druckansicht, mobile Breiten, Datei-Reihenfolge, BOM, leere Daten, ungültige Monate/Zahlen, atomarer Rückfall, Dubletten, Groß-/Kleinschreibung bei Produkt-IDs, fehlende Preise, echte Nullkosten, Jahrespreise, Datumsgrenzen, unbekannte Aktivität, unzugewiesener Lizenzpool, besondere Objektschlüssel, HTML-Inhalte, CSV-Formeln/Quotes/Zeilenumbrüche und Filterung.

Weitere Fälle: explizite Quellwährung, kein Umetikettieren von Katalogpreisen, Währungsauswahl ohne gemischte Summen, YTD, Forecast bei Monatslücken, unzureichende Historie, Budget 0, Packs 0 und verschiedene Kapazitätseinheiten. Die Konfiguration wurde auf lokale Quellen ohne Tenant-Zertifikat, ungültige Zahlen, unveränderten Zustand nach fehlerhaftem Import, Altwerte, besondere Mapping-Schlüssel, doppelte Umgebungen und tatsächlichen JSON-Download geprüft.

Der echte Integrationslauf erstellt eine synthetische PPAC-CSV, führt den Collector aus, lädt dessen Fakten/Katalog ins Dashboard und kontrolliert Kosten, Agent-/Umgebungszuordnung sowie den geschützten CSV-Export. Externe Browser-HTTP-Anfragen werden durch die Tests als Fehler gewertet; es trat keine auf.

### Collector – 56 Prüfungen bestanden

Enthalten sind Parsing der drei PowerShell-Skripte, Dezimalzahlen, Datumsformate, endliche Werte, kleine Personengruppen, unbekannte Aktivität, Singleton-Graph-Antworten, echte PPAC-Läufe mit Exit-Code und Fehlererhalt, Monatswechsel/Idempotenz, beschädigte Historie, erhaltene Währungen/Istkosten, Azure-Zeitgrenzen und Gutschriften, Literal-/Mehrdeutigkeitsprüfung der Azure-Zuordnung, Graph-Berichtsfenster und Aktivitätsfelder, begrenzte API-Ziele und `Retry-After`.

GitHub-Billing wird anhand nachgebildeter Antworten auf konfigurierte Pflichtabfragen und monatliche Aggregation geprüft. Der Pfad `/organizations/{org}/settings/billing/usage`, der String-Parameter `org` und die Filter `year`/`month` wurden anhand der offiziellen Octokit-OpenAPI-Typen 29.0.1 verifiziert. Dies bestätigt keine tatsächliche Erreichbarkeit oder Berechtigung im Kundenkonto. Ein simulierter Schreibfehler prüft die Wiederherstellung der bisherigen Ausgaben.

### Syntax und statische Durchsicht

Beide Inline-JavaScript-Anwendungen bestehen den Node-Parser. Alle drei M-Dateien bestehen den offiziellen Microsoft-Power-Query-Parser 5.0.0. DAX wurde manuell auf Datenmodell, Filter, Währungs-/Preislogik, Forecast und unbekannte Nutzung geprüft; eine DAX-Laufzeitprüfung hat nicht stattgefunden.

## Leistung und Darstellung

Ein synthetischer Einzeltest mit **12.000 Fakten und 120 Produkten** zeigte die erwarteten **1.200.000,00 EUR** ohne Browserfehler. Upload, Prüfung und Darstellung dauerten in dieser Instanz **0,836 Sekunden**. Dies ist eine lokale Rauchprüfung und kein allgemeiner Leistungsvergleich mit Version 1.1. Desktop (1440 px) sowie mobile Ansichten (390 px) wurden erfasst; der mobile Formularüberlauf wurde korrigiert und durch einen Regressionstest abgesichert.

## Verbleibende Grenzen und Abnahme in der Zielumgebung

1. Graph-/Azure-/GitHub-Zugriffe mit den vorgesehenen Rollen und Konten ausführen. Reportfelder, Anonymisierung, echte Abrechnungszeilen und Kostenstellenzuordnung anhand kleiner, bekannter Stichproben abstimmen.
2. Power BI Desktop: M-Abfragen aktualisieren, DAX anlegen, Beziehungen und Währungsslicer prüfen. Anschließend RLS mit tatsächlichen Lesekonten für zugeordneten und nicht zugeordneten Fachbereich testen. Syntaxprüfung ersetzt diesen Schritt nicht.
3. Katalogpreise, aktive Produkte, SKU-/Meter-Namen, Währungen, Kapazität und Jahresbudget kundenseitig pflegen. Preis 0 bei fehlenden Angaben bedeutet unvollständige Kosten. Automatische Preisversionierung je identischer Produkt-ID und Währungsumrechnung sind nicht implementiert.
4. Nur nicht überlappende Exportbestände einlesen. Inhaltliche Dubletten kumulativer Azure-/PPAC-Dateien können ohne Quell-IDs nicht zuverlässig erkannt werden. Fehlende historische Lizenzmonate werden nicht rekonstruiert.
5. Die Mindestgruppengröße ist keine garantierte Anonymisierung. Kleine Teilmengen, Zusatzwissen und Agent-/Umgebungsnamen benötigen weiterhin eine fachliche Datenschutz- und Zugriffsprüfung. Das Offline-Dashboard besitzt keine Zugriffskontrolle.
6. Die Ausgabesicherung schützt vor erkannten Schreibfehlern; ein harter Prozess-/Systemabbruch kann eine Wiederherstellung aus `.finops-*` erfordern. Leser erst nach erfolgreichem Collector-Lauf aktualisieren.

## Nachweise und Wiederholung

- [Testanleitung](../tests/README.md)
- [Browser-/Schema-/Integrationsergebnisse](Pruefergebnisse/browser-schema-tests.txt)
- [Collector-Ergebnisse](Pruefergebnisse/collector-tests.txt)
- [JavaScript-/M-Syntaxergebnisse](Pruefergebnisse/syntax-tests.txt)
- [Original 1.1: sieben erwartete Regressionen](Pruefergebnisse/original-v1.1-regressions.txt)
- [Lokale Leistungsmessung](Pruefergebnisse/performance.json)
- [Desktopansicht](Pruefergebnisse/dashboard-desktop.png), [mobile Dashboardansicht](Pruefergebnisse/dashboard-mobile.png), [mobile Konfiguration](Pruefergebnisse/configuration-mobile.png)

Werkzeuge im Testlauf: Python 3.12, Playwright 1.62.0, jsonschema 4.26.0, installiertes Chromium, Node.js 24.22.1 und PowerShell 7.4.13. PowerShell wurde aus dem offiziellen Release geladen und gegen dessen SHA-256-Datei geprüft; Testabhängigkeiten sind von der Laufzeit der beiden HTML-Anwendungen getrennt.
