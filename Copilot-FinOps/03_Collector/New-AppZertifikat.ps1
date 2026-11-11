#Requires -Version 7.2
<#
.SYNOPSIS
  Erstellt ein selbstsigniertes Zertifikat für die App-Registrierung und exportiert
  ausschließlich den öffentlichen Teil (.cer) zum Hochladen in Entra ID.
.NOTES
  Unter dem Konto ausführen, unter dem der Collector später läuft.
  Für Produktion ist ein Zertifikat aus Unternehmens-PKI oder Key Vault vorzuziehen.
#>
[CmdletBinding()]
param(
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_. -]{0,79}$')][string]$Name = 'Copilot-FinOps-Collector',
  [ValidateRange(1,60)][int]$GueltigMonate = 12
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or -not (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
  throw 'Die Zertifikatserstellung benötigt Windows mit dem PKI-Modul.'
}
$out = Join-Path $PSScriptRoot "$Name.cer"
if (Test-Path $out) { throw "Datei existiert bereits: $out. Einen anderen Namen verwenden oder die Datei zuerst sichern." }
$cert = New-SelfSignedCertificate -Subject "CN=$Name" -CertStoreLocation Cert:\CurrentUser\My `
  -KeyExportPolicy NonExportable -KeySpec Signature -KeyLength 2048 -HashAlgorithm SHA256 -NotAfter (Get-Date).AddMonths($GueltigMonate)
Export-Certificate -Cert $cert -FilePath $out -NoClobber | Out-Null
Write-Host "Zertifikat erstellt. Fingerabdruck (für config.json): $($cert.Thumbprint)" -ForegroundColor Green
Write-Host "Öffentlicher Schlüssel zum Hochladen in Entra ID: $out"
