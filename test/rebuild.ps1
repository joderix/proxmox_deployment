#!/usr/bin/env pwsh
Set-Location -Path "C:\Users\John\projects\proxmox_deployment"
Write-Host "Rebuilding Docker image with printf approach..."
$output = docker compose build --no-cache 2>&1
$lines = @($output) -split "`n"
Write-Host ($lines[(-30)..(-1)] | Out-String)
Write-Host "Build complete. Exit code: $LASTEXITCODE"
