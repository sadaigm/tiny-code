# Tiny Code native installer (Windows)
# Usage: irm https://raw.githubusercontent.com/sadaigm/tiny-code/main/install.ps1 | iex
$ErrorActionPreference = 'Stop'

$repo = 'sadaigm/tiny-code'
$url = "https://github.com/$repo/releases/latest/download/TinyCode-Setup-windows-x64.exe"
$dest = Join-Path $env:TEMP 'TinyCode-Setup.exe'

Write-Host "Downloading $url"
try {
  Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
} catch {
  Write-Error "could not download TinyCode-Setup-windows-x64.exe: $_"
  exit 1
}

Write-Host 'Running installer (silent)...'
$proc = Start-Process -FilePath $dest -ArgumentList '/VERYSILENT', '/NORESTART' -Wait -PassThru
if ($proc.ExitCode -ne 0) {
  Write-Error "installer exited with code $($proc.ExitCode)"
  exit 1
}

Write-Host 'Installed Tiny Code.'
