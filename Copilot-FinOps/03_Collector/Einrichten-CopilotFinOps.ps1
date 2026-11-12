#Requires -Version 7.2
<#
.SYNOPSIS
  Erstellt eine lokale Collector-Konfiguration mit gezielter Quellenauswahl.
.DESCRIPTION
  Bestehende Einstellungen bleiben erhalten. Vor jedem Überschreiben wird eine
  datierte Sicherung erstellt. -DiscoverAzure liest Tenant und Abonnements per
  Benutzeranmeldung; Apps, Rollen und Ressourcen werden niemals verändert.
  Der Collector verwendet weiterhin die eigene App mit Zertifikat.
  Reine CSV-Quellen benötigen weder Azure-Modul noch Tenant-Anmeldung.
.EXAMPLE
  ./Einrichten-CopilotFinOps.ps1
.EXAMPLE
  ./Einrichten-CopilotFinOps.ps1 -Sources Azure -AzureMode Query -DiscoverAzure
.EXAMPLE
  ./Einrichten-CopilotFinOps.ps1 -Sources PPAC -NonInteractive -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot '../02_Konfiguration/config.json'),
  [ValidateSet('Graph','Azure','PPAC','GitHub')][string[]]$Sources,
  [ValidateSet('Export','Query')][string]$AzureMode,
  [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')][string]$TenantId,
  [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')][string]$ClientId,
  [string]$CertificateThumbprint,
  [string[]]$SubscriptionIds,
  [string]$CostCenterTag,
  [switch]$DiscoverAzure,
  [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
# WhatIf never starts a sign-in, prompts for values, or creates files.
if ($WhatIfPreference) {
  [void]$PSCmdlet.ShouldProcess($ConfigPath, 'Aktionsvorschau: Konfiguration vorbereiten, vorhandene Datei sichern und speichern; ggf. Azure-Metadaten lesen (keine Konfigurationsprüfung)')
  return
}
$guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
$cfg = [ordered]@{
  TenantId=''; ClientId=''; CertificateThumbprint=''
  OutputPath='..\06_Daten\out'; CatalogPath='lizenzkatalog.json'
  DepartmentAttribute='department'; MinGroupSize=5; InactiveDays=30; MonthsBack=12
  EnabledSources=@('Graph'); AzureMode='Export'
  AzureExportFolder='..\06_Daten\import\azure-export'; AzureScopes=@()
  CostCenterTag=''; CostApiVersion='2023-11-01'
  AzureExportColumnMap=@{Date='Date';MeterCategory='MeterCategory';MeterName='MeterName';ServiceName='ConsumedService';Location='ResourceLocation';Tags='Tags';Cost='CostInBillingCurrency';Quantity='Quantity';Currency='BillingCurrencyCode'}
  PpacImportFolder='..\06_Daten\import\ppac'; PpacProduktId='CS-CAPACITY'
  PpacColumnMap=@{Date='Date';Environment='Environment';Agent='Agent';Credits='Credits'}
  EnvironmentToDepartment=@{}; CsvDelimiter=';'
  GitHubOrg=''; GitHubApiVersion='2022-11-28'; GitHubDefaultDepartment='IT'
  ProduktIds=@{PremiumLizenz='M365-COPILOT';ChatBasis='M365-COPILOT-CHAT';GitHubSeats='GH-COPILOT-BUS'}
}
$previous = $null
if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
  $previous = Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8
  $existing = ConvertFrom-Json -InputObject $previous -AsHashtable
  if ($existing -isnot [System.Collections.IDictionary]) { throw 'Vorhandene config.json muss ein JSON-Objekt sein; sie wurde nicht verändert.' }
  foreach ($key in $existing.Keys) { $cfg[$key] = $existing[$key] }
}
function Read-Setting([string]$Name, [string]$Help, [string]$Pattern) {
  $value = [string]$cfg[$Name]
  if (-not $NonInteractive) {
    Write-Host $Help -ForegroundColor Cyan
    $entered = Read-Host "$Name [$value] (Enter übernimmt den Wert)"
    if (-not [string]::IsNullOrWhiteSpace($entered)) { $value = $entered.Trim() }
  }
  if ([string]::IsNullOrWhiteSpace($value) -or ($Pattern -and $value -notmatch $Pattern)) { throw "$Name fehlt oder ist ungültig. Parameter angeben oder Assistent ohne -NonInteractive starten." }
  $cfg[$Name] = $value
}
Write-Host 'Copilot-FinOps: lokale Einrichtung' -ForegroundColor Cyan
Write-Host 'Tenant = Microsoft-Verzeichnis; Client-ID = ID eurer bereits registrierten Collector-App.'
if (-not $PSBoundParameters.ContainsKey('Sources') -and -not $NonInteractive) {
  Write-Host 'Welche Daten sollen eingelesen werden? Mehrere Nummern mit Komma trennen.'
  Write-Host '1 = M365 Graph, 2 = Azure CSV-Export (ohne Anmeldung), 3 = Azure Query API, 4 = Copilot Studio CSV, 5 = GitHub'
  $selection = Read-Host ("Auswahl [Enter: {0}, Azure {1}]" -f ($cfg.EnabledSources -join ', '), $cfg.AzureMode)
  if ($selection) {
    $numbers = @($selection.Split(',') | ForEach-Object { $_.Trim() })
    if ($numbers | Where-Object { $_ -notmatch '^[1-5]$' }) { throw 'Nur Nummern 1 bis 5 mit Komma trennen.' }
    if ($numbers -contains '2' -and $numbers -contains '3') { throw 'Für Azure entweder CSV-Export (2) oder Query (3) wählen.' }
    $Sources = @(foreach ($number in $numbers) { switch ($number) { '1' {'Graph'} '2' {'Azure'} '3' {'Azure'} '4' {'PPAC'} '5' {'GitHub'} } })
    if ($numbers -contains '2') { $cfg.AzureMode = 'Export' }
    if ($numbers -contains '3') { $cfg.AzureMode = 'Query' }
  }
}
if ($PSBoundParameters.ContainsKey('Sources') -and -not $Sources.Count) { throw '-Sources benötigt mindestens eine Datenquelle.' }
if ($Sources) { $cfg.EnabledSources = @($Sources | Select-Object -Unique) }
if ($AzureMode) { $cfg.AzureMode = $AzureMode }
if ($TenantId) { $cfg.TenantId = $TenantId }
if ($ClientId) { $cfg.ClientId = $ClientId }
if ($CertificateThumbprint) { $cfg.CertificateThumbprint = $CertificateThumbprint }
if ($PSBoundParameters.ContainsKey('CostCenterTag')) { $cfg.CostCenterTag = $CostCenterTag }
if ($cfg.EnabledSources -isnot [array] -or -not $cfg.EnabledSources.Count -or @($cfg.EnabledSources | Where-Object { $_ -cnotin 'Graph','Azure','PPAC','GitHub' }).Count) { throw 'Mindestens eine bekannte Datenquelle wählen.' }
$needsTenant = $cfg.EnabledSources -contains 'Graph' -or ($cfg.EnabledSources -contains 'Azure' -and $cfg.AzureMode -eq 'Query')
$azureQuery = $cfg.EnabledSources -contains 'Azure' -and $cfg.AzureMode -eq 'Query'
if ($DiscoverAzure) {
  if (-not $needsTenant) { throw '-DiscoverAzure ist nur für Graph oder Azure Query nötig. CSV-Importe benötigen keine Anmeldung.' }
  if (-not (Get-Module -ListAvailable Az.Accounts)) { throw 'Az.Accounts fehlt. Einmalig ausführen: Install-Module Az.Accounts -Scope CurrentUser -Repository PSGallery' }
  Import-Module Az.Accounts -ErrorAction Stop
  Write-Host 'Benutzeranmeldung zur Ermittlung von Tenant/Abonnements. Der Collector nutzt später eure App und ihr Zertifikat.'
  $login = @{Scope='Process';SkipContextPopulation=$true;AllowNoSubscriptions=$true;ErrorAction='Stop'}
  $discoveryTenant = if ($TenantId) { $TenantId } elseif ([string]$cfg.TenantId -match $guidPattern) { [string]$cfg.TenantId } else { $null }
  if ($discoveryTenant) { $login.Tenant = $discoveryTenant }
  Connect-AzAccount @login | Out-Null
  $context = Get-AzContext -ErrorAction Stop
  if (-not $context -or [string]$context.Tenant.Id -notmatch $guidPattern) { throw 'Nach Anmeldung konnte keine gültige Tenant-ID ermittelt werden.' }
  if ($discoveryTenant -and $context.Tenant.Id -ne $discoveryTenant) { throw 'Angemeldeter Tenant stimmt nicht mit der gewählten/vorhandenen TenantId überein.' }
  $cfg.TenantId = [string]$context.Tenant.Id
  Write-Host "Ermittelter Tenant: $($cfg.TenantId). Diese ID muss zur Collector-App gehören." -ForegroundColor Cyan
  if ($azureQuery) {
    $subscriptions = @(Get-AzSubscription -TenantId $cfg.TenantId -ErrorAction Stop | Where-Object { $_.State -eq 'Enabled' })
    if (-not $subscriptions.Count) { throw 'Keine aktiven Abonnements im ausgewählten Tenant sichtbar.' }
    for ($i = 0; $i -lt $subscriptions.Count; $i++) { Write-Host ("{0}: {1} ({2})" -f ($i+1), $subscriptions[$i].Name, $subscriptions[$i].Id) }
    if (-not $PSBoundParameters.ContainsKey('SubscriptionIds')) {
      if ($NonInteractive) { throw '-DiscoverAzure mit -NonInteractive benötigt explizite -SubscriptionIds. Es werden niemals alle Abonnements automatisch übernommen.' }
      $choices = Read-Host 'Nur gewünschte Abonnements wählen: Nummern mit Komma trennen (leer bricht ab)'
      if ([string]::IsNullOrWhiteSpace($choices)) { throw 'Keine Abonnements gewählt. Konfiguration unverändert.' }
      $SubscriptionIds = @(foreach ($part in $choices.Split(',')) {
        $n = 0
        if (-not [int]::TryParse($part.Trim(), [ref]$n) -or $n -lt 1 -or $n -gt $subscriptions.Count) { throw 'Ungültige Abonnement-Auswahl.' }
        [string]$subscriptions[$n-1].Id
      })
    }
    foreach ($id in $SubscriptionIds) { if ($id -notin $subscriptions.Id) { throw "Abonnement $id ist im angemeldeten Tenant nicht sichtbar. Konfiguration unverändert." } }
  }
}
if ($needsTenant) {
  if (-not $TenantId -and -not $DiscoverAzure) { Read-Setting 'TenantId' 'Entra Admin Center > Identität > Übersicht > Mandanten-ID; alternativ -DiscoverAzure.' $guidPattern }
  if (-not $ClientId) { Read-Setting 'ClientId' 'Entra Admin Center > App-Registrierungen > Collector-App > Anwendungs-ID (Client). Keine Objekt-ID verwenden.' $guidPattern }
  $thumb = ([string]$cfg.CertificateThumbprint -replace '[\s\u200e\u200f:]', '').ToUpperInvariant()
  if (-not $CertificateThumbprint -and -not $NonInteractive -and $IsWindows) {
    $certs = @(Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) -and $_.NotBefore -le (Get-Date) } | Sort-Object Thumbprint -Unique)
    if ($certs.Count) {
      Write-Host 'Vorhandene gültige Zertifikate mit privatem Schlüssel (ausgewähltes Zertifikat muss zur Collector-App hochgeladen sein):'
      for ($i=0; $i -lt $certs.Count; $i++) { Write-Host ("{0}: {1}, gültig bis {2:yyyy-MM-dd}, {3}" -f ($i+1),$certs[$i].Subject,$certs[$i].NotAfter,$certs[$i].Thumbprint) }
      $choice = Read-Host 'Zertifikatsnummer (Enter für bisherigen Fingerabdruck/manuelle Eingabe)'
      if ($choice) {
        $n = 0
        if (-not [int]::TryParse($choice,[ref]$n) -or $n -lt 1 -or $n -gt $certs.Count) { throw 'Ungültige Zertifikatsauswahl.' }
        $thumb = $certs[$n-1].Thumbprint
      }
    }
  }
  $cfg.CertificateThumbprint = $thumb
  if ($thumb -notmatch '^[0-9A-F]{40}$') { Read-Setting 'CertificateThumbprint' '40-stelliger Fingerabdruck aus New-AppZertifikat.ps1; privater Schlüssel bleibt im Windows-Zertifikatspeicher.' '^[0-9a-fA-F]{40}$' }
  $cfg.CertificateThumbprint = $cfg.CertificateThumbprint.ToUpperInvariant()
  if (-not $IsWindows) { Write-Warning 'Konfiguration kann hier erstellt werden. Der Zertifikats-Collector benötigt Windows und das Zertifikat unter dem ausführenden Konto.' }
}
if ($azureQuery) {
  if (-not $SubscriptionIds -and -not $NonInteractive -and -not $DiscoverAzure) {
    $ids = Read-Host 'Abonnement-IDs mit Komma trennen (Enter übernimmt vorhandene AzureScopes)'
    if ($ids) { $SubscriptionIds = @($ids.Split(',') | ForEach-Object { $_.Trim() }) }
  }
  if ($SubscriptionIds) {
    foreach ($id in $SubscriptionIds) { if ($id -notmatch $guidPattern) { throw 'SubscriptionIds müssen vollständige GUIDs sein.' } }
    $cfg.AzureScopes = @($SubscriptionIds | ForEach-Object { '/subscriptions/' + $_.ToLowerInvariant() } | Select-Object -Unique)
  }
  if ($cfg.AzureScopes -isnot [array] -or -not $cfg.AzureScopes.Count) { throw 'Azure Query benötigt explizit gewählte Abonnement-IDs (-SubscriptionIds).' }
  foreach ($scope in $cfg.AzureScopes) { if ($scope -notmatch ('^/subscriptions/' + $guidPattern.TrimStart('^'))) { throw 'Vorhandener AzureScope ist ungültig: /subscriptions/<GUID> erwartet.' } }
  Read-Setting 'CostCenterTag' 'Name des Azure-Tags für den Fachbereich, z. B. Kostenstelle. Die App benötigt Cost Management Reader je gewähltem Abonnement.' '^[^<>]+$'
}
if ($cfg.EnabledSources -contains 'GitHub') { Read-Setting 'GitHubOrg' 'GitHub-Organisation. Token ausschließlich als Umgebungsvariable FINOPS_GITHUB_TOKEN hinterlegen.' '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$' }
# The old shipped template had four empty PPAC mappings. Repair these empty
# defaults, while preserving every explicitly configured nonempty column name.
if ($cfg.EnabledSources -contains 'PPAC') {
  if ($cfg.PpacColumnMap -isnot [System.Collections.IDictionary]) { throw 'PpacColumnMap muss ein Objekt sein.' }
  foreach ($key in 'Date','Environment','Agent','Credits') { if ([string]::IsNullOrWhiteSpace([string]$cfg.PpacColumnMap[$key])) { $cfg.PpacColumnMap[$key] = $key } }
  Write-Host 'PPAC: CSV-Kopfzeile mit PpacColumnMap abgleichen; Standardspalten Date, Environment, Agent, Credits.'
}
Write-Host ("Quellen: {0}; Azure-Verfahren: {1}" -f ($cfg.EnabledSources -join ', '), $cfg.AzureMode)
Write-Host 'Nur lokale Einstellungen werden gespeichert; Berechtigungen, App-Registrierung und Preise separat prüfen.'
if (-not $PSCmdlet.ShouldProcess($ConfigPath, 'Bestehende Datei sichern und Collector-Konfiguration speichern')) { return }
$directory = Split-Path $ConfigPath -Parent
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$json = ConvertTo-Json -InputObject $cfg -Depth 50
$stage = Join-Path $directory ('.config-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
  Set-Content -LiteralPath $stage -Value $json -Encoding utf8
  # Use the Collector's own checks so a successful setup cannot save a
  # configuration that the next run rejects before collecting any data.
  & (Join-Path $PSScriptRoot 'Collect-CopilotCosts.ps1') -ConfigPath $stage -ValidateOnly
  if ($null -ne $previous) {
    # Never replace a file that changed while this assistant was open.
    if ((Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8) -cne $previous) { throw 'config.json wurde während der Einrichtung verändert. Erneut laden; keine Datei überschrieben.' }
    $backup = $ConfigPath + '.' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '.' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.bak'
    Copy-Item -LiteralPath $ConfigPath -Destination $backup -ErrorAction Stop
    Write-Host "Sicherung: $backup"
  } elseif (Test-Path -LiteralPath $ConfigPath) { throw 'config.json wurde inzwischen erstellt. Erneut laden; keine Datei überschrieben.' }
  Move-Item -LiteralPath $stage -Destination $ConfigPath -Force
} finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage } }
Write-Host "Gespeichert: $ConfigPath" -ForegroundColor Green
Write-Host 'Nächster Schritt: Konfigurationsmaske öffnen und diese config.json laden; danach Install-Voraussetzungen.ps1 und Start-Collector.cmd ausführen.'
