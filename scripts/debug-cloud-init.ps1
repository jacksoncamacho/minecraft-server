# debug-cloud-init.ps1
$instanceId = "i-0163b75d2d7f74d5e"
Write-Host "Instance ID: $instanceId"

if ($instanceId -ne "None" -and -not [string]::IsNullOrWhiteSpace($instanceId)) {
    $cmdId = & "C:\Program Files\Amazon\AWSCLIV2\aws.exe" ssm send-command --region us-east-1 --document-name "AWS-RunShellScript" --targets "Key=instanceids,Values=$instanceId" --parameters 'commands=["cat /var/log/cloud-init-output.log | tail -n 80", "ls -l /opt/minecraft"]' --query "Command.CommandId" --output text --no-cli-pager
    Start-Sleep -Seconds 4
    & "C:\Program Files\Amazon\AWSCLIV2\aws.exe" ssm get-command-invocation --region us-east-1 --command-id $cmdId --instance-id $instanceId --query "StandardOutputContent" --output text --no-cli-pager
} else {
    Write-Host "Instance not found"
}
