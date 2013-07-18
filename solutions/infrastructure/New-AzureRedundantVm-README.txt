This sample receives input a service name, a base computer name, an image name and the details of an endpoint. 
It then creates the number of VMs specified in the parameters, load balanced on the specified endpoint, 
and also creates direct ports.

Requirements:
- PowerShell Version 3.0
- Windows Azure PowerShell - June 2013

Cmdlets Used:
- Get-AzureAffinityGroup
- New-AzureAffinityGroup
- Get-AzureEndpoint
- Get-AzureOSDisk
- Get-Credential
- Add-AzureEndpoint
- New-AzureService
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


