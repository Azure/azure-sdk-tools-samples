# Add-AzureWebApp#
## Description ##
Creates two virtual machines; a front-end Windows Server and a back-end SQL server.  

The front-end server is configured with the Web Platform Installer, which is then used to install an application published on the Web Platform Installer catalog.

The back-end SQL server is configured with "Mixed" mode authentication and a Firewall rule for remote access.
    
Both Virtual Machines are placed in a single subnet.
## Scenario ##
You need to create an environment that pre-installs an application from the Web Platfom Installer (for example, Blogengine.net) and connect the Virtual Machine to a new SQL server instance.
## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013

## See Also ##
- RemoteScripts.ps1
- BlogengineNet.app