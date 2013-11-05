# CreateSharePointDeveloperMachineInDomain #

## Description ##
Create a new Virtual Machine for SharePoint development in the specified domain based on Visual Studio 2013 image. 
The script configures SQL Server Database Engine, Reporting Service, Analysis Service, Integration Service, Agent Service and create a defulat instance (MSSQLSERVER).
The script also configures the following SharePoint environment in the Virtual Machine.
    - SharePoint configuration database: "SP2013_Configuration".
    - SharePoint Central Administration content database: "SP2013_Content_CentralAdministration" Central Administration Port: 11111 Central Administration Authentication: NTLM.
    - Web Application "Developer Test Site" on port 80 with default authentication provider. Using default app pool running under ¨ClocalSPFarmAccountName identity.
    - Root site collection "Developer Test Site Collection" Based on team site template. Primary site collection owner is the logged on user.
    
Before executing, follow the steps to enable CredSSP on the client machine for delegation.
    - Run Set-WSManQuickConfig to make sure WinRM service is running.
    - Run Enable-WSManCredSSP -Role Client -DelegateComputer "*.cloudapp.net" Note: This command will fail if your client machine is connected to any networks defined as "Public network" in "Network and Sharing Center." 
    - Enable delegating of fresh credentials using group policy editor on your client machine. Run gpedit.msc -> Computer Configuration -> Administrative Templates -> System -> Credentials Delegation and then change the state of "Allow Delegating Fresh Credentials with NTLM-only server authentication" to "Enabled."(Its default state will say, "Not configured.") In the Add Servers sections add : WSMAN/*.cloudapp.net. Click here for more details on enabling CredSSP.

The script must be executed with elevated privileges.
    
## Scenario ##
You want to create a development environment for SharePoint 2013 development in a domain.

## Requirements ##
- Your subscription account needs to be MSDN subscriber to access the Visual Studio 2013 image.
- PowerShell Version 3.0
- Windows Azure PowerShell August 2013

## See Also ##
- CreateWebSQLDeveloperMachine.ps1
- CreateSharePointDeveloperMachine.ps1

