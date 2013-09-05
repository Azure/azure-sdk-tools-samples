# Start-AzureVMsOnSchedule#
## Description ##
Demonstrates starting a single Virtual Machine or set of Virtual Machines (using a wildcard pattern) within a Cloud Service.  It does this by creating scheduled tasks to start the Virtual Machine(s) on a schedule at the time specified.
## Scenario ##
Suppose you have a test machine or set of test machines that you want started every Tue-Thur at 8:00AM.  This script will register the scheduled task to start the virtual machines you specify.
## Requirements ##

- PowerShell Version 0.6.19
- Windows Azure PowerShell July 2013

## See Also ##
- Stop-AzureVMsOnSchedule
