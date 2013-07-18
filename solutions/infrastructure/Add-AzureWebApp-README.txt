This sample creates two virtual machines, a front end based on the latest Windows Server 2012 stock image, and installs the given WebPI application.
It also creates a SQL server machine, and modifies the SQL server installation on it to accept mixed mode authentication. Both of the machines are 
placed in a subnet.

Requirements:
- PowerShell Version 3.0
- Windows Azure PowerShell - June 2013

Cmdlets Used:
- Add-AzureEndpoint
- Add-AzureProvisioningConfig
- Add-Windowsfeature
- Get-AzureAffinityGroup
- Get-AzureCertificate
- Get-AzureVM
- Get-AzureVMImage
- Get-AzureVNetConfig
- Get-AzureVNetSite
- Get-AzureWinRMUri
- Get-Credential
- Get-Item
- Get-Service
- Import-Module
- Invoke-Command
- New-AzureAffinityGroup
- New-AzureAffinityGroupIfNotExists
- New-AzureVM
- New-AzureVMConfig
- New-Item
- New-Object
- New-PSSession
- Out-Null
- Remove-Item
- Remove-PSSession
- Send-File
- Set-AzureSubnet
- Set-AzureSubscription
- Set-AzureVNetConfig
- Set-ExecutionPolicy
- Set-StrictMode
- Sort-Object
- Split-Path
- Test-AzureName
- Test-Path
- Where-Object
- Write-Progress
- Write-Verbose
- Write-Warning