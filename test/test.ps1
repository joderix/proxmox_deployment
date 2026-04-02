#!/usr/bin/env pwsh
Set-Location -Path "C:\Users\John\projects\proxmox_deployment"
Write-Host "Testing container startup with entrypoint..."
docker compose run --rm deployer bash -c "echo 'Container started successfully!'; pwd; ls -l /entrypoint.sh"
Write-Host "Test complete. Exit code: $LASTEXITCODE"
