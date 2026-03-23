# logs.ps1
# Fetches recent logs from the active Minecraft server

Write-Host "Finding active Minecraft server..."
$instanceId = aws ec2 describe-instances --filters "Name=tag:Name,Values=minecraft-server" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text --no-cli-pager

if ($instanceId -eq "None" -or [string]::IsNullOrWhiteSpace($instanceId)) {
    Write-Host "ERROR: No active server found. It might be auto-shutdown or still starting up." -ForegroundColor Red
    exit 1
}

Write-Host "Fetching the last 100 lines of the server log (this takes ~5 seconds)..."

$cmdId = aws ssm send-command --document-name "AWS-RunShellScript" --targets "Key=instanceids,Values=$instanceId" --parameters 'commands=["tail -n 100 /opt/minecraft/logs/latest.log"]' --query "Command.CommandId" --output text --no-cli-pager

if ([string]::IsNullOrWhiteSpace($cmdId)) {
    Write-Host "Failed to send command to SSM." -ForegroundColor Red
    exit 1
}

Start-Sleep -Seconds 5

aws ssm get-command-invocation --command-id $cmdId --instance-id $instanceId --query "StandardOutputContent" --output text --no-cli-pager
