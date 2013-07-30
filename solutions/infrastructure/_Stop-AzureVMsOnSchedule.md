# Stop-AzureVMsOnSchedule#
## Description ##
Demonstrates stopping a single Virtual Machine or set of Virtual Machines (using a wildcard pattern) within a Cloud Service.  It does this by creating scheduled tasks to stop the Virtual Machine(s) on a schedule at the time specified.
## Scenario ##
Suppose you have a test machine or set of test machines that you want turned off everyday at 5:30PM.  This script will register the scheduled task to stop the virtual machines you specify.
## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell July 2013

## See Also ##
- Start-AzureVMsOnSchedule