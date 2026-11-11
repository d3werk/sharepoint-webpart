# Schnellstart – Einrichtung Schritt für Schritt

Diese Anleitung ist auch ohne Skriptkenntnisse umsetzbar. Die Schritte 1–3 werden nur einmal ausgeführt.

## Voraussetzungen
- Windows-Rechner oder -Server, auf dem der Collector regelmäßig laufen darf
- **PowerShell 7.2 oder neuer** (https://aka.ms/powershell)
- Rechte für die App-Registrierung: Anwendungsadministrator und Global Admin bzw. Privileged Role Admin für die Administratorzustimmung

Für reine Azure-Export-/PPAC-CSV-Importe sind App-Registrierung, Zertifikat und `Az.Accounts` nicht erforderlich; diese Workflows funktionieren auch mit PowerShell unter Linux. Schritte 1–3 nur für Graph bzw. Azure Query ausführen. GitHub nutzt separat `FINOPS_GITHUB_TOKEN`.

## Schritt 1 – Voraussetzungen installieren
1. PowerShell 7 öffnen (`pwsh`). Dafür das Konto verwenden, unter dem der Collector später laufen soll.
2. `03_Collector\Install-Voraussetzungen.ps1` ausführen. Das Skript installiert das Modul `Az.Accounts`.

## Schritt 2 – Zertifikat erstellen
1. `03_Collector\New-AppZertifikat.ps1` ausführen.
2. Den angezeigten **Fingerabdruck** notieren. Daneben entsteht die Datei `Copilot-FinOps-Collector.cer`.

## Schritt 3 – App-Registrierung in Entra ID
1. https://entra.microsoft.com → **App-Registrierungen → Neue Registrierung**
   - Name: `Copilot-FinOps-Collector`
   - Kontotyp: *Nur Konten in diesem Organisationsverzeichnis*
   - Umleitungs-URI: leer
2. Auf der Übersicht **Anwendungs-ID (Client)** und **Verzeichnis-ID (Mandant)** notieren.
3. **Zertifikate & Geheimnisse → Zertifikate → Zertifikat hochladen** → die `.cer`-Datei aus Schritt 2 wählen.
4. **API-Berechtigungen → Berechtigung hinzufügen → Microsoft Graph → Anwendungsberechtigungen**:
   `Organization.Read.All`, `User.Read.All`, `Reports.Read.All` [prüfen]
5. **Administratorzustimmung erteilen** anklicken.
6. Optional (nur Azure „Query API“): Azure-Portal → Abonnement → **Zugriffssteuerung (IAM)** → Rolle **Cost Management Reader** an die App vergeben.

## Schritt 4 – Konfiguration
1. `02_Konfiguration\Konfiguration-CopilotFinOps.html` im Browser öffnen.
2. Mandanten-ID, Anwendungs-ID und Fingerabdruck eintragen.
3. Unter **Datenquellen** zunächst nur **Graph** aktivieren.
4. Ist die Prüfung rechts grün, auf **config.json speichern** klicken und die vorhandene Datei in `02_Konfiguration` ersetzen.
5. Im Lizenzkatalog prüfen, ob `graphSkuPartNumber` zu eurem Tenant passt. Die tatsächlichen Namen zeigt `Get-MgSubscribedSku | Select SkuPartNumber` (Modul Microsoft.Graph) oder die Liste im M365 Admin Center → Abrechnung → Ihre Produkte. Einträge mit `[prüfen]` werden übersprungen.

## Schritt 5 – Erster Lauf
1. Doppelklick auf `03_Collector\Start-Collector.cmd`.
2. Ergebnis prüfen: `06_Daten\out\facts.json` und das Protokoll `collector_*.log`.
3. Typische Fehler:

| Meldung im Protokoll | Ursache / Lösung |
|---|---|
| Platzhalter in 'TenantId' wurde nicht ersetzt | config.json mit der Maske neu speichern |
| Zertifikat … nicht im Zertifikatspeicher gefunden | Skript läuft unter anderem Konto als bei Schritt 2 |
| 403 Forbidden bei Graph | Administratorzustimmung fehlt (Schritt 3.5) |
| SKU '…' im Tenant nicht gefunden | `graphSkuPartNumber` im Katalog anpassen |
| Copilot-Nutzungsbericht liefert keine zuordenbaren UPNs | Namensverschleierung in Berichten aktiv (M365 Admin Center → Einstellungen → Organisationseinstellungen → Berichte). Entscheidung mit DSB/Betriebsrat |

## Schritt 6 – Weitere Quellen schrittweise ergänzen
- **Azure (empfohlen: Export):** Im Azure-Portal unter Cost Management → Exporte einen täglichen Export „Tatsächliche Kosten“ in einen Storage Account anlegen. Die CSV-Dateien regelmäßig nach `06_Daten\import\azure-export` kopieren (z. B. mit AzCopy) und die Spaltennamen in `AzureExportColumnMap` prüfen [prüfen].
- Bei Azure außerdem `AzureExportColumnMap.Currency` auf die tatsächliche Abrechnungswährungsspalte setzen (Standard `BillingCurrencyCode`). Überlappende kumulative Exportstände ersetzen, statt sie gemeinsam abzulegen.
- **Copilot Studio:** Im Power Platform Admin Center den Verbrauch als CSV exportieren und nach `06_Daten\import\ppac` legen. Die Spaltennamen in der Maske eintragen.
- **GitHub:** Den Token als Umgebungsvariable `FINOPS_GITHUB_TOKEN` setzen und die Organisation in der Maske eintragen.

## Schritt 7 – Automatisieren
In der Aufgabenplanung eine tägliche Aufgabe anlegen, z. B. um 05:00 Uhr:
- Programm: `pwsh.exe`
- Argumente: `-NoProfile -File "C:\FinOps\Copilot-FinOps\03_Collector\Collect-CopilotCosts.ps1" -ConfigPath "C:\FinOps\Copilot-FinOps\02_Konfiguration\config.json"`
- Ausführen unter: dem Konto aus Schritt 1/2, „unabhängig von der Benutzeranmeldung“
