# connect.ps1
# Connects to the Minecraft server via SSH

$ip = "100.52.134.220"
Write-Host "Connecting to $ip via SSH..." -ForegroundColor Cyan
ssh -i "$PSScriptRoot/seressa" -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL ubuntu@$ip
