# New-AzureMongoDbApp #
## Description ##
Creates two virtual machines; a front-end Windows Server and a back-end MongoDB server.  

The front-end server is configured with the Web Platform Installer, which is then used to install IIS.

The back-end MongoDB server is configured with two additional data disk; one for data and another for log files.
    
Both Virtual Machines are placed in a single subnet.
## Scenario ##
You need to create an environment with and IIS front-end server and a MongoDB back-end server.
## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013

## See Also ##
- Get-AzureVMImage