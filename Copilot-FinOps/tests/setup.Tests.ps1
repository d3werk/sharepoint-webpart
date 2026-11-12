# Offline setup/configuration regressions; no Azure account, modules or Pester.
# Run: pwsh -NoProfile -File tests/setup.Tests.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$setup = Join-Path $root '03_Collector/Einrichten-CopilotFinOps.ps1'
$collector = Join-Path $root '03_Collector/Collect-CopilotCosts.ps1'
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
$temp = Join-Path ([IO.Path]::GetTempPath()) ('finops-setup-' + [guid]::NewGuid())
New-Item $temp -ItemType Directory | Out-Null
$tenant = '11111111-1111-1111-1111-111111111111'
$client = '22222222-2222-2222-2222-222222222222'
$subA = '33333333-3333-3333-3333-333333333333'
$subB = '44444444-4444-4444-4444-444444444444'
$thumb = 'A' * 40
try {
  function Connect-AzAccount { throw 'Unexpected sign-in in offline test' }
  $whatIf = Join-Path $temp 'not-created/config.json'
  & $setup -ConfigPath $whatIf -Sources Azure -AzureMode Query -DiscoverAzure -NonInteractive -WhatIf
  Assert (-not (Test-Path (Split-Path $whatIf))) 'WhatIf creates no directories or files and never signs in'
  $config = Join-Path $temp 'config.json'
  & $setup -ConfigPath $config -Sources PPAC -NonInteractive
  $cfg = Get-Content $config -Raw | ConvertFrom-Json -AsHashtable
  Assert ($cfg.EnabledSources.Count -eq 1 -and $cfg.EnabledSources[0] -eq 'PPAC' -and -not $cfg.TenantId) 'CSV setup works without credentials or Azure modules'
  Assert ($cfg.PpacColumnMap.Credits -eq 'Credits' -and $cfg.ProduktIds.PremiumLizenz -eq 'M365-COPILOT') 'new config contains runnable defaults and product mappings'
  $cfg.Custom = @{Keep=@(1,2,3);Nested=@{Text='unverändert'}}
  $cfg.PpacColumnMap.Date = 'Buchungsdatum'
  $cfg.PpacColumnMap.Credits = ''
  $cfg | ConvertTo-Json -Depth 20 | Set-Content $config
  $before = Get-Content $config -Raw
  & $setup -ConfigPath $config -Sources PPAC -NonInteractive
  $backups = @(Get-ChildItem $temp -Filter 'config.json.*.bak')
  $cfg = Get-Content $config -Raw | ConvertFrom-Json -AsHashtable
  Assert ($backups.Count -eq 1 -and (Get-Content $backups[0].FullName -Raw) -ceq $before) 'overwrite keeps exact previous file in a dated backup'
  Assert ($cfg.Custom.Nested.Text -eq 'unverändert' -and $cfg.Custom.Keep.Count -eq 3) 'unknown nested settings survive setup'
  Assert ($cfg.PpacColumnMap.Date -eq 'Buchungsdatum' -and $cfg.PpacColumnMap.Credits -eq 'Credits') 'explicit PPAC columns preserved while empty legacy defaults repaired'
  $cfg.MonthsBack = 1.5
  $cfg | ConvertTo-Json -Depth 20 | Set-Content $config
  $before = Get-Content $config -Raw
  Assert-Throws { & $setup -ConfigPath $config -Sources PPAC -NonInteractive } 'setup rejects invalid retained settings using Collector validation'
  Assert ((Get-Content $config -Raw) -ceq $before -and @(Get-ChildItem $temp -Filter 'config.json.*.bak').Count -eq 1) 'failed validation leaves original file and backups unchanged'
  Assert (@(Get-ChildItem $temp -Filter '.config-*.tmp').Count -eq 0) 'staging removed after failed validation'
  Assert-Throws { & $setup -ConfigPath $config -Sources @() -NonInteractive } 'explicit empty source selection rejected'
  $cfg.MonthsBack = 12
  $cfg | ConvertTo-Json -Depth 20 | Set-Content $config
  $queryConfig = Join-Path $temp 'query.json'
  & $setup -ConfigPath $queryConfig -Sources Azure -AzureMode Query -TenantId $tenant -ClientId $client -CertificateThumbprint ('aa:' * 19 + 'aa') -SubscriptionIds $subA,$subA.ToUpperInvariant() -CostCenterTag 'Kostenstelle' -NonInteractive
  $query = Get-Content $queryConfig -Raw | ConvertFrom-Json -AsHashtable
  Assert ($query.AzureScopes.Count -eq 1 -and $query.AzureScopes[0] -eq "/subscriptions/$subA") 'manual query setup normalizes and deduplicates subscription IDs'
  Assert ($query.CertificateThumbprint -ceq $thumb) 'certificate fingerprint normalized consistently with browser'
  & $collector -ConfigPath $queryConfig -ValidateOnly
  Assert (-not (Test-Path (Join-Path $temp '../06_Daten/out'))) 'ValidateOnly does not collect, sign in, or create output directories'
  $query.CostApiVersion = '2023-11-01-preview'
  $query | ConvertTo-Json -Depth 20 | Set-Content $queryConfig
  & $collector -ConfigPath $queryConfig -ValidateOnly
  Assert $true 'valid preview API dates remain supported'
  $query.CostApiVersion = '2023-02-30'
  $query | ConvertTo-Json -Depth 20 | Set-Content $queryConfig
  Assert-Throws { & $collector -ConfigPath $queryConfig -ValidateOnly } 'impossible API calendar date rejected'
  $query.CostApiVersion = '2023-11-01'
  $query.AzureScopes = @()
  $query | ConvertTo-Json -Depth 20 | Set-Content $queryConfig
  Assert-Throws { & $collector -ConfigPath $queryConfig -ValidateOnly } 'empty Azure scopes cannot silently publish empty query costs'
  $query.AzureScopes = @("/subscriptions/$subA","/subscriptions/$subA")
  $query | ConvertTo-Json -Depth 20 | Set-Content $queryConfig
  Assert-Throws { & $collector -ConfigPath $queryConfig -ValidateOnly } 'duplicate Azure scopes cannot double costs'
  $query.AzureScopes = @("/subscriptions/$subA")
  $query.ClientId = 'object-name-instead-of-guid'
  $query | ConvertTo-Json -Depth 20 | Set-Content $queryConfig
  Assert-Throws { & $collector -ConfigPath $queryConfig -ValidateOnly } 'malformed app ID rejected before authentication'
  $query.ClientId = $client
  $query | ConvertTo-Json -Depth 20 | Set-Content $queryConfig
  $probe = @{Tenant=$null;Count=0}
  function Get-Module { param($ListAvailable); [pscustomobject]@{Name='Az.Accounts'} }
  function Import-Module { param($Name,$ErrorAction) }
  function Connect-AzAccount {
    param($Scope,[switch]$SkipContextPopulation,[switch]$AllowNoSubscriptions,$ErrorAction,$Tenant)
    $probe.Tenant = $Tenant; $probe.Count++
  }
  function Get-AzContext { param($ErrorAction); [pscustomobject]@{Tenant=[pscustomobject]@{Id=$tenant}} }
  function Get-AzSubscription {
    param($TenantId,$ErrorAction)
    [pscustomobject]@{Id=$subA;Name='A';State='Enabled'}
    [pscustomobject]@{Id=$subB;Name='B';State='Enabled'}
  }
  & $setup -ConfigPath $queryConfig -Sources Azure -AzureMode Query -DiscoverAzure -SubscriptionIds $subB -NonInteractive
  $discovered = Get-Content $queryConfig -Raw | ConvertFrom-Json -AsHashtable
  Assert ($probe.Tenant -eq $tenant -and $discovered.TenantId -eq $tenant) 'discovery explicitly uses retained tenant instead of another home tenant'
  Assert ($discovered.AzureScopes.Count -eq 1 -and $discovered.AzureScopes[0] -eq "/subscriptions/$subB") 'discovery saves only explicitly chosen visible subscription'
  $before = Get-Content $queryConfig -Raw
  Assert-Throws { & $setup -ConfigPath $queryConfig -Sources Azure -AzureMode Query -DiscoverAzure -NonInteractive } 'noninteractive discovery never selects all subscriptions implicitly'
  Assert ((Get-Content $queryConfig -Raw) -ceq $before) 'missing subscription selection leaves prior config unchanged'
  Assert-Throws { & $setup -ConfigPath $queryConfig -Sources Azure -AzureMode Query -DiscoverAzure -SubscriptionIds '55555555-5555-5555-5555-555555555555' -NonInteractive } 'subscription outside visible tenant rejected'
  function Get-AzContext { param($ErrorAction); [pscustomobject]@{Tenant=[pscustomobject]@{Id='66666666-6666-6666-6666-666666666666'}} }
  Assert-Throws { & $setup -ConfigPath $queryConfig -Sources Azure -AzureMode Query -DiscoverAzure -SubscriptionIds $subA -NonInteractive } 'unexpected tenant switch rejected before preserving unrelated app credentials'
  Write-Host "Setup offline regressions: $script:passed passed."
} finally { Remove-Item $temp -Recurse -Force }
