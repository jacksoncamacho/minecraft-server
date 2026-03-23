$instanceId = (& "C:\Program Files\Amazon\AWSCLIV2\aws.exe" ec2 describe-instances --region us-east-1 --filters "Name=tag:Name,Values=minecraft-server" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text --no-cli-pager).Trim()
Write-Host "Instance ID is: $instanceId"
$cmdId = (& "C:\Program Files\Amazon\AWSCLIV2\aws.exe" ssm send-command --region us-east-1 --document-name "AWS-RunShellScript" --targets "Key=instanceids,Values=$instanceId" --parameters commands="tail -n 100 /var/log/cloud-init-output.log" --query "Command.CommandId" --output text --no-cli-pager).Trim()
Write-Host "Command ID is: $cmdId"
Start-Sleep -Seconds 5
& "C:\Program Files\Amazon\AWSCLIV2\aws.exe" ssm get-command-invocation --region us-east-1 --command-id $cmdId --instance-id $instanceId --query "StandardOutputContent" --output text --no-cli-pager
