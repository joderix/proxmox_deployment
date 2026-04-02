#!/usr/bin/env pwsh
Set-Location -Path "C:\Users\John\projects\proxmox_deployment"
Write-Host "Building Docker image with no cache..."
docker compose build --no-cache
Write-Host "Build complete. Exit code: $LASTEXITCODE"
