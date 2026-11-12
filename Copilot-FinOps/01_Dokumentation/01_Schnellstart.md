# Schnellstart – vom ersten Blick zu eigenen Daten

Version 1.3 · Stand 12.11.2026

Diese Anleitung beginnt ohne Microsoft-Anmeldung. Danach wählst du nur den Weg für die Daten, die du tatsächlich auswerten möchtest. Die Konfiguration verbindet noch keine Datenquelle; erst der Collector liest die aktivierten Quellen aus.

## 1. Dashboard sofort kennenlernen

Das vollständige Paket entpacken und `04_Dashboard/copilot-cost-dashboard.html` im Browser öffnen. Es zeigt ausdrücklich gekennzeichnete Beispieldaten. Du kannst zwischen Übersicht, Lizenzen, Credits und Katalog wechseln, ohne etwas einzurichten.

**Erwartetes Ergebnis:** Das Dashboard ist sichtbar und kennzeichnet den Datenstand als Beispieldaten. Es zeigt noch keine Daten deiner Organisation.

## 2. Den passenden Weg wählen

| Du möchtest … | Quelle / Verfahren | Was du bereitstellen musst |
|---|---|---|
| vorhandene Azure-Kostenexporte auswerten | Azure / **Export** | lokale CSV-Dateien und passende Spaltenzuordnung |
| Copilot-Studio-Credits auswerten | **PPAC** | lokale CSV-Dateien aus dem Power Platform Admin Center |
| M365-Lizenzen und Nutzung automatisch lesen | **Graph** | Entra-App, Zertifikat, Graph-Anwendungsberechtigungen |
| Azure-Kosten ohne lokalen CSV-Export abfragen | Azure / **Query** | Entra-App, Zertifikat, ausgewählte Abonnements und Azure-Rolle |
| GitHub Copilot lesen | **GitHub** | Organisation und Token als Umgebungsvariable |

**Der geringste Einrichtungsaufwand ist CSV**, wenn passende Exporte bereits vorhanden sind. Dafür braucht der Collector keine Tenant-ID, App-ID oder Zertifikatsanmeldung. Azure Export erfordert außerhalb dieses Pakets weiterhin jemanden, der den Export einrichtet bzw. die Datei herunterladen darf.

Mehrere Quellen lassen sich später kombinieren. Für den ersten eigenen Lauf nur eine vollständig vorbereitete Quelle einschalten.

## 3. Die vier Kennungen auseinanderhalten

| Angabe | Bedeutung | Woher kommt sie? | Wann benötigt? |
|---|---|---|---|
| **Tenant-ID** (`TenantId`) | Organisationsverzeichnis in Microsoft Entra ID | Entra Admin Center → Identität → Übersicht → Mandanten-ID; alternativ Assistent mit `-DiscoverAzure` | Graph oder Azure Query |
| **Client-ID** (`ClientId`) | Kennung der registrierten Collector-Anwendung | Entra Admin Center → App-Registrierungen → eigene App → Übersicht → Anwendungs-ID (Client) | Graph oder Azure Query |
| **Zertifikat-Fingerabdruck** (`CertificateThumbprint`) | Kennung des Zertifikats, dessen privater Schlüssel lokal liegt | Ausgabe von `New-AppZertifikat.ps1` oder Zertifikatsauswahl im Assistenten | Graph oder Azure Query |
| **Abonnement-ID** (`AzureScopes`) | Azure-Abonnement, dessen Kosten gelesen werden | Azure-Portal → Abonnements → Abonnement-ID; alternativ Auswahl im Assistenten | Azure Query |

Tenant-ID und Abonnement-ID sind verschiedene Kennungen. In der App-Übersicht die **Anwendungs-ID**, nicht die Objekt-ID kopieren. Ein Fingerabdruck ist kein Client-Secret: In `config.json` gehören weder ein Secret noch ein privater Schlüssel.

## 4. Konfiguration erstellen: Browser oder Assistent

**Reihenfolge je Einrichtungsweg:** Für CSV kannst du direkt hier beginnen und anschließend Schritt 5a ausführen. Für **Graph oder Azure Query** zuerst unter [Schritt 5b](#5b-automatischer-zugriff-graph-oder-azure-query) das Zertifikat und die App vorbereiten. Danach hierher zurückkehren und die Konfiguration mit den ermittelten Kennungen abschließen. Die Maske kann eine Graph-/Query-Konfiguration erst speichern, wenn deren Anmeldeangaben vollständig sind.

Vorhandene `02_Konfiguration/config.json` zuerst sichern. In der Browsermaske **Vorhandene config.json laden** verwenden, damit zusätzliche Einstellungen erhalten bleiben. Der Assistent liest die bestehende Datei selbst und legt vor dem Überschreiben zusätzlich eine datierte `.bak` an.

### Möglichkeit A: Browsermaske

1. `02_Konfiguration/Konfiguration-CopilotFinOps.html` öffnen.
2. Die benötigten Datenquellen wählen. Nur die dazu passenden Angaben werden benötigt.
3. Für Azure **Export** oder **Query** wählen; danach Importordner bzw. Abonnements angeben.
4. Fehler in der Prüfung korrigieren und **config.json speichern** wählen.
5. Die heruntergeladene Datei unter **`02_Konfiguration/config.json`** ablegen. Der Browser kann die Datei im Paket nicht selbst ersetzen; eine Datei im Downloads-Ordner oder `config (1).json` wird vom Collector nicht automatisch verwendet.

Die Prüfung bestätigt Datenformate und Pflichtfelder. Sie führt keine Anmeldung durch und bestätigt weder Zugriffsrechte noch die tatsächliche Erreichbarkeit der APIs.

### Möglichkeit B: lokaler PowerShell-Assistent

PowerShell **7.2 oder neuer** öffnen (`pwsh`, nicht die alte Windows PowerShell 5.1). In den entpackten Ordner `Copilot-FinOps` wechseln und starten:

```powershell
./03_Collector/Einrichten-CopilotFinOps.ps1
```

Der Assistent bietet die Quellenwahl an. Unter Windows kann er gültige Zertifikate mit privatem Schlüssel zur Auswahl anzeigen. Vorhandene Angaben und zusätzliche JSON-Felder bleiben erhalten. Für einen reinen PPAC-Import ist beispielsweise möglich:

```powershell
./03_Collector/Einrichten-CopilotFinOps.ps1 -Sources PPAC
```

Tenant und Azure-Abonnements lassen sich mit einer Benutzeranmeldung ermitteln. Dazu einmalig das Modul für das aktuelle Benutzerkonto installieren, falls es fehlt:

```powershell
Install-Module Az.Accounts -Repository PSGallery -Scope CurrentUser
./03_Collector/Einrichten-CopilotFinOps.ps1 -Sources Azure -AzureMode Query -DiscoverAzure
```

Ein bereits konfigurierter gültiger Tenant wird berücksichtigt. Für einen bewussten Tenant-Wechsel `-TenantId "<neue Tenant-ID>"` ergänzen. Nach der Anmeldung werden die im gewählten Tenant zugänglichen Abonnements angezeigt. Nur die Abonnements auswählen, die der Collector auswerten soll. Die Werte werden als `/subscriptions/<ID>` gespeichert. Für **Graph ohne Azure-Abonnement** die Tenant-ID manuell eintragen; Azure-Discovery ist dafür nicht erforderlich.

**Was dieser Schritt vereinfacht:** Tenant-ID und Abonnement-IDs müssen nicht aus mehreren Portalseiten kopiert werden. **Was danach nötig bleibt:** Client-ID der Collector-App, deren Zertifikat und die passenden Berechtigungen. Die Benutzeranmeldung zur Ermittlung der Kennungen wird nicht als Collector-Anmeldung gespeichert. Rechte des angemeldeten Benutzers werden nicht auf die App übertragen.

Eine Aktionsvorschau ohne Schreiben und ohne Cloud-Anmeldung ist möglich:

```powershell
./03_Collector/Einrichten-CopilotFinOps.ps1 -Sources PPAC -NonInteractive -WhatIf
```

`-WhatIf` erstellt keine Datei und führt auch mit `-DiscoverAzure` keine Anmeldung durch. Es prüft weder die Konfigurationswerte noch die Verbindung. Für eine formale Prüfung die vorhandene Konfiguration mit `-ValidateOnly` prüfen (Schritt 6). Für unbeaufsichtigte lokale Konfiguration unterstützt der Assistent zusätzlich `-TenantId`, `-ClientId`, `-CertificateThumbprint`, `-SubscriptionIds`, `-CostCenterTag` und `-NonInteractive`. IDs in PowerShell als Zeichenketten übergeben, mehrere Quellen als `-Sources Graph,Azure`.

**Erwartetes Ergebnis:** Im Paket liegt eine `02_Konfiguration/config.json`, deren aktivierte Quellen und Angaben zu deinem gewählten Weg passen.

## 5a. Einfacher Weg: lokale CSV-Dateien

Dieser Weg benötigt PowerShell 7.2+, aber weder `Az.Accounts` noch eine App-Registrierung oder ein Zertifikat. Er funktioniert auch unter Linux/macOS.

### Azure Export

1. Im Azure-Portal einen passenden Cost-Management-Export für tatsächliche Kosten bereitstellen lassen. Exportberechtigungen und Storage-Zugriff liegen bei der dafür zuständigen Azure-Administration.
2. Die exportierten CSV-Dateien nach `06_Daten/import/azure-export` kopieren. Der Collector lädt sie nicht automatisch aus Azure Storage herunter.
3. In der Maske Quelle **Azure**, Verfahren **Export** wählen. Den Importordner kontrollieren.
4. `AzureExportColumnMap` anhand der echten CSV-Kopfzeile prüfen. Die Standardzuordnung erwartet unter anderem `Date`, `CostInBillingCurrency`, `Quantity` und `BillingCurrencyCode`. Abweichende Exporte benötigen eine angepasste Zuordnung in `config.json`.
5. Bei Fachbereichszuordnung über Tags den tatsächlichen Tag-Namen unter `CostCenterTag` eintragen.

Überlappende kumulative Exporte desselben Zeitraums ersetzen. Sie nicht gemeinsam im Importordner ablegen, sonst werden dieselben Kosten mehrfach eingelesen.

### PPAC / Copilot Studio

1. Den Verbrauch als CSV aus dem Power Platform Admin Center exportieren und nach `06_Daten/import/ppac` legen.
2. Quelle **PPAC** aktivieren. Die tatsächlichen CSV-Spalten für Datum, Umgebung, Agent und Credits in der Maske eintragen. Die Standardnamen sind `Date`, `Environment`, `Agent`, `Credits`.
3. Die Produkt-ID muss auf das gewünschte Produkt im Lizenzkatalog zeigen, z. B. `CS-CAPACITY`.
4. Umgebungen bei Bedarf Fachbereichen zuordnen. Ohne Zuordnung erscheinen sie als „Nicht zugeordnet“.

Die Namen sind Exportfelder, keine universell garantierten PPAC-Spalten. Für Datumswerte ISO `2026-11-02` oder deutsches Punktformat `02.11.2026` verwenden; Zahlen ohne Tausendertrennzeichen.

Danach mit Schritt 6 fortfahren.

## 5b. Automatischer Zugriff: Graph oder Azure Query

Dieser Weg verwendet eine **Collector-App mit Zertifikat**. Dafür wird Windows mit PowerShell 7.2+ benötigt. Das Zertifikat unter dem Konto erstellen, unter dem der Collector später läuft.

### Zertifikat und App einmalig vorbereiten

1. `./03_Collector/New-AppZertifikat.ps1` ausführen. Der private Schlüssel bleibt im lokalen Zertifikatspeicher; neben dem Skript entsteht die öffentliche Datei `Copilot-FinOps-Collector.cer`. Fingerabdruck notieren.
2. [Entra Admin Center](https://entra.microsoft.com) → **App-Registrierungen → Neue Registrierung** öffnen. Name z. B. `Copilot-FinOps-Collector`, Kontotyp nur dieses Organisationsverzeichnis, Umleitungs-URI leer.
3. Aus der App-Übersicht **Anwendungs-ID (Client)** und **Verzeichnis-ID (Mandant)** übernehmen.
4. **Zertifikate & Geheimnisse → Zertifikate → Zertifikat hochladen**: die öffentliche `.cer`-Datei auswählen. Ein Client-Secret wird nicht benötigt.
5. Die Berechtigungen für die gewählten Quellen einrichten:

| Quelle | Berechtigung der Collector-App | Freigabe |
|---|---|---|
| Graph: Lizenzbestand | Microsoft Graph **Anwendungsberechtigung** `LicenseAssignment.Read.All` | Administratorzustimmung |
| Graph: Benutzer und Fachbereiche | Microsoft Graph **Anwendungsberechtigung** `User.Read.All` | Administratorzustimmung |
| Graph: Copilot-Nutzungsbericht | Microsoft Graph **Anwendungsberechtigung** `Reports.Read.All` | Administratorzustimmung; Bericht/API im Zieltenant prüfen |
| Azure Query | Azure-Rolle **Cost Management Reader** auf jedem ausgewählten Abonnement | Rollenzuweisung in Azure IAM an den Dienstprinzipal der Collector-App |

Für `subscribedSkus` ist `LicenseAssignment.Read.All` die laut [Microsoft-Dokumentation](https://learn.microsoft.com/en-us/graph/api/subscribedsku-list?view=graph-rest-1.0) geringste Anwendungsberechtigung. Eine bestehende Freigabe von `Organization.Read.All` deckt diesen Zugriff ebenfalls ab, ist dafür aber weitergehend. Bestehende Berechtigungen nur nach Prüfung anderer App-Aufgaben entfernen.

Graph-Rechte unter **API-Berechtigungen → Microsoft Graph → Anwendungsberechtigungen** hinzufügen. Die Zustimmung muss ein dafür berechtigter Administrator erteilen, z. B. Privileged Role Administrator oder Global Administrator. Eine Person, die eine App registrieren darf, darf nicht automatisch auch alle Graph-Anwendungsberechtigungen genehmigen.

Azure-Rechte unter **Abonnement → Zugriffssteuerung (IAM)** vergeben lassen. Dabei die Collector-App auswählen, nicht den Benutzer des Einrichtungsassistenten. Graph-Administratorzustimmung allein erteilt keine Azure-Kostenrechte und eine Azure-Rolle erteilt keine Graph-Rechte.

### Konfiguration und Voraussetzungen abschließen

6. In Maske oder Assistent Tenant-ID, Client-ID und Zertifikat-Fingerabdruck übernehmen. Unter Azure Query zusätzlich die ausgewählten Abonnements und den tatsächlichen Kostenstellen-Tag angeben.
7. Den Lizenzkatalog prüfen: `graphSkuPartNumber` muss zu den tatsächlichen Tenant-SKUs passen; Azure-Zuordnungsschlüssel müssen zu den exportierten bzw. abgefragten Metern passen. Einträge mit `[prüfen]` werden übersprungen.
8. **Jetzt** `./03_Collector/Install-Voraussetzungen.ps1` ausführen. Dieses Skript liest die fertige Konfiguration, installiert bei Bedarf `Az.Accounts` und prüft das konfigurierte lokale Zertifikat. Deshalb kommt es erst nach der Zertifikaterstellung und Konfiguration.

Unter Azure Query werden monatliche Kosten nach Meter und dem konfigurierten Tag gruppiert. Die Tagwerte sind Grundlage der Fachbereichszuordnung; fehlende oder uneinheitliche Tags lassen sich nicht durch die Subscription-Auswahl ersetzen. API-Version und Query-Unterstützung im Zielabonnement prüfen.

**Erwartetes Ergebnis:** Die Voraussetzungprüfung findet das gültige Zertifikat mit privatem Schlüssel. Das bestätigt die lokale Einrichtung; der erste Collector-Lauf prüft anschließend den tatsächlichen Cloud-Zugriff.

## 5c. GitHub Copilot

Quelle **GitHub**, Organisationsname und Standard-Fachbereich konfigurieren. Einen für die verwendeten Copilot-/Billing-Endpunkte berechtigten Token außerhalb von `config.json` unter **`FINOPS_GITHUB_TOKEN`** für das ausführende Konto hinterlegen. Tokentyp, Organisationsfreigabe und API-Zugriff anhand der aktuellen GitHub-Dokumentation prüfen.

Eine Entra-App wird nur zusätzlich benötigt, wenn gleichzeitig Graph oder Azure Query aktiviert sind.

## 6. Daten sammeln und Ergebnis prüfen

Unter Windows `03_Collector/Start-Collector.cmd` starten. Plattformübergreifend aus PowerShell 7:

```powershell
./03_Collector/Collect-CopilotCosts.ps1 -ConfigPath ./02_Konfiguration/config.json
```

Vor dem ersten Zugriff kann die Konfiguration lokal geprüft werden:

```powershell
./03_Collector/Collect-CopilotCosts.ps1 -ConfigPath ./02_Konfiguration/config.json -ValidateOnly
```

`-ValidateOnly` prüft die Konfigurationswerte ohne Anmeldung und ohne Ergebnisdateien zu schreiben. Die tatsächlichen Berechtigungen werden dabei nicht geprüft. Der Einrichtungsassistent führt diese lokale Prüfung vor dem Speichern ebenfalls aus.

Nach einem erfolgreichen Lauf liegen unter `06_Daten/out` die Dateien `facts.json`, `facts.csv`, `lizenzkatalog.json` und ein Protokoll `collector_*.log`. Der Collector beendet sich bei Fehlern mit einem von null verschiedenen Status; vorhandene Ergebnisdateien werden bei einer fehlgeschlagenen Quelle nicht durch einen unvollständigen neuen Lauf ersetzt.

Das Dashboard öffnen, **Daten laden** wählen und `facts.json` sowie `lizenzkatalog.json` aus diesem Ausgabeordner gemeinsam auswählen. Bei Bedarf Budget und Kapazität ergänzen. Prüfen, ob Datenstand, Quellen, Produkte und Fachbereiche plausibel sind. Alte Dateien nach einem Fehler sind kein aktuelles Ergebnis.

### Häufige Probleme

| Meldung / Beobachtung | Nächster sinnvoller Schritt |
|---|---|
| `config.json` fehlt oder alte Quellen bleiben aktiv | Download wirklich unter `02_Konfiguration/config.json` ablegen; vorhandene Datei vorher in der Maske laden |
| Ungültige Tenant-/Client-ID | richtige Kennung aus der App-Übersicht übernehmen; Objekt-ID und Abonnement-ID nicht verwechseln |
| Ungültiger Zertifikat-Fingerabdruck | vollständigen Fingerabdruck neu kopieren; erwartete Länge 40 Hex-Zeichen; nicht durch erfundene Zeichen ergänzen |
| Zertifikat nicht gefunden / kein privater Schlüssel | Collector unter dem Konto der Zertifikaterstellung starten; eine hochgeladene `.cer` allein enthält keinen privaten Schlüssel |
| Graph antwortet mit 403 | Anwendungsberechtigungen und erteilte Administratorzustimmung für genau diese App prüfen |
| Azure Query antwortet mit 403 | Cost-Management-Rolle der **App** am richtigen Abonnement prüfen; Benutzerzugriff im Assistenten genügt nicht |
| Azure-Abonnement fehlt in der Auswahl | angemeldeten Tenant und Zugriffsrechte des Benutzers prüfen; alternativ bekannte Abonnement-ID manuell angeben |
| Keine passenden Kosten / SKUs | Katalogzuordnung, aktive Produkte, Zeitbereich und tatsächliche Export-/API-Felder prüfen |
| PPAC-Spalte fehlt | CSV-Kopfzeile mit `PpacColumnMap` abgleichen; keine leeren Spaltennamen verwenden |
| Kosten wirken zu niedrig | fehlende Preise, nicht zugeordnete Produkte, Datenzeitraum und Währung kontrollieren |
| Copilot-Aktivität unbekannt | Berichtszugriff und Namensverschleierung im M365-Bericht prüfen; aus unbekannter Aktivität keine Einsparung ableiten |

## 7. Erst danach automatisieren

Nach einem erfolgreichen manuellen Lauf unter demselben Konto eine Aufgabe einrichten, beispielsweise täglich um 05:00 Uhr:

- Programm: `pwsh.exe`
- Argumente: `-NoProfile -File "C:\FinOps\Copilot-FinOps\03_Collector\Collect-CopilotCosts.ps1" -ConfigPath "C:\FinOps\Copilot-FinOps\02_Konfiguration\config.json"`
- Konto: das Konto mit Zugriff auf den privaten Zertifikatsschlüssel und die benötigten lokalen Dateien

Protokoll, Exit-Code und Zeitstempel überwachen. Zertifikaterneuerung, Importlieferungen, Preise und Wiederanlauf sind im [Betriebsleitfaden](04_Betriebsleitfaden.md) beschrieben. Lokale Formatprüfungen und Tests ersetzen die Abnahme mit echten Daten und Rechten im Zieltenant nicht.
