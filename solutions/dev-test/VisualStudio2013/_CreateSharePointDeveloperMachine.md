# CreateSharePointDeveloperMachine #

## Description ##
Create a new Virtual Machine for SharePoint development based on Visual Studio 2013 image. 
The script configures SQL Server Database Engine, Reporting Service, Analysis Service, Integration Service, Agent Service and create a defulat instance (MSSQLSERVER).
The script also configures the following SharePoint environment in the Virtual Machine.
    - SharePoint configuration database: "SP2013_Configuration".
    - SharePoint Central Administration content database: "SP2013_Content_CentralAdministration" Central Administration Port: 11111 Central Administration Authentication: NTLM.
    - Web Application "Developer Test Site" on port 80 with default authentication provider. Using default app pool running under ¨ClocalSPFarmAccountName identity.
    - Root site collection "Developer Test Site Collection" Based on team site template. Primary site collection owner is the logged on user.

The script must be executed with elevated privileges.
    
## Scenario ##
You want to create a development environment for SharePoint 2013 development on an Azure Virtual Machine.

## Requirements ##
- Your subscription account needs to be MSDN subscriber to access the Visual Studio 2013 image.
- PowerShell Version 3.0
- Windows Azure PowerShell August 2013

## See Also ##
- CreateWebSQLDeveloperMachine.ps1
- CreateSharePointDeveloperMachineInDomain.ps1

