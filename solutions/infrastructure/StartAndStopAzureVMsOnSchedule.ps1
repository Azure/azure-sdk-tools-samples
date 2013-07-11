# Retrieve with Get-AzureSubscription.
$subscriptionName = "[MY SUBSCRIPTION]"

# The name of the scheduled tasks.  Make sure there's not already a scheduled task with these names.
$startTaskName = "[NAME OF SCHEDULED TASK TO START VMs]"
$stopTaskName = "[NAME OF SCHEDULED TASK TO START VMs]"

# The name of the VM(s) to start/stop on schedule.  Can be wildcard pattern
$vmName = "[VM NAME]"

# The service name that $vmName belongs to.
$serviceName = "[SERVICE NAME]"

# Select the correct subscription.
Select-AzureSubscription -SubscriptionName $subscriptionName

# Define a scheduled task to start the VM(s) on a schedule.
$startAzureVM = "Start-AzureVM -Name " + $vmName + " -ServiceName " + $serviceName
$startTaskTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Tuesday,Wednesday,Thursday -At 8AM
$startTaskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $startAzureVM
$startScheduledTask = New-ScheduledTask -Action $startTaskAction -Trigger $startTaskTrigger

# Define a scheduled task to stop the VM(s) on a schedule.
$stopAzureVM = "Stop-AzureVM -Name " + $vmName + " -ServiceName " + $serviceName + " -StayProvisioned -Force"
$stopTaskTrigger = New-ScheduledTaskTrigger -Daily -At 5:30PM
$stopTaskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $stopAzureVM
$stopScheduledTask = New-ScheduledTask -Action $stopTaskAction -Trigger $stopTaskTrigger

# Register the scheduled tasks to start and stop the VM(s).
Register-ScheduledTask -TaskName $startTaskName -InputObject $startScheduledTask
Register-ScheduledTask -TaskName $stopTaskName -InputObject $stopScheduledTask