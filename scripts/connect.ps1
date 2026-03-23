# connect.ps1
# Connects to the active Minecraft server console via AWS SSM Session Manager

Write-Host "Finding active Minecraft server..."
$instanceId = aws ec2 describe-instances --filters "Name=tag:Name,Values=minecraft-server" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text --no-cli-pager

if ($instanceId -eq "None" -or [string]::IsNullOrWhiteSpace($instanceId)) {
    Write-Host "ERROR: No active server found. It might be auto-shutdown or still starting up." -ForegroundColor Red
    exit 1
}

Write-Host "Connecting to instance $instanceId..."
Write-Host "Once connected, you can view live server logs by typing:"
Write-Host "  sudo journalctl -u minecraft -f" -ForegroundColor Cyan
Write-Host ""
aws ssm start-session --target $instanceId

# Note: This requires the 'Session Manager plugin for the AWS CLI' installed on your local machine.
# If it fails, please download it from AWS documentation.
