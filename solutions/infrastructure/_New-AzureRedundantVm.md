# New-AzureRedundantVm#
## Description ##
Deploy a specified number of Virtual Machines based on a given image name.  The Virtual Machines are placed in the same availability set and load balanced on a given endpoint name.

If the cloud service name already exists, then subsequent call will adds new Virtual Machine instances.
## Scenario ##
You need to create a farm of Virtual Machines using a standard disk image and have all instances load balanced.
## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013

## See Also ##
- Get-AzureVMImage