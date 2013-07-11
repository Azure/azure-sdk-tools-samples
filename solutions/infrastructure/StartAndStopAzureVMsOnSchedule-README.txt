This sample demonstrates starting and stopping a single Virtual Machine or set of Virtual Machines (using a wildcard pattern) within a Cloud Service.  Additionally, it does this by creating scheduled tasks to start and stop the Virtual Machine(s) on a schedule.

For example, suppose you have a test machine or set of test machines that you want started every Tue-Thur at 8:00AM.  Suppose you also want the test machines turned off at 5:30PM, regardless of them being started manually or as a scheduled task.

***** NOTE *****
NOTE: Wildcard pattern support mentioned above is not released yet.  It will be part of the Start-AzureVM and Stop-AzureVM feautures, currently under code review.  See this commit for more details:
https://github.com/rickrain/azure-sdk-tools/commit/d7403c67e995d39cfdce8548ff57d8e1f9297ac2
****************

Requirements:
- PowerShell Version 3.0
- Windows Azure PowerShell - June 2013

Cmdlets Used:
- Select-AzureSubscription
- New-ScheduledTaskTrigger
- New-ScheduledTaskAction
- New-ScheduledTask
- Register-ScheduledTask
- Start-AzureVM
- Stop-AzureVM

