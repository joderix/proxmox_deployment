#!/usr/bin/env pwsh
Set-Location -Path "C:\Users\John\projects\proxmox_deployment"
Write-Host "Testing container startup..."
docker compose run --rm deployer bash -c "echo 'SUCCESS: Container started!'; pwd"
Write-Host "Exit code: $LASTEXITCODE"
