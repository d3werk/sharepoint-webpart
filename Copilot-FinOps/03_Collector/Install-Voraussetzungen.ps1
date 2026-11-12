#Requires -Version 7.2
<#
.SYNOPSIS
  Prüft und installiert die Voraussetzungen für die aktivierten Datenquellen.
  CSV-Importe benötigen weder Az.Accounts noch ein Tenant-Zertifikat.
#>
$ErrorActionPreference = 'Stop'
Write-Host "PowerShell-Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
$cfgPath = Join-Path $PSScriptRoot '../02_Konfiguration/config.json'
if (-not (Test-Path $cfgPath -PathType Leaf)) { throw 'config.json fehlt. Zuerst die Konfiguration erstellen.' }
$cfg = Get-Content $cfgPath -Raw -Encoding utf8 | ConvertFrom-Json
$needsTenant = $cfg.EnabledSources -contains 'Graph' -or ($cfg.EnabledSources -contains 'Azure' -and $cfg.AzureMode -eq 'Query')
if (-not $needsTenant) {
  Write-Host 'Aktivierte Quellen benötigen keine Az-Anmeldung. Keine zusätzlichen Module erforderlich.' -ForegroundColor Green
  return
}
if (-not $IsWindows) { throw 'Die Zertifikatsanmeldung über Cert: benötigt Windows. Offline-CSV-Importe funktionieren auch auf Linux/macOS.' }
if (-not (Get-Module -ListAvailable Az.Accounts)) {
  Write-Host 'Installiere Modul Az.Accounts für den aktuellen Benutzer …'
  Install-Module Az.Accounts -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
} else { Write-Host 'Az.Accounts ist vorhanden.' -ForegroundColor Green }
$t = $cfg.CertificateThumbprint
if (-not $t -or $t -match '[<>]') { throw 'CertificateThumbprint fehlt oder enthält einen Platzhalter.' }
$c = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object Thumbprint -eq $t | Select-Object -First 1
if (-not $c) { throw "Zertifikat '$t' nicht im Speicher dieses Kontos gefunden." }
if (-not $c.HasPrivateKey) { throw "Zertifikat '$t' gefunden, aber ohne privaten Schlüssel." }
if ($c.NotAfter -le (Get-Date) -or $c.NotBefore -gt (Get-Date)) { throw "Zertifikat '$t' ist noch nicht oder nicht mehr gültig." }
Write-Host "Zertifikat gefunden (mit privatem Schlüssel), gültig bis $($c.NotAfter)." -ForegroundColor Green
