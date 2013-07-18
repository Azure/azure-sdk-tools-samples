This sample receives input a service name, a base computer name, an image name and the details of an endpoint. 
It then creates the number of VMs specified in the parameters, load balanced on the specified endpoint, 
and also creates direct ports.

Requirements:
- PowerShell Version 3.0
- Windows Azure PowerShell - June 2013

Cmdlets Used:
- Add-AzureEndpoint
- Add-AzureProvisioningConfig
- ForEach-Object
- Get-AzureAffinityGroup
- Get-AzureEndpoint
- Get-AzureOSDisk
- Get-AzureService
- Get-AzureVM
- Get-AzureVMImage
- Get-Credential
- New-AzureAffinityGroup
- New-AzureService
- New-AzureVM
- New-AzureVMConfig
- Out-Null
- Set-AzureSubscription
- Set-StrictMode
- Sort-Object
- Start-Job
- Start-Sleep
- Wait-Job
- Write-Verbose
- Write-Warning