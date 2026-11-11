# Power-BI-Bauanleitung

## 1. Abfragen anlegen (Power BI Desktop)
1. **Daten transformieren → Parameter verwalten**, um zwei Textparameter anzulegen:
   - `DatenOrdner` = `C:\FinOps\Copilot-FinOps\06_Daten\out\` (mit abschließendem `\`)
   - `KonfigOrdner` = `C:\FinOps\Copilot-FinOps\02_Konfiguration\Beispiele\`
2. **Neue Quelle → Leere Abfrage → Erweiterter Editor** und den Inhalt einfügen aus:
   - `PowerQuery_FactKosten.pq` → Abfrage `FactKosten`
   - `PowerQuery_DimProdukt.pq` → Abfrage `DimProdukt`
   - `PowerQuery_Budget.pq` → Abfrage `Budget`
   `FactKosten` liest ab Version 1.2 die `facts.json`, nicht die Excel-sichere `facts.csv`. Vorhandene Abfragen entsprechend ersetzen. Textschlüssel bleiben so unverändert; unbekannte Zählwerte bleiben `null`.
3. `DimFachbereich`: Verweis auf FactKosten → nur die Spalte `fachbereich` behalten → Duplikate entfernen → in `Fachbereich` umbenennen. Fachbereiche, die nur im Budget vorkommen, per Anfügen ergänzen.
4. `RLS_Mapping` (UPN, Fachbereich) als Excel- oder SharePoint-Liste einbinden.
5. What-if-Parameter `Packs` anlegen (Anzahl gekaufter Capacity Packs).

## 2. Modell
- `DimDatum` als berechnete Tabelle aus `DimDatum.dax` anlegen und als Datumstabelle markieren.
- Beziehungen (1:n, einfache Filterrichtung):
  - `DimDatum[Datum]` → `FactKosten[Datum]`
  - `DimProdukt[produktId]` → `FactKosten[produktId]`
  - `DimFachbereich[Fachbereich]` → `FactKosten[fachbereich]` und → `Budget[Fachbereich]`
- Berechnete Spalten und Measures aus `DAX_Measures.dax` übernehmen.
- **Preisstände:** Gibt es je `produktId` mehrere Katalogzeilen (Preisänderung mit `gueltigAb`/`gueltigBis`), dann `produktId` im Katalog je Preisstand eindeutig halten (z. B. `M365-COPILOT@2027`) oder eine Preistabelle mit LOOKUPVALUE nach Datum verwenden. Die mitgelieferte Spalte `Preis` deckt einen Preisstand je Produkt ab.

## 3. Berichtsseiten
1. **Übersicht:** KPI-Karten (Kosten Gesamt, Kosten YTD, Forecast Jahresende, Budget + Ampel, Produkte ohne Preis), Liniendiagramm Kosten je Monat, Balken nach Produktfamilie, Abrechnungsart und Region, Matrix Fachbereich × Budget/Ist/Ausschöpfung/Ampel.
2. **Lizenzen & User:** Tabelle Produkt × Fachbereich mit zugewiesenen und aktiven Lizenzen, Auslastung (bedingte Formatierung < 60 % rot, < 80 % gelb) und Einsparpotenzial sowie Tabelle Unlizenzierte Nutzer.
3. **Credits & Verbrauch:** Linie Credits verbraucht mit Konstantenlinie Kapazität, Tabelle Agent × Umgebung × Fachbereich, Balken der Azure-Kosten je Fachbereich.
4. **Lizenzkatalog:** Tabelle `DimProdukt`; leere Preise werden rot hervorgehoben.
- Synchronisierte Slicer auf allen Seiten: Zeitraum, Produktfamilie, Fachbereich, Region, Abrechnungsart.
- Zusätzlich einen Währungsslicer auf `FactKosten[Währung]` mit Einzelauswahl verwenden. Keine impliziten Summen der berechneten Spalte `Kosten` anzeigen, sondern die währungsgeprüften Measures. Ohne eindeutige Währung bleiben Geld-Measures leer. `Budget` gilt nur für `waehrungStandard` des Katalogs und das ausgewertete Geschäftsjahr.
- Für Kapazitäts-KPIs genau ein Kapazitätsprodukt auswählen; Credits und SCU sind nicht addierbar. Der automatisch erzeugte What-if-Parameter verwendet `Packs[Packs]`.
- Die Preisgültigkeit wird am Monatsersten geprüft; `ProUser`-Jahrespreise werden auf Monate verteilt. Ohne mindestens zwei Ist-Monate in den letzten drei Kalendermonaten ist der Forecast unbekannt (außer im Dezember). Fehlende Preise bedeuten unvollständige Jahreswerte.
- Für den Export „Daten exportieren“ zulassen; für Management-Berichte „In PDF exportieren“ verwenden.

## 4. Row-Level Security
**Modellierung → Rollen verwalten → Rolle `Fachbereichsleitung`**, Tabellenfilter auf `DimFachbereich`:
```DAX
[Fachbereich] IN CALCULATETABLE ( VALUES ( RLS_Mapping[Fachbereich] ), RLS_Mapping[UPN] = USERPRINCIPALNAME () )
```
Nach der Veröffentlichung im Power-BI-Dienst unter Dataset → Sicherheit die Entra-Gruppe der Fachbereichsleitungen zuordnen. Admin und Controlling erhalten keine Rolle mit Filter (Arbeitsbereichsrolle „Mitwirkender“ bzw. Leserecht auf eine ungefilterte App).

Vor Freigabe mit **Als Rolle anzeigen** und anschließend mit einem tatsächlichen Lesekonto testen: eigener Fachbereich sichtbar, fremder Fachbereich unsichtbar, nicht zugeordnete Identität ohne Daten. Budget- und Kostenseiten ebenfalls prüfen. RLS ersetzt keine geeigneten Arbeitsbereichsrollen; die Ausführung dieser Prüfungen ist in der Cloud-Linux-Umgebung nicht erfolgt.

## 5. Aktualisierung
Bei lokaler Ablage ist ein **On-Premises-Datengateway** nötig. Alternativ den Ausgabeordner per OneDrive/SharePoint synchronisieren und die Quelle auf SharePoint-Ordner umstellen. Die geplante Aktualisierung täglich nach dem Collector-Lauf einrichten, z. B. um 07:00 Uhr.
