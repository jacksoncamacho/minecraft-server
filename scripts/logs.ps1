# logs.ps1
# Fetches recent logs from the Minecraft server via SSH

$domain = "seressa.bijadillo.com"
Write-Host "Fetching the last 100 lines of the server log from $domain..." -ForegroundColor Cyan
ssh -i seressa ubuntu@$domain "sudo journalctl -u minecraft -n 100 --no-pager"
