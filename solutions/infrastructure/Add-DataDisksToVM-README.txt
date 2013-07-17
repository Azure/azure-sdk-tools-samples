This sample creates a new Virtual Machine and adds one ore more data disks to it, or adds new disks to an existing VM.  The data disks will be formatted and have drive letters assigned.

Requirements:
- PowerShell Version 3.0
- Windows Azure PowerShell - June 2013

Cmdlets Used:
- Get-AzureVM
- Get-AzureCertificate
- Get-Item
- New-Object
- Set-AzureSubscription
- Select-AzureSubscription
- Get-AzureService
- New-AzureVMConfig
- Add-AzureProvisioningConfig
- Add-AzureDataDisk
- New-AzureVM
- Get-AzureWinRMUri
- Invoke-Command


