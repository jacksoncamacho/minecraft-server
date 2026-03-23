# connect.ps1
# Connects to the Minecraft server via SSH

$domain = "seressa.bijadillo.com"
Write-Host "Connecting to $domain via SSH..." -ForegroundColor Cyan
ssh -i "$PSScriptRoot/seressa" -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL ubuntu@$domain
