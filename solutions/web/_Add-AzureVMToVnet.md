# Add-AzureVMToVNet #
## Description ##
Creates four Windows Server 2012 Virtual Machines across two separate cloud services and adds them to the same virtual network.

If the virtual network indicated does not exist then it is created.  The user is prompted for administrator credentials which can be used to logon to the virtual machines.
    
This script will produce two cloud services, <ServiceNamePrefix>-1 and <ServiceNamePrefix>-2.  Each cloud service will have two Virtual Machines, Host1 and Host2.  

## Scenario ##
You need multiple Virtual Machines spread across separate cloud services in the same Virtual Network.

## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013

## See Also ##
