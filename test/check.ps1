#!/usr/bin/env pwsh
Set-Location -Path "C:\Users\John\projects\proxmox_deployment"
Write-Host "Checking if /entrypoint.sh exists in container..."
docker compose run --rm --entrypoint /bin/bash deployer -c "test -f /entrypoint.sh && echo 'File exists' || echo 'File does NOT exist'; ls -la / | grep entrypoint"
Write-Host "Exit code: $LASTEXITCODE"
