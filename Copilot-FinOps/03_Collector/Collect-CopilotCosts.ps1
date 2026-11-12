#Requires -Version 7.2
<#
.SYNOPSIS
  Copilot-FinOps-Collector (Version 1.3): sammelt Lizenz-, Nutzungs- und Verbrauchsdaten und
  schreibt eine normalisierte Faktentabelle (facts.json / facts.csv) für Dashboard und Power BI.
.DESCRIPTION
  - Keine hartkodierten Werte: alles aus config.json + lizenzkatalog.json
  - Relative Pfade in config.json gelten relativ zum Ordner der config.json
  - App-Registrierung mit Zertifikat (kein Secret)
  - Je Datenquelle eine Funktion; Fehler einer Quelle stoppen nicht den Gesamtlauf
  - Datenschutz: Ausgabe ausschließlich aggregiert (Fachbereich/Region); Gruppen kleiner als
    MinGroupSize werden zu "Sonstige" zusammengefasst. Es werden keine UPNs gespeichert.
  Alle Endpunkte/Berechtigungen sind vor Produktivsetzung zu verifizieren [prüfen].
.EXAMPLE
  ./Collect-CopilotCosts.ps1 -ConfigPath ../02_Konfiguration/config.json
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ConfigPath,
  [switch]$ValidateOnly
)
Set-StrictMode -Version 1.0   # erkennt nicht initialisierte Variablen; toleriert leere Arrays/fehlende CSV-Spalten
$ErrorActionPreference = 'Stop'

#region Hilfsfunktionen -------------------------------------------------------
function Write-Log {
  param([string]$Msg, [ValidateSet('INFO','WARN','ERROR')]$Level = 'INFO')
  $line = "{0:u} [{1}] {2}" -f (Get-Date), $Level, $Msg
  Write-Host $line
  if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $line -Encoding utf8 }
}

function Resolve-ConfigPath {
  # Relative Pfade relativ zum Ordner der config.json auflösen
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
  if (-not $IsWindows) { $Path = $Path.Replace('\', '/') }
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return [System.IO.Path]::GetFullPath((Join-Path $script:ConfigDir $Path))
}

function Get-Config {
  param([string]$Path)
  if (-not (Test-Path $Path)) { throw "Konfiguration nicht gefunden: $Path" }
  $script:ConfigDir = Split-Path (Resolve-Path $Path) -Parent
  $c = Get-Content $Path -Raw -Encoding utf8 | ConvertFrom-Json
  if ($null -eq $c -or $c -isnot [pscustomobject]) { throw 'config.json muss ein JSON-Objekt enthalten.' }
  foreach ($k in 'OutputPath','CatalogPath') {
    if (-not $c.PSObject.Properties[$k] -or $c.$k -isnot [string] -or [string]::IsNullOrWhiteSpace($c.$k) -or $c.$k -match '[<>]') { throw "Pflichtparameter '$k' fehlt oder ist ungültig." }
  }
  if (-not $c.PSObject.Properties['EnabledSources'] -or $c.EnabledSources -isnot [array] -or $c.EnabledSources.Count -eq 0) { throw 'EnabledSources muss ein nicht leeres Array sein.' }
  $seenSources = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($source in $c.EnabledSources) {
    if ($source -isnot [string] -or $source -cnotin 'Graph','Azure','PPAC','GitHub') { throw "Unbekannte Datenquelle: $source" }
    if (-not $seenSources.Add($source)) { throw "Doppelte Datenquelle: $source" }
  }
  $azureMode = if ($c.PSObject.Properties['AzureMode']) { $c.AzureMode } else { 'Export' }
  if ($azureMode -cnotin 'Export','Query') { throw 'AzureMode muss Export oder Query sein.' }
  $guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  if ($c.EnabledSources -contains 'Graph' -or ($c.EnabledSources -contains 'Azure' -and $azureMode -eq 'Query')) {
    foreach ($k in 'TenantId','ClientId') {
      if (-not $c.PSObject.Properties[$k] -or $c.$k -isnot [string] -or $c.$k -notmatch $guidPattern) { throw "$k muss eine vollständige GUID sein. Einrichten-CopilotFinOps.ps1 oder die Konfigurationsmaske verwenden." }
    }
    if (-not $c.PSObject.Properties['CertificateThumbprint'] -or $c.CertificateThumbprint -isnot [string]) { throw 'CertificateThumbprint fehlt.' }
    $c.CertificateThumbprint = ($c.CertificateThumbprint -replace '[\s\u200e\u200f:]', '').ToUpperInvariant()
    if ($c.CertificateThumbprint -notmatch '^[0-9A-F]{40}$') { throw 'CertificateThumbprint muss 40 Hexadezimalzeichen enthalten.' }
  }
  if ($c.EnabledSources -contains 'Graph' -and (-not $c.PSObject.Properties['DepartmentAttribute'] -or $c.DepartmentAttribute -isnot [string] -or $c.DepartmentAttribute -notmatch '^[A-Za-z][A-Za-z0-9_]{0,127}$')) { throw 'DepartmentAttribute fehlt oder enthält ungültige Zeichen.' }
  if ($c.EnabledSources -contains 'Azure') {
    if ($azureMode -eq 'Query') {
      if (-not $c.PSObject.Properties['AzureScopes'] -or $c.AzureScopes -isnot [array] -or -not $c.AzureScopes.Count) { throw 'Azure Query benötigt mindestens einen AzureScopes-Eintrag: /subscriptions/<GUID>.' }
      $seenScopes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
      foreach ($scope in $c.AzureScopes) {
        if ($scope -isnot [string] -or $scope -notmatch ('^/subscriptions/' + $guidPattern.TrimStart('^'))) { throw 'Azure-Scope muss /subscriptions/<GUID> entsprechen.' }
        if (-not $seenScopes.Add($scope)) { throw "Doppelter Azure-Scope: $scope" }
      }
      if (-not $c.PSObject.Properties['CostCenterTag'] -or $c.CostCenterTag -isnot [string] -or [string]::IsNullOrWhiteSpace($c.CostCenterTag) -or $c.CostCenterTag -match '[<>]|\[prüfen\]') { throw 'Azure Query: CostCenterTag fehlt oder enthält einen Platzhalter.' }
      $date = [datetime]::MinValue
      $dateText = if ($c.PSObject.Properties['CostApiVersion'] -and $c.CostApiVersion -is [string] -and $c.CostApiVersion -cmatch '^(\d{4}-\d{2}-\d{2})(-preview)?$') { $Matches[1] } else { $null }
      if (-not $dateText -or -not [datetime]::TryParseExact($dateText, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)) { throw 'CostApiVersion muss ein gültiges Datum JJJJ-MM-TT (optional -preview) sein.' }
    } elseif (-not $c.PSObject.Properties['AzureExportFolder'] -or $c.AzureExportFolder -isnot [string] -or [string]::IsNullOrWhiteSpace($c.AzureExportFolder)) { throw 'Azure Export: AzureExportFolder fehlt.' }
  }
  if ($c.EnabledSources -contains 'PPAC') {
    foreach ($k in 'PpacImportFolder','PpacProduktId') {
      if (-not $c.PSObject.Properties[$k] -or $c.$k -isnot [string] -or [string]::IsNullOrWhiteSpace($c.$k) -or $c.$k -match '[<>]') { throw "PPAC: '$k' fehlt oder ist ungültig." }
    }
    if (-not $c.PSObject.Properties['PpacColumnMap'] -or $c.PpacColumnMap -isnot [pscustomobject]) { throw 'PPAC: PpacColumnMap muss ein Objekt sein.' }
    foreach ($k in 'Date','Environment','Agent','Credits') {
      if (-not $c.PpacColumnMap.PSObject.Properties[$k] -or $c.PpacColumnMap.$k -isnot [string] -or [string]::IsNullOrWhiteSpace($c.PpacColumnMap.$k)) { throw "PPAC: PpacColumnMap.$k fehlt." }
    }
  }
  if ($c.EnabledSources -contains 'GitHub' -and (-not $c.PSObject.Properties['GitHubOrg'] -or $c.GitHubOrg -isnot [string] -or $c.GitHubOrg -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$')) { throw 'GitHubOrg fehlt oder ist ungültig.' }
  $bounds = @{ MinGroupSize = @(1,50); InactiveDays = @(7,180); MonthsBack = @(1,36) }
  foreach ($k in $bounds.Keys) {
    if ($c.PSObject.Properties[$k] -and (($c.$k -isnot [long] -and $c.$k -isnot [int]) -or $c.$k -lt $bounds[$k][0] -or $c.$k -gt $bounds[$k][1])) { throw "$k muss eine ganze Zahl zwischen $($bounds[$k][0]) und $($bounds[$k][1]) sein." }
  }
  if ($c.PSObject.Properties['CsvDelimiter'] -and $c.CsvDelimiter -cnotin ';',',') { throw 'CsvDelimiter muss Semikolon oder Komma sein.' }
  foreach ($k in 'OutputPath','CatalogPath','PpacImportFolder','AzureExportFolder') {
    if ($c.PSObject.Properties[$k]) {
      if ($c.$k -isnot [string]) { throw "$k muss Text sein." }
      $c.$k = Resolve-ConfigPath $c.$k
    }
  }
  return $c
}

function Get-Setting {
  # Optionale Einstellung mit Standardwert lesen
  param([string]$Name, $Default)
  if ($cfg.PSObject.Properties[$Name] -and $null -ne $cfg.$Name -and "$($cfg.$Name)" -ne '') { return $cfg.$Name }
  return $Default
}

function Get-Catalog {
  param([string]$Path)
  if (-not (Test-Path $Path)) { throw "Lizenzkatalog nicht gefunden: $Path" }
  $cat = Get-Content $Path -Raw -Encoding utf8 | ConvertFrom-Json
  if (-not $cat.PSObject.Properties['produkte'] -or $cat.produkte -isnot [array] -or -not $cat.produkte.Count) { throw 'Lizenzkatalog enthält kein nicht leeres Produkte-Array.' }
  $active = @($cat.produkte | Where-Object { -not $_.PSObject.Properties['aktiv'] -or $_.aktiv -ne $false })
  $ids = @{}
  foreach ($p in $cat.produkte) {
    if ([string]::IsNullOrWhiteSpace($p.produktId)) { throw 'Produkt-ID fehlt im Lizenzkatalog.' }
    if ($ids.ContainsKey($p.produktId)) { throw "Doppelte Produkt-ID: $($p.produktId)" }
    $ids[$p.produktId] = $true
  }
  return $active
}

function Test-KeyValue {
  # Zuordnungsschlüssel nur verwenden, wenn gesetzt und kein Platzhalter
  param($Value)
  return ($Value -and "$Value" -notmatch '\[prüfen\]|[<>]')
}

function Get-MapValue {
  param($Product, [string]$Key)
  $z = $Product.zuordnungsschluessel
  if ($z -and $z.PSObject.Properties[$Key] -and (Test-KeyValue $z.$Key)) { return $z.$Key }
  return $null
}

function Find-AzureProduct {
  # Deklaratives Mapping Azure-Zeile -> genau ein Katalogprodukt; Konflikte offenlegen.
  param([string]$MeterCategory, [string]$MeterName, [string]$ServiceName)
  $matches = @()
  foreach ($p in $catalog | Where-Object datenquelle -eq 'AzureCostManagement') {
    $mc = Get-MapValue $p 'azureMeterCategory'
    $sn = Get-MapValue $p 'azureServiceName'
    $mn = Get-MapValue $p 'azureMeterNameContains'
    if (($mc -and $MeterCategory -eq $mc) -or ($sn -and $ServiceName -eq $sn) -or ($mn -and $MeterName.IndexOf([string]$mn,[StringComparison]::OrdinalIgnoreCase) -ge 0)) { $matches += $p }
  }
  if ($matches.Count -gt 1) { throw "Mehrdeutige Azure-Zuordnung: $($matches.produktId -join ', '). Katalogschlüssel präzisieren." }
  if ($matches.Count) { return $matches[0] }
  return $null
}

function Connect-Tenant {
  if (-not $IsWindows) { throw 'Zertifikatsanmeldung über den Windows-Zertifikatspeicher benötigt Windows. CSV-Importe funktionieren plattformübergreifend.' }
  if (-not (Get-Module -ListAvailable Az.Accounts)) { throw "Modul Az.Accounts fehlt: Install-Module Az.Accounts -Scope CurrentUser" }
  Import-Module Az.Accounts -ErrorAction Stop
  $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
          Where-Object Thumbprint -eq $cfg.CertificateThumbprint | Select-Object -First 1
  if (-not $cert) { throw "Zertifikat $($cfg.CertificateThumbprint) nicht im Zertifikatspeicher dieses Kontos gefunden." }
  if (-not $cert.HasPrivateKey) { throw "Zertifikat gefunden, aber ohne privaten Schlüssel." }
  if ($cert.NotAfter -le (Get-Date) -or $cert.NotBefore -gt (Get-Date)) { throw 'Zertifikat ist noch nicht oder nicht mehr gültig.' }
  Connect-AzAccount -ServicePrincipal -Tenant $cfg.TenantId -ApplicationId $cfg.ClientId `
    -CertificateThumbprint $cfg.CertificateThumbprint -Scope Process -SkipContextPopulation -AllowNoSubscriptions -WarningAction SilentlyContinue | Out-Null
  Write-Log "Anmeldung als App $($cfg.ClientId) erfolgreich"
}

function Get-AccessToken {
  param([string]$Resource)
  $t = Get-AzAccessToken -ResourceUrl $Resource -WarningAction SilentlyContinue
  if ($t.Token -is [securestring]) { return [System.Net.NetworkCredential]::new('', $t.Token).Password }
  return $t.Token
}

function Invoke-Api {
  param([string]$Uri, [string]$Token, [string]$Method = 'GET', $Body, [hashtable]$ExtraHeaders = @{}, [int]$MaxRetry = 4)
  $target = [uri]$Uri
  if ($target.Scheme -ne 'https' -or $target.Host -notin 'graph.microsoft.com','management.azure.com','api.github.com') { throw 'Nicht erlaubtes API-Ziel.' }
  $h = @{ Authorization = "Bearer $Token" } + $ExtraHeaders
  for ($i = 1; $i -le $MaxRetry; $i++) {
    try {
      $p = @{ Uri = $Uri; Headers = $h; Method = $Method; TimeoutSec = 120; MaximumRedirection = 0 }
      if ($Body) { $p.Body = ($Body | ConvertTo-Json -Depth 20); $p.ContentType = 'application/json' }
      return Invoke-RestMethod @p
    } catch {
      $code = $null
      if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
      if ($code -in 429,500,502,503,504 -and $i -lt $MaxRetry) {
        $wait = [math]::Pow(2, $i) * 5
        $response = $_.Exception.Response
        if ($response -and $response.Headers -and $response.Headers.RetryAfter) {
          $retry = $response.Headers.RetryAfter
          if ($retry.Delta) { $wait = [math]::Max($wait, $retry.Delta.TotalSeconds) }
          elseif ($retry.Date) { $wait = [math]::Max($wait, ($retry.Date.UtcDateTime - [datetime]::UtcNow).TotalSeconds) }
        }
        Write-Log "HTTP $code – erneuter Versuch in $wait s ($Uri)" 'WARN'
        Start-Sleep -Seconds $wait
      } else { throw }
    }
  }
}

function Invoke-GraphPaged {
  param([string]$Uri, [string]$Token)
  $all = [System.Collections.Generic.List[object]]::new()
  $seen = [System.Collections.Generic.HashSet[string]]::new()
  while ($Uri) {
    if (([uri]$Uri).Host -ne 'graph.microsoft.com' -or -not $seen.Add($Uri)) { throw 'Ungültiger oder zyklischer Graph-Folgeseitenlink.' }
    $r = Invoke-Api -Uri $Uri -Token $Token
    if (-not $r.PSObject.Properties['value'] -or $r.value -isnot [array]) { throw 'Graph-Antwort enthält kein value-Array.' }
    foreach ($v in $r.value) { $all.Add($v) }
    $Uri = if ($r.PSObject.Properties['@odata.nextLink']) { $r.'@odata.nextLink' } else { $null }
  }
  return $all
}

function New-Fact {
  param($Monat, $ProduktId, $Fachbereich, $Region, $Menge, $KostenIst = $null, $Agent = '', $Umgebung = '',
        $Quelle, $Zugewiesen = 0, $Aktiv = $null, $Unlizenziert = 0, $Waehrung = $null)
  if ([string]$Monat -notmatch '^\d{4}-(0[1-9]|1[0-2])$' -or [string]::IsNullOrWhiteSpace($ProduktId)) { throw 'Ungültiger Faktenschlüssel.' }
  if (-not [double]::IsFinite([double]$Menge) -or ($null -ne $KostenIst -and -not [double]::IsFinite([double]$KostenIst))) { throw 'Nicht endlicher Mengen- oder Kostenwert.' }
  [pscustomobject]@{
    monat = $Monat; produktId = $ProduktId
    fachbereich = $(if ($Fachbereich) { $Fachbereich } else { 'Nicht zugeordnet' })
    region      = $(if ($Region) { $Region } else { 'Unbekannt' })
    menge = [double]$Menge; kostenIst = $(if ($null -ne $KostenIst -and "$KostenIst" -ne '') { [double]$KostenIst } else { $null })
    agent = $Agent; umgebung = $Umgebung
    zugewiesen = [int]$Zugewiesen; aktiv = $(if ($null -eq $Aktiv) { $null } else { [int]$Aktiv }); unlizenziert = [int]$Unlizenziert; quelle = $Quelle; waehrung = $Waehrung
  }
}

function Get-UserDepartment {
  # Fachbereich aus konfiguriertem Entra-Attribut (department, companyName, officeLocation …)
  param($User)
  $a = $cfg.DepartmentAttribute
  if ($User.PSObject.Properties[$a] -and $User.$a) { return $User.$a }
  return 'Nicht zugeordnet'
}
#endregion

function Convert-ImportDate {
  param([string]$Value, [switch]$AllowUsDate)
  $formats = @('yyyy-MM-dd','yyyyMMdd','yyyy-MM-ddTHH:mm:ss','yyyy-MM-ddTHH:mm:ssZ','yyyy-MM-ddTHH:mm:ss.fffZ','dd.MM.yyyy','d.M.yyyy')
  if ($AllowUsDate) { $formats += @('M/d/yyyy','MM/dd/yyyy') }
  $date = [datetime]::MinValue
  if (-not [datetime]::TryParseExact($Value.Trim(), [string[]]$formats, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$date)) {
    throw 'Ungültiges oder mehrdeutiges Importdatum. ISO yyyy-MM-dd verwenden.'
  }
  return $date
}

function Convert-ImportNumber {
  param([string]$Value, [string]$Column, [switch]$NonNegative)
  $text = $Value.Trim()
  # Decimal dot or comma is accepted; grouping separators are rejected as ambiguous.
  if ($text -notmatch '^[+-]?(?:\d+(?:[.,]\d+)?|[.,]\d+)$') { throw "Ungültiger Zahlenwert in Spalte '$Column'." }
  $n = [double]::Parse($text.Replace(',', '.'), [cultureinfo]::InvariantCulture)
  if (-not [double]::IsFinite($n) -or ($NonNegative -and $n -lt 0)) { throw "Ungültiger Zahlenwert in Spalte '$Column'." }
  return $n
}

#region Quelle 1: Microsoft Graph – Lizenzen, User, Copilot-Nutzung -----------
# Berechtigungen (Application): LicenseAssignment.Read.All, User.Read.All, Reports.Read.All [prüfen]
function Get-GraphLicenseFacts {
  $tok   = Get-AccessToken 'https://graph.microsoft.com'
  $skus  = @(Invoke-GraphPaged 'https://graph.microsoft.com/v1.0/subscribedSkus' $tok)
  $attr  = $cfg.DepartmentAttribute
  $users = @(Invoke-GraphPaged "https://graph.microsoft.com/v1.0/users?`$select=id,userPrincipalName,$attr,usageLocation,assignedLicenses&`$top=999" $tok)
  Write-Log "Graph: $($skus.Count) SKUs, $($users.Count) Benutzer gelesen"

  # Copilot-Nutzungsbericht (letzte Aktivität je User); Endpunkt ggf. nur /beta [prüfen].
  # Bei aktivierter Namensverschleierung im M365 Admin Center sind UPNs anonymisiert -> keine Zuordnung möglich.
  $usage = @{}
  $usageAvailable = $false
  $inactiveDays = [int](Get-Setting 'InactiveDays' 30)
  $reportDays = @(7,30,90,180 | Where-Object { $_ -ge $inactiveDays })[0]
  try {
    $r = Invoke-GraphPaged "https://graph.microsoft.com/beta/reports/getMicrosoft365CopilotUsageUserDetail(period='D$reportDays')?`$format=application/json" $tok
    foreach ($u in $r) {
      $dates = @()
      foreach ($field in 'lastActivityDate','microsoft365CopilotLastActivityDate','copilotChatLastActivityDate','microsoftTeamsCopilotLastActivityDate','wordCopilotLastActivityDate','excelCopilotLastActivityDate','powerPointCopilotLastActivityDate','outlookCopilotLastActivityDate','oneNoteCopilotLastActivityDate','loopCopilotLastActivityDate') {
        if ($u.PSObject.Properties[$field] -and $u.$field) {
          $date = [datetime]::MinValue
          if ([datetime]::TryParse([string]$u.$field, [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$date)) { $dates += $date }
        }
      }
      if ($u.userPrincipalName -and $dates.Count) { $usage[$u.userPrincipalName] = ($dates | Sort-Object -Descending | Select-Object -First 1) }
    }
    $usageAvailable = $usage.Count -gt 0 -and @($users | Where-Object { $usage.ContainsKey($_.userPrincipalName) }).Count -gt 0
    if ($usage.Count -and -not ($users.userPrincipalName | Where-Object { $usage.ContainsKey($_) } | Select-Object -First 1)) {
      Write-Log 'Copilot-Nutzungsbericht liefert keine zuordenbaren UPNs (Verschleierung aktiv?) – Auslastung nicht berechenbar' 'WARN'
    }
  } catch { Write-Log "Copilot-Nutzungsbericht nicht verfügbar: $($_.Exception.Message)" 'WARN' }

  $month  = Get-Date -Format 'yyyy-MM'
  $cutoff = (Get-Date).AddDays(-[int](Get-Setting 'InactiveDays' 30))
  $facts  = [System.Collections.Generic.List[object]]::new()

  foreach ($p in $catalog | Where-Object datenquelle -eq 'Graph') {
    $partNo = Get-MapValue $p 'graphSkuPartNumber'
    if (-not $partNo) { continue }
    $sku = $skus | Where-Object skuPartNumber -eq $partNo | Select-Object -First 1
    if (-not $sku) { Write-Log "SKU '$partNo' ($($p.produktId)) im Tenant nicht gefunden" 'WARN'; continue }
    $lic = @($users | Where-Object { $_.assignedLicenses.skuId -contains $sku.skuId })
    foreach ($g in $lic | Group-Object { Get-UserDepartment $_ }, { $_.usageLocation }) {
      $active = if ($usageAvailable) { @($g.Group | Where-Object { $usage.ContainsKey($_.userPrincipalName) -and $usage[$_.userPrincipalName] -ge $cutoff }).Count } else { $null }
      $facts.Add((New-Fact -Monat $month -ProduktId $p.produktId -Fachbereich (Get-UserDepartment $g.Group[0]) `
        -Region $g.Group[0].usageLocation -Menge $g.Count -Zugewiesen $g.Count -Aktiv $active -Quelle 'Graph'))
    }
    # Gekaufte, aber nicht zugewiesene Lizenzen
    $free = [int]$sku.prepaidUnits.enabled - [int]$sku.consumedUnits
    if ($free -gt 0) {
      $facts.Add((New-Fact -Monat $month -ProduktId $p.produktId -Fachbereich 'Pool (nicht zugewiesen)' -Region 'n/a' -Menge $free -Quelle 'Graph'))
    }
  }

  # Unlizenzierte Copilot-Chat-Nutzer (Aktivität ohne Premium-Lizenz)
  $ids     = Get-Setting 'ProduktIds' $null
  $premId  = if ($ids -and $ids.PSObject.Properties['PremiumLizenz']) { $ids.PremiumLizenz } else { $null }
  $chatId  = if ($ids -and $ids.PSObject.Properties['ChatBasis'])     { $ids.ChatBasis }     else { $null }
  if ($chatId -and $usageAvailable) {
    $prem    = $catalog | Where-Object produktId -eq $premId | Select-Object -First 1
    $premNo  = if ($prem) { Get-MapValue $prem 'graphSkuPartNumber' }
    $premSku = if ($premNo) { ($skus | Where-Object skuPartNumber -eq $premNo | Select-Object -First 1).skuId }
    if (-not $premSku) { Write-Log 'Premium-SKU nicht zugeordnet: unlizenzierte Nutzer werden nicht geschätzt.' 'WARN'; return $facts }
    $unl = @($users | Where-Object { $usage.ContainsKey($_.userPrincipalName) -and $usage[$_.userPrincipalName] -ge $cutoff -and -not ($premSku -and $_.assignedLicenses.skuId -contains $premSku) })
    foreach ($g in $unl | Group-Object { Get-UserDepartment $_ }, { $_.usageLocation }) {
      $facts.Add((New-Fact -Monat $month -ProduktId $chatId -Fachbereich (Get-UserDepartment $g.Group[0]) -Region $g.Group[0].usageLocation `
        -Menge $g.Count -Unlizenziert $g.Count -Quelle 'Graph'))
    }
  }
  return $facts
}
#endregion

#region Quelle 2a: Azure Cost Management – Export-Dateien (empfohlen) ----------
# Cost Management Export (täglich, "Actual cost") in Storage Account einrichten und Dateien
# in AzureExportFolder synchronisieren (z. B. AzCopy). Spaltennamen je Exportversion [prüfen].
function Import-AzureExportFacts {
  $folder = Get-Setting 'AzureExportFolder' $null
  if (-not $folder -or -not (Test-Path $folder -PathType Container)) { throw 'Azure-Exportordner fehlt.' }
  $m = $cfg.AzureExportColumnMap
  foreach ($key in 'Date','MeterCategory','MeterName','ServiceName','Location','Tags','Cost','Quantity') {
    if (-not $m.$key -or $m.$key -match '[<>]') { throw "AzureExportColumnMap.$key fehlt oder enthält einen Platzhalter." }
  }
  $tag = Get-Setting 'CostCenterTag' ''
  $from = (Get-Date -Day 1).Date.AddMonths(-[int](Get-Setting 'MonthsBack' 12))
  $agg = @{}
  foreach ($f in Get-ChildItem $folder -Filter *.csv -Recurse) {
    $rows = @(Import-Csv $f.FullName -Encoding utf8)
    if (-not $rows.Count) { continue }
    $fehlend = @($m.PSObject.Properties | Where-Object { $_.Name -ne 'Currency' } | ForEach-Object Value | Where-Object { -not $rows[0].PSObject.Properties[$_] })
    if ($fehlend) { throw "$($f.Name): Spalten fehlen ($($fehlend -join ', ')) – AzureExportColumnMap prüfen" }
    $currencyColumn = if ($m.PSObject.Properties['Currency'] -and $m.Currency) { $m.Currency } else { @('BillingCurrencyCode','BillingCurrency','Currency') | Where-Object { $rows[0].PSObject.Properties[$_] } | Select-Object -First 1 }
    if (-not $currencyColumn -or -not $rows[0].PSObject.Properties[$currencyColumn]) { throw "$($f.Name): Währungsspalte fehlt – AzureExportColumnMap.Currency konfigurieren." }
    foreach ($r in $rows) {
      $p = Find-AzureProduct -MeterCategory $r.($m.MeterCategory) -MeterName $r.($m.MeterName) -ServiceName $r.($m.ServiceName)
      if (-not $p) { continue }
      $d = Convert-ImportDate $r.($m.Date) -AllowUsDate
      if ($d -lt $from -or $d.Date -gt (Get-Date).Date) { continue }
      # Tags liegen im Export als JSON-Fragment vor, z. B. "Kostenstelle": "Vertrieb"
      $fb = 'Nicht getaggt'
      if ($tag -and -not [string]::IsNullOrWhiteSpace($r.($m.Tags))) {
        $tagsText = ([string]$r.($m.Tags)).Trim()
        if (-not $tagsText.StartsWith('{')) { $tagsText = '{' + $tagsText + '}' }
        try { $tagsObject = ConvertFrom-Json $tagsText -AsHashtable } catch { throw "$($f.Name): Ungültiges Tags-JSON." }
        if ($tagsObject -is [hashtable] -and $tagsObject.ContainsKey($tag) -and $tagsObject[$tag]) { $fb = [string]$tagsObject[$tag] }
      }
      $currency = ([string]$r.$currencyColumn).Trim().ToUpperInvariant()
      if ($currency -notmatch '^[A-Z]{3}$') { throw "$($f.Name): Ungültige Währung." }
      $key = ConvertTo-Json -InputObject @($d.ToString('yyyy-MM'), $p.produktId, $fb, $r.($m.Location),$currency) -Compress
      if (-not $agg[$key]) { $agg[$key] = @{ menge = 0.0; kosten = 0.0 } }
      $agg[$key].menge  += (Convert-ImportNumber $r.($m.Quantity) 'Quantity')
      $agg[$key].kosten += (Convert-ImportNumber $r.($m.Cost) 'Cost')
    }
  }
  foreach ($k in $agg.Keys) {
    $s = @($k | ConvertFrom-Json)
    New-Fact -Monat $s[0] -ProduktId $s[1] -Fachbereich $s[2] -Region $s[3] -Menge $agg[$k].menge -KostenIst $agg[$k].kosten -Quelle 'Azure-Export' -Waehrung $s[4]
  }
}
#endregion

#region Quelle 2b: Azure Cost Management – Query API (Alternative) --------------
# Rolle: Cost Management Reader. Die Query API erlaubt max. 2 Gruppierungen [prüfen]:
# daher Gruppierung nach Meter + Kostenstellen-Tag; Mapping im Katalog nur über azureMeterNameContains.
function Get-AzureQueryFacts {
  $tok = Get-AccessToken 'https://management.azure.com/'
  $from = (Get-Date -Day 1).Date.AddMonths(-[int](Get-Setting 'MonthsBack' 12)).ToString('yyyy-MM-dd')
  $to   = (Get-Date).ToString('yyyy-MM-dd')
  $ver  = Get-Setting 'CostApiVersion' $null
  if (-not $ver -or $ver -notmatch '^\d{4}-\d{2}-\d{2}(-preview)?$') { throw "CostApiVersion ungültig: '$ver'" }
  $facts = [System.Collections.Generic.List[object]]::new()
  foreach ($scope in @($cfg.AzureScopes)) {
    if ($scope -notmatch '^/subscriptions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { throw 'Azure-Scope muss /subscriptions/<GUID> entsprechen.' }
    if (-not (Test-KeyValue $cfg.CostCenterTag)) { throw 'CostCenterTag fehlt oder enthält einen Platzhalter.' }
    $body = @{ type = 'ActualCost'; timeframe = 'Custom'; timePeriod = @{ from = $from; to = $to }
      dataset = @{ granularity = 'Monthly'
        aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' }; totalQty = @{ name = 'UsageQuantity'; function = 'Sum' } }
        grouping = @( @{ type = 'Dimension'; name = 'Meter' }, @{ type = 'TagKey'; name = $cfg.CostCenterTag } ) } }
    $uri = "https://management.azure.com$scope/providers/Microsoft.CostManagement/query?api-version=$ver"
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    while ($uri) {
      if (([uri]$uri).Host -ne 'management.azure.com' -or -not $seen.Add($uri)) { throw 'Ungültiger Azure-Folgeseitenlink.' }
      $r = Invoke-Api -Uri $uri -Token $tok -Method POST -Body $body
      if (-not $r.PSObject.Properties['properties'] -or -not $r.properties -or -not $r.properties.PSObject.Properties['columns'] -or $r.properties.columns -isnot [array] -or -not $r.properties.PSObject.Properties['rows'] -or $r.properties.rows -isnot [array]) { throw 'Azure Query: Antwort enthält keine vollständigen columns/rows-Arrays.' }
      $cols = @($r.properties.columns.name)
      $seenColumns = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
      foreach ($column in $cols) { if ($column -isnot [string] -or -not $seenColumns.Add($column)) { throw 'Azure Query: ungültige oder doppelte Spaltennamen.' } }
      foreach ($column in 'Meter','Cost','UsageQuantity','Currency') { if ($column -notin $cols) { throw "Azure Query: Pflichtspalte '$column' fehlt." } }
      if ('BillingMonth' -notin $cols -and 'UsageDate' -notin $cols) { throw 'Azure Query: Monatsspalte fehlt.' }
      $tagColumn = if ($cfg.CostCenterTag -in $cols) { $cfg.CostCenterTag } elseif ('TagValue' -in $cols) { 'TagValue' } else { throw 'Azure Query: Spalte für das konfigurierte Kostenstellen-Tag fehlt.' }
      foreach ($row in $r.properties.rows) {
        if ($row -isnot [array] -or $row.Count -ne $cols.Count) { throw 'Azure Query: Zeile passt nicht zu den Spalten.' }
        $o = @{}; for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
        $p = Find-AzureProduct -MeterCategory '' -MeterName $o['Meter'] -ServiceName ''
        if (-not $p) { continue }
        $dateValue = if ($o.ContainsKey('BillingMonth')) { $o['BillingMonth'] } elseif ($o.ContainsKey('UsageDate')) { $o['UsageDate'] } else { throw 'Azure Query: Monatsspalte fehlt.' }
        $monat = (Convert-ImportDate ([string]$dateValue) -AllowUsDate).ToString('yyyy-MM')
        if (-not $o.ContainsKey('Currency') -or $o['Currency'] -notmatch '^[A-Z]{3}$') { throw 'Azure Query: Währung fehlt oder ist ungültig.' }
        if ($null -eq $o['Cost'] -or $null -eq $o['UsageQuantity']) { throw 'Azure Query: Kosten oder Verbrauch fehlen; keine Nullkosten ableiten.' }
        $quantity = Convert-ImportNumber ([string]$o['UsageQuantity']) 'UsageQuantity'
        $cost = Convert-ImportNumber ([string]$o['Cost']) 'Cost'
        $fb = if ($o[$tagColumn]) { $o[$tagColumn] } else { 'Nicht getaggt' }
        $facts.Add((New-Fact -Monat $monat -ProduktId $p.produktId -Fachbereich $fb -Region 'Azure' `
          -Menge $quantity -KostenIst $cost -Quelle 'Azure-Query' -Waehrung $o['Currency']))
      }
      $uri = if ($r.properties.PSObject.Properties['nextLink']) { $r.properties.nextLink } else { $null }
    }
  }
  return $facts
}
#endregion

#region Quelle 3: Power Platform – Copilot-Studio-Credits (CSV-Import) --------
# Für Verbrauch je Agent/Umgebung ist keine stabile öffentliche API bekannt [prüfen].
# Daher manueller CSV-Export aus dem Power Platform Admin Center in PpacImportFolder.
function Import-PpacCreditFacts {
  $folder = Get-Setting 'PpacImportFolder' $null
  if (-not $folder -or -not (Test-Path $folder -PathType Container)) { throw 'PPAC-Importordner fehlt.' }
  if (-not ($catalog | Where-Object produktId -eq $cfg.PpacProduktId)) { throw 'PpacProduktId ist im aktiven Katalog nicht vorhanden.' }
  $map = $cfg.PpacColumnMap
  foreach ($k in 'Date','Environment','Agent','Credits') {
    if (-not $map.$k -or $map.$k -match '[<>]') { throw "PpacColumnMap.$k ist nicht gesetzt" }
  }
  $envMap = @{}
  if ($cfg.PSObject.Properties['EnvironmentToDepartment']) {
    foreach ($e in $cfg.EnvironmentToDepartment.PSObject.Properties) { if ($e.Name -notmatch '[<>]') { $envMap[$e.Name] = $e.Value } }
  }
  $delim = Get-Setting 'CsvDelimiter' ';'
  $from = (Get-Date -Day 1).Date.AddMonths(-[int](Get-Setting 'MonthsBack' 12))
  $agg = @{}
  foreach ($f in Get-ChildItem $folder -Filter *.csv) {
    $rows = @(Import-Csv $f.FullName -Delimiter $delim -Encoding utf8)
    foreach ($name in @($map.Date,$map.Environment,$map.Agent,$map.Credits)) {
      if ($rows.Count -and -not $rows[0].PSObject.Properties[$name]) { throw "$($f.Name): Spalte '$name' nicht gefunden – Trennzeichen/Spaltennamen prüfen" }
    }
    foreach ($r in $rows) {
      $d = Convert-ImportDate $r.($map.Date)
      if ($d -lt $from -or $d.Date -gt (Get-Date).Date) { continue }
      $env = $r.($map.Environment)
      $fb  = if ($envMap.ContainsKey($env)) { $envMap[$env] } else { 'Nicht zugeordnet' }
      $key = ConvertTo-Json -InputObject @($d.ToString('yyyy-MM'), $fb, $env, $r.($map.Agent)) -Compress
      $agg[$key] = ($agg[$key] ?? 0) + (Convert-ImportNumber $r.($map.Credits) 'Credits' -NonNegative)
    }
  }
  foreach ($k in $agg.Keys) {
    $s = @($k | ConvertFrom-Json)
    New-Fact -Monat $s[0] -ProduktId $cfg.PpacProduktId -Fachbereich $s[1] -Region 'n/a' -Menge $agg[$k] -Umgebung $s[2] -Agent $s[3] -Quelle 'PPAC-CSV'
  }
}
#endregion

#region Quelle 4: GitHub – Copilot Seats & Premium Requests -------------------
# Token (Fine-grained PAT/GitHub App, Billing-Lesezugriff) als Umgebungsvariable FINOPS_GITHUB_TOKEN. Endpunkte [prüfen].
function Get-GitHubFacts {
  $org = Get-Setting 'GitHubOrg' ''
  if ($org -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,38}$') { throw 'GitHubOrg fehlt oder ist ungültig.' }
  $tok = $env:FINOPS_GITHUB_TOKEN
  if (-not $tok) { throw 'Umgebungsvariable FINOPS_GITHUB_TOKEN fehlt.' }
  $hdr   = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = (Get-Setting 'GitHubApiVersion' '2022-11-28') }
  $fbDef = Get-Setting 'GitHubDefaultDepartment' 'IT'
  $seatId = $cfg.ProduktIds.GitHubSeats
  $facts = [System.Collections.Generic.List[object]]::new()
  $month = Get-Date -Format 'yyyy-MM'
  $cut   = (Get-Date).AddDays(-[int](Get-Setting 'InactiveDays' 30))

  $seats = [System.Collections.Generic.List[object]]::new(); $page = 1; $total = 0
  do {
    $r = Invoke-Api -Uri "https://api.github.com/orgs/$org/copilot/billing/seats?per_page=100&page=$page" -Token $tok -ExtraHeaders $hdr
    $total = $r.total_seats; foreach ($s in $r.seats) { $seats.Add($s) }; $page++
  } while ($seats.Count -lt $total -and $r.seats.Count -gt 0)
  if ($seats.Count -ne $total) { throw 'GitHub Seats: unvollständige Antwort.' }
  $act = @($seats | Where-Object { $_.last_activity_at -and [datetime]$_.last_activity_at -ge $cut }).Count
  if ($seatId) {
    $facts.Add((New-Fact -Monat $month -ProduktId $seatId -Fachbereich $fbDef -Region 'Global' -Menge $total -Zugewiesen $total -Aktiv $act -Quelle 'GitHub'))
  }
  $billingProducts = @($catalog | Where-Object {
    $_.datenquelle -eq 'GitHubAPI' -and $_.abrechnungsart -eq 'Verbrauch' -and (Get-MapValue $_ 'githubSku')
  })
  if (-not $billingProducts.Count) {
    Write-Log 'GitHub-Billing nicht aktiviert: kein Verbrauchsprodukt mit gepflegtem githubSku.'
  } else {
    # Billing is required once it is mapped; do not silently publish incomplete costs.
    # Endpoint/query schema verified against @octokit/openapi-types 29.0.1:
    # org is a string; year/month/day supported; no pagination parameters.
    $from = (Get-Date -Day 1).Date.AddMonths(-[int](Get-Setting 'MonthsBack' 12))
    $thisMonth = (Get-Date -Day 1).Date
    $billing = @{}
    for ($period = $from; $period -le $thisMonth; $period = $period.AddMonths(1)) {
      $uri = "https://api.github.com/organizations/$org/settings/billing/usage?year=$($period.Year)&month=$($period.Month)"
      $u = Invoke-Api -Uri $uri -Token $tok -ExtraHeaders $hdr
      if (-not $u.PSObject.Properties['usageItems']) { throw 'GitHub Billing: usageItems fehlt in der Antwort.' }
      foreach ($i in @($u.usageItems) | Where-Object { $_.product -eq 'copilot' }) {
        $matches = @($billingProducts | Where-Object { (Get-MapValue $_ 'githubSku') -eq $i.sku })
        if ($matches.Count -gt 1) { throw 'GitHub Billing: Mehrdeutige SKU-Zuordnung.' }
        if ($matches.Count -eq 1) {
          foreach ($field in 'date','quantity','netAmount') {
            if (-not $i.PSObject.Properties[$field] -or $null -eq $i.$field) { throw "GitHub Billing: Pflichtfeld '$field' fehlt." }
          }
          $date = [datetime]::Parse([string]$i.date, [cultureinfo]::InvariantCulture)
          if ($date.ToString('yyyy-MM') -ne $period.ToString('yyyy-MM') -or $date.Date -gt (Get-Date).Date) { continue }
          $key = ConvertTo-Json -InputObject @($date.ToString('yyyy-MM'),$matches[0].produktId) -Compress
          if (-not $billing.ContainsKey($key)) { $billing[$key] = New-Fact -Monat $date.ToString('yyyy-MM') -ProduktId $matches[0].produktId -Fachbereich $fbDef -Region 'Global' -Menge 0 -KostenIst 0 -Quelle 'GitHub' -Waehrung 'USD' }
          $billing[$key].menge += Convert-ImportNumber ([string]$i.quantity) 'quantity'
          $billing[$key].kostenIst += Convert-ImportNumber ([string]$i.netAmount) 'netAmount'
          if (-not [double]::IsFinite($billing[$key].menge) -or -not [double]::IsFinite($billing[$key].kostenIst)) { throw 'GitHub Billing: Summe ist nicht endlich.' }
        }
      }
    }
    foreach ($fact in $billing.Values) { $facts.Add($fact) }
  }
  return $facts
}
#endregion

#region Datenschutz: Mindestgruppengröße --------------------------------------
function Merge-SmallGroups {
  # Personenbezogene Zählwerte (Lizenzen, Unlizenzierte) unterhalb MinGroupSize
  # je Monat/Produkt zu Fachbereich "Sonstige" zusammenfassen.
  param([object[]]$Facts)
  $min = [int](Get-Setting 'MinGroupSize' 5)
  if ($min -le 1) { return $Facts }
  $out = [System.Collections.Generic.List[object]]::new()
  $small = @{}
  foreach ($f in $Facts) {
    $personen = [math]::Max($f.zugewiesen, $f.unlizenziert)
    if ($f.quelle -in 'Graph','GitHub' -and $personen -gt 0 -and $personen -lt $min -and $f.fachbereich -ne 'Pool (nicht zugewiesen)') {
      $k = ConvertTo-Json -InputObject @($f.monat,$f.produktId,$f.quelle,$f.waehrung,($null -ne $f.kostenIst)) -Compress
      if (-not $small[$k]) { $small[$k] = New-Fact -Monat $f.monat -ProduktId $f.produktId -Fachbereich 'Sonstige' -Region 'gemischt' -Menge 0 -Quelle $f.quelle -Aktiv 0 -Waehrung $f.waehrung -KostenIst $(if ($null -ne $f.kostenIst) { 0 } else { $null }) }
      $small[$k].menge += $f.menge; $small[$k].zugewiesen += $f.zugewiesen
      if ($null -ne $f.kostenIst) { $small[$k].kostenIst += $f.kostenIst }
      if ($null -eq $f.aktiv -or $null -eq $small[$k].aktiv) { $small[$k].aktiv = $null } else { $small[$k].aktiv += $f.aktiv }; $small[$k].unlizenziert += $f.unlizenziert
    } else { $out.Add($f) }
  }
  foreach ($v in $small.Values) { $out.Add($v) }
  return $out
}
#endregion

function Merge-LicenseHistory {
  # User/license APIs provide point-in-time snapshots. Preserve actually collected
  # past months only; CSV exports and usage/billing API history stay authoritative.
  param([object[]]$Facts, [string]$ExistingPath)
  if (-not (Test-Path $ExistingPath -PathType Leaf)) { return $Facts }
  $history = Get-Content $ExistingPath -Raw -Encoding utf8 | ConvertFrom-Json -NoEnumerate
  if ($history -isnot [array]) { throw 'Vorhandene facts.json ist kein Array. Historie vor erneutem Lauf prüfen.' }
  $currentMonth = Get-Date -Format 'yyyy-MM'
  $firstMonth = (Get-Date -Day 1).Date.AddMonths(-[int](Get-Setting 'MonthsBack' 12)).ToString('yyyy-MM')
  $fresh = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($f in $Facts) {
    [void]$fresh.Add((ConvertTo-Json -InputObject @($f.monat,$f.produktId,$f.quelle) -Compress))
  }
  $merged = [System.Collections.Generic.List[object]]::new()
  foreach ($f in $Facts) { $merged.Add($f) }
  foreach ($old in $history) {
    if ($null -eq $old -or $old -isnot [pscustomobject]) { throw 'Vorhandene Faktenhistorie enthält ungültige Zeilen.' }
    foreach ($name in 'monat','produktId','fachbereich','region','menge','quelle','zugewiesen','aktiv','unlizenziert') {
      if (-not $old.PSObject.Properties[$name]) { throw "Faktenhistorie: Pflichtfeld '$name' fehlt." }
    }
    if ($old.monat -isnot [string] -or $old.monat -notmatch '^\d{4}-(0[1-9]|1[0-2])$' -or $old.produktId -isnot [string] -or -not $old.produktId) { throw 'Faktenhistorie: ungültiger Schlüssel.' }
    foreach ($name in 'menge','kostenIst','zugewiesen','aktiv','unlizenziert') {
      $property = $old.PSObject.Properties[$name]
      if ($property -and $null -ne $property.Value -and ($property.Value -is [string] -or $property.Value -is [bool] -or -not [double]::IsFinite([double]$property.Value))) { throw "Faktenhistorie: ungültiger Wert '$name'." }
    }
    foreach ($name in 'menge','zugewiesen','unlizenziert') { if ($null -eq $old.$name) { throw "Faktenhistorie: Nullwert in '$name'." } }
    if ($old.PSObject.Properties['waehrung'] -and $null -ne $old.waehrung -and $old.waehrung -notmatch '^[A-Z]{3}$') { throw 'Faktenhistorie: ungültige Währung.' }
    if ($old.zugewiesen -lt 0 -or $old.unlizenziert -lt 0 -or ($null -ne $old.aktiv -and ($old.aktiv -lt 0 -or $old.aktiv -gt $old.zugewiesen))) { throw 'Faktenhistorie: ungültige Personenzählung.' }
    if ($old.monat -lt $firstMonth -or $old.monat -ge $currentMonth) { continue }
    $snapshot = $old.quelle -eq 'Graph' -and $cfg.EnabledSources -contains 'Graph'
    if ($old.quelle -eq 'GitHub' -and $cfg.EnabledSources -contains 'GitHub') {
      $p = $catalog | Where-Object produktId -eq $old.produktId | Select-Object -First 1
      $snapshot = $old.zugewiesen -gt 0 -or ($p -and $p.abrechnungsart -eq 'ProUser' -and $null -eq $old.kostenIst)
    }
    $key = ConvertTo-Json -InputObject @($old.monat,$old.produktId,$old.quelle) -Compress
    if ($snapshot -and -not $fresh.Contains($key)) { $merged.Add($old) }
  }
  return $merged
}

function Publish-FactFiles {
  # Stage and back up the complete output set before replacement. Roll back any
  # replacements on publication failure; readers should wait until the run ends.
  param([object[]]$Facts, [string]$OutputPath, [string]$CatalogPath, [char]$Delimiter)
  $stage = Join-Path $OutputPath ('.finops-' + [guid]::NewGuid().ToString('N'))
  New-Item $stage -ItemType Directory | Out-Null
  $names = @('facts.json','facts.csv','lizenzkatalog.json')
  $replaced = [System.Collections.Generic.List[string]]::new()
  $cleanup = $true
  try {
    ConvertTo-Json -InputObject $Facts -Depth 10 | Set-Content (Join-Path $stage 'facts.json') -Encoding utf8
    $csvFacts = @(foreach ($f in $Facts) {
      $copy = [ordered]@{}
      foreach ($property in $f.PSObject.Properties) {
        $value = $property.Value
        if ($value -is [string] -and $value -match '^[\s\u0000-\u001f]*[=+@-]') { $value = "'" + $value }
        $copy[$property.Name] = $value
      }
      [pscustomobject]$copy
    })
    if ($csvFacts.Count) { $csvFacts | Export-Csv (Join-Path $stage 'facts.csv') -Delimiter $Delimiter -NoTypeInformation -Encoding utf8 }
    else {
      $header = (New-Fact -Monat '2000-01' -ProduktId '_schema' -Menge 0 -Quelle '_schema' | ConvertTo-Csv -Delimiter $Delimiter -NoTypeInformation)[0]
      Set-Content (Join-Path $stage 'facts.csv') -Value $header -Encoding utf8
    }
    Copy-Item $CatalogPath (Join-Path $stage 'lizenzkatalog.json')
    foreach ($name in $names) {
      $target = Join-Path $OutputPath $name
      if (Test-Path $target -PathType Leaf) { Copy-Item $target (Join-Path $stage ($name + '.backup')) }
    }
    try {
      foreach ($name in $names) {
        # Register before moving so even a partially failed replacement is restored.
        $replaced.Add($name)
        Move-Item (Join-Path $stage $name) (Join-Path $OutputPath $name) -Force
      }
    } catch {
      $failure = $_
      try {
        foreach ($name in $replaced) {
          $backup = Join-Path $stage ($name + '.backup')
          $target = Join-Path $OutputPath $name
          if (Test-Path $backup) { Copy-Item $backup $target -Force }
          elseif (Test-Path $target) { Remove-Item $target -Force }
        }
      } catch {
        $cleanup = $false
        Write-Warning "Wiederherstellung fehlgeschlagen. Sicherungen bleiben erhalten: $stage"
        throw
      }
      throw $failure
    }
  } finally {
    # Keep backups if rollback itself failed; do not destroy the only recovery copy.
    if ($cleanup) { Remove-Item $stage -Recurse -Force }
  }
}

#region Hauptablauf -----------------------------------------------------------
$cfg = Get-Config $ConfigPath
if ($ValidateOnly) { Write-Host 'Konfiguration formal gültig. Keine Anmeldung oder Datenabfrage ausgeführt.'; return }
New-Item -ItemType Directory -Force -Path $cfg.OutputPath | Out-Null
try { $collectorLock = [IO.File]::Open((Join-Path $cfg.OutputPath '.collector.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
catch { throw 'Ausgabeordner wird bereits von einem Collector verwendet oder ist nicht schreibbar.' }
try {
$script:LogFile = Join-Path $cfg.OutputPath ("collector_{0:yyyyMMdd_HHmm}.log" -f (Get-Date))
Write-Log "Start – Konfiguration: $ConfigPath"
$cfg.CatalogPath = Resolve-ConfigPath $cfg.CatalogPath
$catalog = @(Get-Catalog $cfg.CatalogPath)
Write-Log "Lizenzkatalog: $($catalog.Count) aktive Produkte"

$sources = @($cfg.EnabledSources)
$authError = $null
if ($sources -contains 'Graph' -or ($sources -contains 'Azure' -and (Get-Setting 'AzureMode' 'Export') -eq 'Query')) {
  try { Connect-Tenant } catch { $authError = $_.Exception.Message; Write-Log "Tenant-Anmeldung fehlgeschlagen: $authError" 'ERROR' }
}

$all = [System.Collections.Generic.List[object]]::new()
$plan = [ordered]@{
  'Graph'  = { Get-GraphLicenseFacts }
  'Azure'  = { if ((Get-Setting 'AzureMode' 'Export') -eq 'Query') { Get-AzureQueryFacts } else { Import-AzureExportFacts } }
  'PPAC'   = { Import-PpacCreditFacts }
  'GitHub' = { Get-GitHubFacts }
}
$fehler = 0
foreach ($name in $plan.Keys) {
  if ($sources -notcontains $name) { continue }
  try {
    if ($authError -and ($name -eq 'Graph' -or ($name -eq 'Azure' -and (Get-Setting 'AzureMode' 'Export') -eq 'Query'))) { throw $authError }
    $r = @(& $plan[$name])
    foreach ($x in $r) { if ($x) { $all.Add($x) } }
    Write-Log "$($name): $($r.Count) Datensätze"
  } catch { $fehler++; Write-Log "$name fehlgeschlagen: $($_.Exception.Message)" 'ERROR' }
}

if ($fehler -gt 0) {
  Write-Log 'Ergebnisdateien unverändert: Mindestens eine aktivierte Quelle ist fehlgeschlagen.' 'ERROR'
  exit 1
}
$withHistory = @(Merge-LicenseHistory -Facts $all.ToArray() -ExistingPath (Join-Path $cfg.OutputPath 'facts.json'))
$final = @(Merge-SmallGroups $withHistory)
$delim = Get-Setting 'CsvDelimiter' ';'
Publish-FactFiles -Facts $final -OutputPath $cfg.OutputPath -CatalogPath $cfg.CatalogPath -Delimiter $delim
Write-Log "Fertig: $($final.Count) Datensätze, $fehler Quelle(n) mit Fehler"
if ($fehler -gt 0) { exit 1 }
} finally { $collectorLock.Dispose() }
#endregion

