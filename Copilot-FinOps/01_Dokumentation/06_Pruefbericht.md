# Prüfbericht – Copilot-FinOps 1.3

Prüfdatum: **12.11.2026**. Grundlage: Repository `d3werk/sharepoint-webpart`, Branch `main`, Commit `84661d0928bba4accb1a138d52c04bd730b787e9`. Geprüft wurden Konfigurationsoberfläche, Collector, Dashboard, Einrichtung und zugehörige Erklärungen.

## Ergebnis

**48 Browser-/Schema-/Integrationstests, 64 Collector-Prüfungen und 24 Assistenten-Prüfungen bestanden.** Kein Test im vollständigen Browserlauf wurde übersprungen. Beide JavaScript-Oberflächen und alle drei Power-Query-Abfragen bestehen die Syntaxprüfung.

Tenant-/Azure-Einstellungen sind einfacher zugänglich: Zuerst wird die Datenquelle gewählt, danach erscheinen die erforderlichen Angaben. Reine CSV-Verarbeitung benötigt keine Tenant-Anmeldung. Der neue lokale Assistent kann Tenant- und Abonnement-IDs ermitteln, gültige lokale Zertifikate anbieten und eine bestehende Konfiguration mit Sicherung aktualisieren.

Zusätzlich wurden konkrete Fehler bei unterschiedlich aktuellen Datenquellen sowie bei unvollständigen Azure-Query-Antworten behoben. Die vorhandene `config.json` mit ihren Kennungen wurde nicht verändert.

**Prüfgrenzen:** Keine echte Microsoft-/GitHub-Anmeldung, kein produktiver API-Aufruf und keine Änderung von Cloud-Ressourcen. Windows-Zertifikatszugriff sowie DAX-Ausführung, Power-BI-Refresh und RLS sind in der Zielumgebung zu prüfen.

## Einrichtung und verständliche Erklärungen

| Bisheriger Ablauf | Verhalten in 1.3 |
|---|---|
| App- und Zertifikatsangaben stehen vor der Quellenwahl. Alle Quellenbereiche sind ständig sichtbar. | Quellenwahl und passende Einstiegsschaltflächen stehen zuerst. Nur benötigte Quellenbereiche erscheinen; die App-Anmeldung wird nur für Graph/Azure Query eingeblendet. |
| Tenant-, App-, Zertifikat- und Subscription-Angaben müssen aus mehreren Stellen übertragen werden. | Begriffe und Fundstellen sind erklärt. `Einrichten-CopilotFinOps.ps1 -DiscoverAzure` kann Tenant und auswählbare Abonnements lesen; unter Windows bietet der Assistent gültige Zertifikate mit privatem Schlüssel an. |
| Benutzerrechte bei der Ermittlung und App-Rechte bei der Sammlung können verwechselt werden. | Benutzer-Discovery, Collector-App, Graph-Administratorzustimmung und Azure-IAM-Rolle werden getrennt erklärt. Es werden keine Apps, Rollen oder Ressourcen automatisch angelegt. |
| Die Voraussetzungprüfung wird im bisherigen Schnellstart vor fertig eingerichteter Konfiguration/Zertifikat aufgerufen. | Die Anleitung beginnt mit Demo und Quellenwahl; die Voraussetzungprüfung folgt auf App/Zertifikat und Konfiguration. |
| JSON-Vorschau und inaktive Felder überladen die Maske. | Technische Vorschau ist eingeklappt; Azure Export und Query werden mit ihrem konkreten Aufwand erklärt. |
| Speichern kann als direkte Änderung der Paketdatei verstanden werden. | Die Maske erklärt Download, Ablage als `02_Konfiguration/config.json` und nächsten Collector-Schritt ausdrücklich. |
| Formale Vollständigkeit kann mit funktionierendem Cloud-Zugriff verwechselt werden. | Browserprüfung und `-ValidateOnly` sind als lokale Format-/Pflichtfeldprüfung beschrieben. `-WhatIf` ist ausdrücklich nur eine Aktionsvorschau. |

Die Graph-Anleitung nennt `LicenseAssignment.Read.All` als geringste Anwendungsberechtigung für `subscribedSkus`, entsprechend der [Microsoft-Dokumentation](https://learn.microsoft.com/en-us/graph/api/subscribedsku-list?view=graph-rest-1.0). Bestehendes `Organization.Read.All` bleibt eine funktionierende, weitergehende Freigabe. Andere App-Aufgaben sind vor Änderungen bestehender Rechte zu berücksichtigen.

### Verhalten des neuen Assistenten

- Vorhandene und unbekannte JSON-Einstellungen bleiben erhalten. Explizite PPAC-Spaltennamen werden bewahrt; leere PPAC-Standardfelder der bisherigen Vorlage erhalten ihre Standardnamen.
- Die vorbereitete Datei wird vor dem Ersetzen durch dieselbe formale Prüfung wie im Collector geprüft. Ein Fehler erhält die ursprüngliche Datei.
- Vor dem Überschreiben entsteht eine datierte Sicherung; zwischenzeitlich veränderte Konfigurationen werden nicht überschrieben. Sicherungen und temporäre Konfigurationsdateien sind in `.gitignore` berücksichtigt.
- Discovery berücksichtigt einen vorhandenen Tenant. Ein abweichender angemeldeter Tenant wird abgewiesen. Ein bewusster Wechsel erfolgt über `-TenantId`.
- Azure-Abonnements werden gezielt ausgewählt. Im unbeaufsichtigten Discovery-Modus sind explizite `-SubscriptionIds` erforderlich; es werden niemals automatisch sämtliche sichtbaren Abonnements übernommen.
- `-WhatIf` startet keine Anmeldung, fragt keine Werte ab und schreibt keine Dateien. Es validiert auch keine Konfiguration.

## Fachliche Fehlerkorrekturen

| Befund | Korrektur und Nachweis |
|---|---|
| September-Kapazitätsverbrauch kann bei neueren Oktober-Lizenzdaten als null erscheinen; ein Pool mit 100 Credits und 70 verbrauchten Credits zeigt dann fälschlich 100 frei. | Der letzte vorhandene Monat des Kapazitätsprodukts ist maßgeblich. Das Ergebnis lautet September: 70 verbraucht, 30 frei. Ein Filter ohne Verbrauchsdaten zeigt „nicht verfügbar“. Regression im bisherigen Stand nachgewiesen. |
| Lizenz- und Chat-Auswertungen verwenden den jüngsten Monat sämtlicher Quellen. | Die Ansichten verwenden ihren passenden Lizenz-/Chat-Monat. DAX-Measures wurden entsprechend angepasst; die DAX-Anpassung ist manuell geprüft. |
| Ein nachgeliefertes Budget setzt Filter zurück. | Ergänzende Dateien erhalten gültige Filter. Neue Fakten aktualisieren den Zeitraum; ein eigener Button setzt Filter zurück. |
| Importfehler verschwinden nach dem Schließen eines Dialogs. | Fehler bleiben sichtbar; zuvor geladene Daten und Filter bleiben bei fehlgeschlagenem Import erhalten. Demo und geladene Dateitypen sind eindeutig gekennzeichnet. |
| Leere oder doppelte Query-Scopes können leere Ergebnisse bzw. doppelte Kosten erzeugen. | Der Collector verwirft fehlende, ungültige und doppelte Scopes vor Anmeldung/Datensammlung. Die Maske entfernt doppelte Subscription-Eingaben einmalig und erklärt dies. |
| Die Maske verlangt auch für Azure-CSV einen Kostenstellen-Tag, obwohl der Collector Exporte ohne Tag unterstützt. | Der Tag ist bei Export optional. Ein Export lässt sich ohne Tenant, Zertifikat oder Tag konfigurieren; bei Query bleibt der Tag erforderlich. |
| Fehlende Azure-Kosten-/Mengenwerte können durch Typumwandlung zu null werden. | Query-Antworten werden auf erforderliche, eindeutige Spalten, passende Zeilenbreite und vorhandene Zahlenwerte geprüft. Fehlende Werte führen zu einem Fehler. |
| Eine Azure-Query-Tagspalte kann den konfigurierten Tag-Namen statt `TagValue` tragen. | Beide Varianten werden berücksichtigt. Fehlt die angeforderte Tagspalte, bricht die Quelle ab; tatsächlich leere Tagwerte bleiben „Nicht getaggt“. |
| Geladene Altoptionen und zusätzliche PPAC-Mappings können beim erneuten Speichern verschwinden. | Auch `Pseudonymize` und zusätzliche PPAC-Mapping-Schlüssel bleiben erhalten. Platzhalter werden sichtbar als Fehler behandelt und nicht still entfernt. |

## Ausgeführte Prüfungen

| Prüfung | Ergebnis | Nachweis |
|---|---|---|
| Vollständige Chromium-/Schema-/Collector-Integration | **48 bestanden**, keine übersprungen | [Browserprotokoll](Pruefergebnisse/v1.3-browser-schema-tests.txt) |
| Echte PowerShell-Collector-Funktionen, CSV-Unterprozesse und API-Mocks | **64 bestanden** | [Collectorprotokoll](Pruefergebnisse/v1.3-collector-tests.txt) |
| Assistent, Sicherungen, Fehlererhalt, Discovery-Mocks und lokale Validierung | **24 bestanden** | [Assistentenprotokoll](Pruefergebnisse/v1.3-setup-tests.txt) |
| Inline-JavaScript und offizieller Microsoft-Power-Query-Parser | **2 HTML-Anwendungen und 3 M-Abfragen gültig** | [Syntaxprotokoll](Pruefergebnisse/v1.3-syntax-tests.txt) |
| Neue Kapazitätsregression gegen unveränderten bisherigen Quellstand | **Erwarteter Fehler nachgewiesen:** 0 statt 70 Verbrauch | [Baseline-Nachweis](Pruefergebnisse/v1.2-capacity-regression.txt) |
| Desktop und mobile Darstellung | Keine horizontale Seitenüberschreitung; zusätzlich 320 px mit ausgeklappter Hilfe/Vorschau getestet | [Konfiguration Desktop](Pruefergebnisse/v1.3-configuration-desktop.jpg), [Konfiguration mobil, Azure CSV](Pruefergebnisse/v1.3-configuration-mobile.jpg), [Dashboard mobil](Pruefergebnisse/v1.3-dashboard-mobile.jpg) |

Der Integrationstest führt den echten PPAC-Collector als PowerShell-Unterprozess aus und lädt dessen Fakten und Katalog im Chromium-Dashboard. Externe HTTP-Anfragen der HTML-Anwendungen werden in den Browserprüfungen als Fehler gewertet. Discovery und Cloud-APIs werden ausschließlich nachgebildet.

Die bestehenden Vorschautests lesen jetzt `text_content()`: Bei geschlossenem HTML-`details` liefert `inner_text()` keinen Vorschautext. Damit prüfen die Tests weiterhin die tatsächlichen serialisierten Werte und vergleichen keine leeren Zeichenketten.

Werkzeuge: Python **3.12.14**, Playwright **1.62.0**, jsonschema **4.26.0**, Chromium **156.0.8078.79**, Node.js **24.22.1**, Microsoft Power Query Parser **5.0.0**, PowerShell **7.4.13**. Der PowerShell-Download wurde gegen die SHA-256-Angabe des offiziellen Releases geprüft. Reproduzierbare Befehle stehen in der [Testanleitung](../tests/README.md).

## Verbleibende Abnahme

1. Die gewählten Quellen mit echten Daten und den Rechten der Collector-App testen. Sichtbarkeit für den Discovery-Benutzer beweist keine Zugriffsrechte der App.
2. Auf dem ausführenden Windows-Konto Zertifikatsgültigkeit, privaten Schlüssel und tatsächliche App-Anmeldung prüfen.
3. Preise, SKU-/Meter-Zuordnungen, Reportfelder, Exportspalten und Anonymisierung im Zieltenant anhand bekannter Stichproben abstimmen.
4. DAX und Power Query in Power BI ausführen sowie Refresh, Beziehungen und RLS mit den vorgesehenen Lesekonten prüfen. Die Syntaxprüfung ist kein Laufzeitnachweis.
5. Inhaltlich überlappende Azure-/PPAC-Exporte vor dem Einlesen bereinigen. Ohne eindeutige Quellschlüssel kann das Paket kumulative Exportstände nicht zuverlässig deduplizieren. Fehlende historische Lizenzmonate werden nicht rekonstruiert.

Die bisherigen Prüfungen und Grenzen der Version 1.2 sind im [historischen Prüfbericht](06_Pruefbericht-v1.2.md) erhalten. Die bestehenden ZIP-Dateien im Repository sind ältere Paketstände; maßgeblich für Version 1.3 ist der überarbeitete Quellordner.

