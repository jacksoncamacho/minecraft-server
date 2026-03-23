# connect.ps1
# Connects to the Minecraft server via SSH

$domain = "seressa.bijadillo.com"
Write-Host "Connecting to $domain via SSH..." -ForegroundColor Cyan
ssh -i seressa ubuntu@$domain
