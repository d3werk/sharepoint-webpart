# Offline regressions; no modules, tenant login, network access or Pester required.
# Run: pwsh -NoProfile -File tests/collector.Tests.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$collector = Join-Path $root '03_Collector/Collect-CopilotCosts.ps1'
$source = Get-Content $collector -Raw
$functions = $source.Substring(0, $source.IndexOf('#region Hauptablauf'))
# Define only the real production functions; do not execute its main entrypoint.
. ([scriptblock]::Create($functions.Substring($functions.IndexOf('function Write-Log'))))
$script:LogFile = $null
$script:passed = 0
function Assert($condition, [string]$message) {
  if (-not $condition) { throw "FAIL: $message" }
  $script:passed++
  Write-Host "PASS: $message"
}
function Assert-Throws([scriptblock]$operation, [string]$message) {
  $thrown = $false
  try { & $operation | Out-Null } catch { $thrown = $true }
  Assert $thrown $message
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('finops-test-' + [guid]::NewGuid())
New-Item $temp -ItemType Directory | Out-Null
try {
  foreach ($file in Get-ChildItem (Join-Path $root '03_Collector') -Filter '*.ps1') {
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$null,[ref]$errors) | Out-Null
    Assert (-not $errors) "Syntax $($file.Name)"
  }
  Assert ((Convert-ImportNumber '1,25' 'Credits') -eq 1.25) 'decimal comma accepted'
  Assert ((Convert-ImportNumber '-1.25' 'Cost') -eq -1.25) 'credit adjustment accepted'
  Assert-Throws { Convert-ImportNumber '1.234,56' 'Cost' } 'ambiguous grouped numeric rejected'
  Assert-Throws { Convert-ImportNumber 'NaN' 'Cost' } 'NaN rejected'
  Assert-Throws { Convert-ImportNumber '-1' 'Credits' -NonNegative } 'negative credit quantity rejected'
  Assert ((Convert-ImportDate '20261101').ToString('yyyy-MM') -eq '2026-11') 'Azure numeric YYYYMMDD parsed as date'
  Assert ((Convert-ImportDate '02.11.2026').Day -eq 2) 'German import date deterministic'
  Assert-Throws { Convert-ImportDate '11/02/2026' } 'ambiguous PPAC slash date rejected'
  Assert-Throws { New-Fact -Monat '2026-13' -ProduktId P -Menge 1 } 'invalid fact month rejected'
  Assert-Throws { New-Fact -Monat '2026-01' -ProduktId P -Menge ([double]::PositiveInfinity) } 'infinite fact quantity rejected'
  $f = New-Fact -Monat '2026-01' -ProduktId P -Menge 1 -Quelle Graph
  Assert ($null -eq $f.aktiv) 'missing activity remains unknown'

  $script:cfg = [pscustomobject]@{ MinGroupSize=5 }
  $f1 = New-Fact -Monat '2026-01' -ProduktId P -Menge 2 -Zugewiesen 2 -Aktiv 1 -Fachbereich A -Region DE -Quelle Graph
  $f2 = New-Fact -Monat '2026-01' -ProduktId P -Menge 1 -Zugewiesen 1 -Fachbereich B -Region AT -Quelle Graph
  $financial = New-Fact -Monat '2026-01' -ProduktId C -Menge 2 -Agent 'A|B' -Umgebung 'U|V' -Fachbereich Small -Quelle 'PPAC-CSV'
  $merged = @(Merge-SmallGroups @($f1,$f2,$financial))
  Assert ($merged.Count -eq 2) 'only person-count groups are pooled'
  $group = $merged | Where-Object produktId -eq P
  Assert ($group.fachbereich -eq 'Sonstige' -and $group.region -eq 'gemischt' -and $group.zugewiesen -eq 3) 'small group region removed and counts preserved'
  Assert ($null -eq $group.aktiv) 'pooled activity stays unknown if any input is unknown'
  Assert (($merged | Where-Object produktId -eq C).agent -eq 'A|B') 'financial agent dimension preserved'
  $g = New-Fact -Monat '2026-01' -ProduktId G -Menge 1 -Zugewiesen 1 -Aktiv 0 -Fachbereich IT -Quelle GitHub
  Assert ((@(Merge-SmallGroups @($g)))[0].fachbereich -eq 'Sonstige') 'GitHub small person groups pooled'

  # A one-user Graph response and failed activity report must produce a license fact
  # with unknown activity, never a false inactive/savings signal.
  $script:cfg = [pscustomobject]@{ DepartmentAttribute='department'; ProduktIds=[pscustomobject]@{PremiumLizenz='P';ChatBasis='CHAT'};InactiveDays=30 }
  $script:catalog = @([pscustomobject]@{produktId='P';datenquelle='Graph';zuordnungsschluessel=[pscustomobject]@{graphSkuPartNumber='PREMIUM'}})
  function Get-AccessToken { return 'offline-test-token' }
  function Invoke-GraphPaged($Uri,$Token) {
    if ($Uri -like '*subscribedSkus*') { return [pscustomobject]@{skuPartNumber='PREMIUM';skuId='sku1';prepaidUnits=[pscustomobject]@{enabled=1};consumedUnits=1} }
    if ($Uri -like '*/users?*') { return [pscustomobject]@{department='IT';usageLocation='DE';userPrincipalName='nobody@example.invalid';assignedLicenses=@([pscustomobject]@{skuId='sku1'})} }
    throw 'Offline: usage report unavailable'
  }
  $facts = @(Get-GraphLicenseFacts)
  Assert ($facts.Count -eq 1 -and $facts[0].zugewiesen -eq 1) 'singleton Graph collections handled'
  Assert ($null -eq $facts[0].aktiv) 'failed Graph usage never reported as inactive'

  $import = New-Item (Join-Path $temp 'ppac') -ItemType Directory
  $out = Join-Path $temp 'out'
  $cat = Join-Path $temp 'catalog.json'
  $config = Join-Path $temp 'config.json'
  @{produkte=@(@{produktId='C';datenquelle='PPAC-CSV';aktiv=$true})} | ConvertTo-Json -Depth 5 | Set-Content $cat
  $now = Get-Date -Format 'yyyy-MM-dd'
  $old = (Get-Date).AddMonths(-15).ToString('yyyy-MM-dd')
  $future = (Get-Date).AddMonths(1).ToString('yyyy-MM-dd')
  @("Date;Environment;Agent;Credits", "$now;Env|A;=SUM(1);1,5", "$now;Env|A;=SUM(1);2,5", "$old;Env|A;=SUM(1);100", "$future;Env|A;=SUM(1);100") | Set-Content (Join-Path $import 'test.csv')
  $c = @{OutputPath='out';CatalogPath='catalog.json';EnabledSources=@('PPAC');PpacImportFolder='ppac';PpacProduktId='C';PpacColumnMap=@{Date='Date';Environment='Environment';Agent='Agent';Credits='Credits'};EnvironmentToDepartment=@{'Env|A'='IT|DE'};CsvDelimiter=';';MonthsBack=12;MinGroupSize=5}
  $c | ConvertTo-Json -Depth 8 | Set-Content $config
  $engine = (Get-Process -Id $PID).Path
  & $engine -NoProfile -File $collector -ConfigPath $config
  Assert ($LASTEXITCODE -eq 0) 'offline PPAC-only collector works without tenant credentials'
  $result = @(Get-Content (Join-Path $out 'facts.json') -Raw | ConvertFrom-Json)
  Assert ($result.Count -eq 1 -and $result[0].menge -eq 4) 'PPAC aggregates decimal credits and filters date window'
  Assert ($result[0].fachbereich -eq 'IT|DE' -and $result[0].umgebung -eq 'Env|A' -and $result[0].agent -eq '=SUM(1)') 'pipe characters survive aggregation in every dimension'
  $csv = Get-Content (Join-Path $out 'facts.csv') -Raw
  Assert ($csv.Contains("'=SUM(1)")) 'CSV spreadsheet formula neutralized'
  $previous = Get-Content (Join-Path $out 'facts.json') -Raw
  'Date;Environment;Credits' | Set-Content (Join-Path $import 'broken.csv')
  "$now;Env|A;10" | Add-Content (Join-Path $import 'broken.csv')
  & $engine -NoProfile -File $collector -ConfigPath $config
  Assert ($LASTEXITCODE -eq 1) 'missing mapped import column fails the source'
  Assert ((Get-Content (Join-Path $out 'facts.json') -Raw) -eq $previous) 'failed run preserves previous complete facts'
  Remove-Item (Join-Path $import 'broken.csv')
  $c.EnabledSources=@('Unknown'); $c | ConvertTo-Json -Depth 8 | Set-Content $config
  Assert-Throws { Get-Config $config } 'unknown source rejected'
  $c.EnabledSources=@('PPAC'); $c.MonthsBack=1.5; $c | ConvertTo-Json -Depth 8 | Set-Content $config
  Assert-Throws { Get-Config $config } 'fractional month window rejected'
  $c.MonthsBack=12; $c.EnabledSources=@('Graph'); $c | ConvertTo-Json -Depth 8 | Set-Content $config
  Assert-Throws { Get-Config $config } 'Graph configuration still requires tenant credentials'

  # License rollover history: retain only real past snapshots, not old import or
  # usage copies; do not duplicate a month that a fresh source already supplied.
  $script:cfg = [pscustomobject]@{EnabledSources=@('Graph','GitHub');MonthsBack=12;MinGroupSize=5}
  $script:catalog = @([pscustomobject]@{produktId='G';abrechnungsart='ProUser'})
  $lastMonth = (Get-Date).AddMonths(-1).ToString('yyyy-MM')
  $current = Get-Date -Format 'yyyy-MM'
  $oldMonth = (Get-Date).AddMonths(-20).ToString('yyyy-MM')
  $historic = @(
    (New-Fact -Monat $lastMonth -ProduktId P -Fachbereich IT -Region DE -Menge 5 -Zugewiesen 5 -Aktiv 2 -Quelle Graph),
    (New-Fact -Monat $lastMonth -ProduktId G -Fachbereich IT -Region Global -Menge 5 -Zugewiesen 5 -Aktiv 3 -Quelle GitHub),
    (New-Fact -Monat $lastMonth -ProduktId USAGE -Fachbereich IT -Region Global -Menge 100 -KostenIst 9 -Quelle GitHub -Waehrung USD),
    (New-Fact -Monat $lastMonth -ProduktId C -Fachbereich IT -Region Global -Menge 100 -Quelle 'PPAC-CSV'),
    (New-Fact -Monat $oldMonth -ProduktId P -Fachbereich IT -Region DE -Menge 5 -Zugewiesen 5 -Aktiv 2 -Quelle Graph),
    (New-Fact -Monat $current -ProduktId P -Fachbereich IT -Region DE -Menge 5 -Zugewiesen 5 -Aktiv 2 -Quelle Graph)
  )
  $historyFile = Join-Path $temp 'history.json'
  ConvertTo-Json -InputObject $historic -Depth 5 | Set-Content $historyFile
  $fresh = @((New-Fact -Monat $current -ProduktId P -Fachbereich IT -Region DE -Menge 7 -Zugewiesen 7 -Aktiv 4 -Quelle Graph))
  $retained = @(Merge-LicenseHistory -Facts $fresh -ExistingPath $historyFile)
  Assert ($retained.Count -eq 3) 'rollover retains past Graph and GitHub seats, excludes old imports, usage and out-of-window snapshots'
  Assert (@($retained | Where-Object { $_.monat -eq $current }).Count -eq 1 -and $retained[0].menge -eq 7) 'current license snapshot replaces previous current-month rows'
  ConvertTo-Json -InputObject $retained -Depth 5 | Set-Content $historyFile
  $again = @(Merge-LicenseHistory -Facts $fresh -ExistingPath $historyFile)
  Assert ($again.Count -eq 3) 'historical merge is idempotent'
  $fresh += New-Fact -Monat $lastMonth -ProduktId P -Fachbereich IT -Region DE -Menge 8 -Zugewiesen 8 -Aktiv 3 -Quelle Graph
  $replaced = @(Merge-LicenseHistory -Facts $fresh -ExistingPath $historyFile)
  Assert ($replaced.Count -eq 3 -and ($replaced | Where-Object { $_.monat -eq $lastMonth -and $_.produktId -eq 'P' }).menge -eq 8) 'fresh historic snapshot replaces stored same month/product/source'
  '{broken' | Set-Content $historyFile
  Assert-Throws { Merge-LicenseHistory -Facts $fresh -ExistingPath $historyFile } 'corrupt historical JSON blocks destructive update'
  '[{"monat":"2026-13"}]' | Set-Content $historyFile
  Assert-Throws { Merge-LicenseHistory -Facts $fresh -ExistingPath $historyFile } 'invalid historical fact blocks destructive update'

  # Privacy pooling preserves financial facts and distinct currencies.
  $script:cfg = [pscustomobject]@{MinGroupSize=5}
  $x = New-Fact -Monat $current -ProduktId G -Menge 1 -Zugewiesen 1 -Aktiv 1 -KostenIst 3 -Quelle GitHub -Waehrung USD
  $y = New-Fact -Monat $current -ProduktId G -Menge 2 -Zugewiesen 2 -Aktiv 1 -KostenIst 4 -Quelle GitHub -Waehrung USD
  $z = New-Fact -Monat $current -ProduktId G -Menge 1 -Zugewiesen 1 -Aktiv 1 -KostenIst 2 -Quelle GitHub -Waehrung EUR
  $pooled = @(Merge-SmallGroups @($x,$y,$z))
  Assert ($pooled.Count -eq 2 -and ($pooled | Where-Object waehrung -eq USD).kostenIst -eq 7) 'privacy pooling preserves actual costs and separates currencies'

  # Real Azure CSV import covers cutoff midnight, source currency, escaped tags,
  # pipe-containing dimensions and negative actual-cost adjustments.
  $azure = New-Item (Join-Path $temp 'azure') -ItemType Directory
  $script:cfg = [pscustomobject]@{ AzureExportFolder=$azure.FullName; AzureExportColumnMap=[pscustomobject]@{Date='Date';MeterCategory='MeterCategory';MeterName='MeterName';ServiceName='ServiceName';Location='Location';Tags='Tags';Cost='Cost';Quantity='Quantity';Currency='Currency'};CostCenterTag='Dept';MonthsBack=1 }
  $script:catalog = @([pscustomobject]@{produktId='AZ';datenquelle='AzureCostManagement';zuordnungsschluessel=[pscustomobject]@{azureMeterNameContains='AI'}})
  $boundary = (Get-Date -Day 1).Date.AddMonths(-1).ToString('yyyy-MM-dd')
  @(
    [pscustomobject]@{Date=$boundary;MeterCategory='AI';MeterName='AI';ServiceName='AI';Location='west|eu';Tags='"Dept":"IT|DE"';Cost='10,5';Quantity='2';Currency='USD'},
    [pscustomobject]@{Date=$boundary;MeterCategory='AI';MeterName='AI';ServiceName='AI';Location='west|eu';Tags='"Dept":"IT|DE"';Cost='-1,5';Quantity='-1';Currency='USD'}
  ) | Export-Csv (Join-Path $azure 'test.csv') -NoTypeInformation
  $azFacts = @(Import-AzureExportFacts)
  Assert ($azFacts.Count -eq 1 -and $azFacts[0].kostenIst -eq 9 -and $azFacts[0].menge -eq 1) 'Azure includes midnight cutoff and sums adjustments'
  Assert ($azFacts[0].waehrung -eq 'USD' -and $azFacts[0].fachbereich -eq 'IT|DE' -and $azFacts[0].region -eq 'west|eu') 'Azure source currency and pipe dimensions preserved'
  # Report window covers the configured inactivity period.
  $script:cfg = [pscustomobject]@{ DepartmentAttribute='department';InactiveDays=90 }
  $script:catalog = @()
  $script:reportUri = ''
  function Invoke-GraphPaged($Uri,$Token) {
    if ($Uri -like '*UsageUserDetail*') { $script:reportUri = $Uri }
    return @()
  }
  Get-GraphLicenseFacts | Out-Null
  Assert ($script:reportUri.Contains("period='D90'")) 'Graph 90-day inactivity uses D90 report window'
  $script:cfg.InactiveDays = 180
  Get-GraphLicenseFacts | Out-Null
  Assert ($script:reportUri.Contains("period='D180'")) 'Graph 180-day inactivity uses D180 report window'

  # API retries honor Retry-After without sleeping or contacting the network.
  $script:apiAttempts = 0
  $script:capturedWait = 0
  function Start-Sleep { param($Seconds); $script:capturedWait = $Seconds }
  function Invoke-RestMethod {
    param($Uri,$Headers,$Method,$TimeoutSec,$MaximumRedirection)
    $script:apiAttempts++
    if ($script:apiAttempts -eq 1) {
      $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
      $response.Headers.RetryAfter = [System.Net.Http.Headers.RetryConditionHeaderValue]::new([timespan]::FromSeconds(120))
      throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Throttled', $response)
    }
    return [pscustomobject]@{ok=$true}
  }
  $r = Invoke-Api -Uri 'https://graph.microsoft.com/v1.0/test' -Token 'offline-test'
  Assert ($r.ok -and $script:apiAttempts -eq 2 -and $script:capturedWait -ge 120) 'API respects Retry-After and recovers on next attempt'
  Assert-Throws { Invoke-Api -Uri 'https://attacker.example/steal' -Token 'offline-test' } 'bearer token never sent to unknown API host'
  Assert-Throws { Invoke-Api -Uri 'http://graph.microsoft.com/steal' -Token 'offline-test' } 'bearer token never sent without HTTPS'

  # Configured GitHub billing is required, while no mapped billing SKU makes it optional.
  $savedToken = $env:FINOPS_GITHUB_TOKEN
  try {
    $env:FINOPS_GITHUB_TOKEN = 'offline-test'
    $script:cfg = [pscustomobject]@{GitHubOrg='offline-org';ProduktIds=[pscustomobject]@{GitHubSeats='G'}}
    $script:catalog = @([pscustomobject]@{produktId='U';datenquelle='GitHubAPI';abrechnungsart='Verbrauch';zuordnungsschluessel=[pscustomobject]@{githubSku='sku'}})
    $script:billingCalls = 0
    function Invoke-Api {
      param($Uri,$Token,$ExtraHeaders)
      if ($Uri -like '*billing/seats*') { return [pscustomobject]@{total_seats=1;seats=@([pscustomobject]@{last_activity_at=(Get-Date).ToString('o')})} }
      $script:billingCalls++
      throw 'offline billing unavailable'
    }
    Assert-Throws { Get-GitHubFacts } 'configured GitHub billing failures fail the source'
    $script:catalog = @()
    $seats = @(Get-GitHubFacts)
    Assert ($seats.Count -eq 1 -and $script:billingCalls -eq 1) 'unmapped GitHub billing skipped while seat snapshot collected'
  } finally { $env:FINOPS_GITHUB_TOKEN = $savedToken }
  # Recognize the actual Microsoft report field; unknown report dates stay unknown.
  $script:cfg = [pscustomobject]@{DepartmentAttribute='department';InactiveDays=30}
  $script:catalog = @([pscustomobject]@{produktId='P';datenquelle='Graph';zuordnungsschluessel=[pscustomobject]@{graphSkuPartNumber='PREMIUM'}})
  function Invoke-GraphPaged($Uri,$Token) {
    if ($Uri -like '*subscribedSkus*') { return [pscustomobject]@{skuPartNumber='PREMIUM';skuId='sku1';prepaidUnits=[pscustomobject]@{enabled=1};consumedUnits=1} }
    if ($Uri -like '*/users?*') { return [pscustomobject]@{department='IT';usageLocation='DE';userPrincipalName='nobody@example.invalid';assignedLicenses=@([pscustomobject]@{skuId='sku1'})} }
    return [pscustomobject]@{userPrincipalName='nobody@example.invalid';microsoft365CopilotLastActivityDate=(Get-Date).ToString('yyyy-MM-dd')}
  }
  $realField = @(Get-GraphLicenseFacts)
  Assert ($realField.Count -eq 1 -and $realField[0].aktiv -eq 1) 'actual microsoft365CopilotLastActivityDate recognized'

  # GitHub historical billing uses supported year/month filters, no invented pages,
  # aggregates repository usage, and never multiplies current-month records.
  try {
    $env:FINOPS_GITHUB_TOKEN = 'offline-test'
    $script:cfg = [pscustomobject]@{GitHubOrg='offline-org';ProduktIds=[pscustomobject]@{GitHubSeats='G'};MonthsBack=1}
    $script:catalog = @([pscustomobject]@{produktId='U';datenquelle='GitHubAPI';abrechnungsart='Verbrauch';zuordnungsschluessel=[pscustomobject]@{githubSku='sku'}})
    $script:billingUris = @()
    function Invoke-Api {
      param($Uri,$Token,$ExtraHeaders)
      if ($Uri -like '*billing/seats*') { return [pscustomobject]@{total_seats=1;seats=@([pscustomobject]@{last_activity_at=(Get-Date).ToString('o')})} }
      $script:billingUris += $Uri
      $query = [uri]$Uri
      $year = [regex]::Match($query.Query,'year=(\d+)').Groups[1].Value
      $month = [regex]::Match($query.Query,'month=(\d+)').Groups[1].Value
      $date = '{0}-{1:D2}-01' -f [int]$year,[int]$month
      return [pscustomobject]@{usageItems=@(
        [pscustomobject]@{date=$date;product='copilot';sku='sku';quantity=1;netAmount=2},
        [pscustomobject]@{date=$date;product='copilot';sku='sku';quantity=3;netAmount=4}
      )}
    }
    $billed = @(Get-GitHubFacts)
    Assert ($script:billingUris.Count -eq 2 -and $script:billingUris[0] -match 'year=\d{4}&month=\d+$') 'GitHub requests every retained month with supported filters'
    $usage = @($billed | Where-Object produktId -eq U)
    Assert ($usage.Count -eq 2 -and @($usage | Where-Object { $_.menge -eq 4 -and $_.kostenIst -eq 6 -and $_.waehrung -eq 'USD' }).Count -eq 2) 'GitHub usage aggregated by month with USD actual costs'
  } finally { $env:FINOPS_GITHUB_TOKEN = $savedToken }

  # All catalog IDs are unique even if disabled (dashboard copies the whole file).
  @{produkte=@(@{produktId='same';aktiv=$true},@{produktId='SAME';aktiv=$false})} | ConvertTo-Json -Depth 5 | Set-Content $cat
  Assert-Throws { Get-Catalog $cat } 'disabled duplicate/case-only catalog ID rejected'

  $publishOut = New-Item (Join-Path $temp 'publish') -ItemType Directory
  $schemaCatalog = Join-Path $temp 'publish-catalog.json'
  '{"produkte":[]}' | Set-Content $schemaCatalog
  Publish-FactFiles -Facts @() -OutputPath $publishOut -CatalogPath $schemaCatalog -Delimiter ';'
  Assert ((Get-Content (Join-Path $publishOut 'facts.json') -Raw).Trim() -eq '[]') 'empty facts exported as JSON array'
  Assert ((Get-Content (Join-Path $publishOut 'facts.csv') -Raw).Contains('monat')) 'empty CSV retains schema headers'
  $oldJson = Get-Content (Join-Path $publishOut 'facts.json') -Raw
  $oldCsv = Get-Content (Join-Path $publishOut 'facts.csv') -Raw
  $script:publishMoves = 0
  function Move-Item {
    param($Path,$Destination,[switch]$Force)
    $script:publishMoves++
    if ($script:publishMoves -eq 2) { throw 'Simulated publication disk failure' }
    Microsoft.PowerShell.Management\Move-Item $Path $Destination -Force:$Force
  }
  Assert-Throws { Publish-FactFiles -Facts @((New-Fact -Monat $current -ProduktId P -Menge 1 -Quelle Graph)) -OutputPath $publishOut -CatalogPath $schemaCatalog -Delimiter ';' } 'publication failures are surfaced'
  Assert ((Get-Content (Join-Path $publishOut 'facts.json') -Raw) -eq $oldJson -and (Get-Content (Join-Path $publishOut 'facts.csv') -Raw) -eq $oldCsv) 'publication failure restores previous complete output files'
  Remove-Item Function:Move-Item
  $script:catalog = @([pscustomobject]@{produktId='A';datenquelle='AzureCostManagement';zuordnungsschluessel=[pscustomobject]@{azureMeterNameContains='AI[prod]'}})
  Assert ($null -ne (Find-AzureProduct -MeterCategory '' -MeterName 'x AI[prod] y' -ServiceName '')) 'Azure Contains mapping treats wildcard characters literally'
  $script:catalog += [pscustomobject]@{produktId='B';datenquelle='AzureCostManagement';zuordnungsschluessel=[pscustomobject]@{azureMeterCategory='AI'}}
  Assert-Throws { Find-AzureProduct -MeterCategory 'AI' -MeterName 'x AI[prod] y' -ServiceName '' } 'ambiguous Azure product mapping rejected'
  Write-Host "Collector offline regressions: $script:passed passed."
} finally { Remove-Item $temp -Recurse -Force }
