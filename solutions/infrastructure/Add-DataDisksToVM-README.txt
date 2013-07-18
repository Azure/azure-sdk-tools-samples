This sample creates two virtual machines, a front end based on the latest Windows Server 2012 stock image, and installs the given WebPI application.
It also creates a SQL server machine, and modifies the SQL server installation on it to accept mixed mode authentication. Both of the machines are 
placed in a subnet.

Requirements:
- PowerShell Version 3.0
- Windows Azure PowerShell - June 2013

Cmdlets Used:
- Add-AzureDataDisk
- Add-AzureProvisioningConfig
- Format-Volume
- Get-AzureCertificate
- Get-AzureDataDisk
- Get-AzureService
- Get-AzureVM
- Get-AzureVMImage
- Get-AzureWinRMUri
- Get-Credential
- Get-Disk
- Get-Item
- Initialize-Disk
- Invoke-Command
- New-AzureService
- New-AzureVM
- New-AzureVMConfig
- New-Object
- New-Partition
- Set-AzureSubscription
- Set-StrictMode
- Update-AzureVM
- Where-Object
- Write-Verbose
- Write-Warning