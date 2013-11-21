<#
    Copyright (c) Microsoft Corporation. All rights reserved.
    THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
    ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
    IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
    PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
#>

<#
.SYNOPSIS
    Create a new Virtual Machine for SharePoint development.
.DESCRIPTION
    Create a new Virtual Machine for SharePoint development based on Visual Studio 2013 image. 
    The script configures SQL Server Database Engine, Reporting Service, Analysis Service, Integration Service, Agent Service and create a defulat instance (MSSQLSERVER).
    The script also configures the following SharePoint environment in the Virtual Machine.
    - SharePoint configuration database: "SP2013_Configuration".
    - SharePoint Central Administration content database: "SP2013_Content_CentralAdministration" Central Administration Port: 11111 Central Administration Authentication: NTLM.
    - Web Application "Developer Test Site" on port 80 with default authentication provider. Using default app pool running under –localSPFarmAccountName identity.
    - Root site collection "Developer Test Site Collection" Based on team site template. Primary site collection owner is the logged on user.

    The script must be executed with elevated privileges.
.EXAMPLE
    .\CreateSharePointDeveloperMachine.ps1 -imageName "03f55de797f546a1b29d1b8d66be687a__Visual-Studio-2013-Ultimate-12.0.21005.1-AzureSDK-2.2" -azurePublishSettingsFile "C:\Sample\Sample.publishsettings" -subscriptionName "SampleSub" -storageAccountName "samplestorage" -vmName “samplespdev" -vmSize "ExtraLarge" -adminUserName "SampleUser1" -adminUserPassword "Pass@word1" -localSPFarmAccountName "sp_farm" -localSPFarmAccountPassword "Pass@word1"
    .\CreateSharePointDeveloperMachine.ps1 -imageName "03f55de797f546a1b29d1b8d66be687a__Visual-Studio-2013-Ultimate-12.0.21005.1-AzureSDK-2.2" -azurePublishSettingsFile "C:\Sample\Sample.publishsettings" -subscriptionName "SampleSub" -storageAccountName "samplestorage" -vmName “samplespdev" -vmSize "ExtraLarge" -adminUserName "SampleUser1" -adminUserPassword "Pass@word1" -localSPFarmAccountName "sp_farm" -localSPFarmAccountPassword "Pass@word1" -vnetName "VNet1" -subnetNames "Subnet1"
#>

Param(
    # The name of the Visual Studio 2013 image
    [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
    [string]$imageName, 

    # The path of the Azure Publish Settings file
    [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$false)]
    [string]$azurePublishSettingsFile, 

    # The name of the subscription
    [Parameter(Mandatory=$true, Position=2, ValueFromPipeline=$false)]
    [string]$subscriptionName, 

    # The name of the Storage Account which will be used to store the Virtual Machine. Please note the script will not create a storage account
    [Parameter(Mandatory=$true, Position=3, ValueFromPipeline=$false)]
    [string]$storageAccountName, 

    # The name of the Virtual Machine. The name will also be used as the Cloud Service name that will be created
    [Parameter(Mandatory=$true, Position=4, ValueFromPipeline=$false)]
    [string]$vmName, 

    # The size of the Virtual Machine
    [Parameter(Mandatory=$true, Position=5, ValueFromPipeline=$false)]
    [string]$vmSize, 

    # The name of the admin account that you will use to connect to the machine
    [Parameter(Mandatory=$true, Position=6, ValueFromPipeline=$false)]
    [string]$adminUserName, 

    # The password of the admin account
    [Parameter(Mandatory=$true, Position=7, ValueFromPipeline=$false)]
    [string]$adminUserPassword,

    # The name of the SharePoint Farm local account
    [Parameter(Mandatory=$true, Position=8, ValueFromPipeline=$false)]
    [string]$localSPFarmAccountName,

    # The password of the SharePoint Farm local account
    [Parameter(Mandatory=$true, Position=9, ValueFromPipeline=$false)]
    [string]$localSPFarmAccountPassword,

    # The name of the Virtual Network the Virtual Machine should be provisioned into. The Virtual Network needs to be in the same location as the storage account. Please note that this will not create a Virtual Network
    [Parameter(Mandatory=$false, Position=10, ValueFromPipeline=$false)]
    [string]$vnetName,

    # The subnet names of the Virtual Network the Virtual Machine should be provisioned into
    [Parameter(Mandatory=$false, Position=11, ValueFromPipeline=$false)]
    [string[]]$subnetNames
    )

<#
.SYNOPSIS
    Remove the specified Cloud Service and clean up the deployments under it.
.DESCRIPTION
    Remove the specified Cloud Service and clean up the deployments under it.
.INPUTS
    $serviceName - The Cloud Service name.
.OUTPUTS
    None.
#>

function CleanupCloudService
{
    param(
        # The Cloud Service Name
        [string]$serviceName
        )

    $slots = @("Staging", "Production")

    foreach($slot in $slots)
    {       
	    $deployment = Get-AzureDeployment -Slot $slot -ServiceName $serviceName -ErrorAction Ignore

	    if($deployment -ne $null)
	    {
		    $machines = Get-AzureVM -ServiceName $serviceName -ErrorAction Ignore
						    
		    if($machines -ne $null)
		    {
			    foreach($machine in $machines)
			    {
				    Write-Host "$(Get-Date): Start to remove virtual machine $($machine.Name)." 
				    Remove-AzureVM -Name $machine.Name -ServiceName $serviceName							
			    }
		    }
            else
            {									
		        Write-Host "$(Get-Date): Start to remove deployment $($deployment.Name)." 
                Remove-AzureDeployment -ServiceName $serviceName -Slot $slot -Force		
            }		
	    }
    }
		
    Write-Host "$(Get-Date): Start to remove cloud service $serviceName." 
    Remove-AzureService -ServiceName $serviceName -Force
}

<#
.SYNOPSIS
    Create a new Virtual Machine.
.DESCRIPTION
    Create a new Virtual Machine. If there exits a Cloud Service with the same name, it will be removed along with its deployments.
.INPUTS
    $imageName - The name of the base Virtual Machine image.
    $storageAccountName - The name of the Storage Account which will be used to store the Virtual Machine.
    $serviceName - The name of the Cloud Service for the Virtual Machine.
    $vmName - The name of the Virtual Machine.
    $vmSize - The size of the Virtual Machine.
    $adminUserName - The name of the admin account.
    $adminUserPassword - The password of the admin account.
    $vnetName - The name of the Virtual Network.
    $subnetNames - The subnet names of the Virtual Network. 
.OUTPUTS
    None.
#>

function CreateVirtualMachine
{
    param(
        # The name of the base Virtual Machine image
        [string]$imageName,
         
        # The name of the Storage Account which will be used to store the Virtual Machine
        [string]$storageAccountName, 

        # The name of the Cloud Service for the Virtual Machine
        [string]$serviceName, 

        # The name of the Virtual Machine
        [string]$vmName, 

        # The size of the Virtual Machine
        [string]$vmSize, 

        # The name of the admin account
        [string]$adminUserName, 

        # The password of the admin account
        [string]$adminUserPassword, 

        # The name of the Virtual Network
        [string]$vnetName,

        # The subnet names of the Virtual Network 
        [string[]]$subnetNames
        )

    # Check if the image exists
    $image = Get-AzureVMImage -ImageName $imageName
    if(!$image)
    {
        Write-Host "$(Get-Date): $imageName doesn't exist."
        return
    }

    $storageAccount = Get-AzureStorageAccount -StorageAccountName $storageAccountName
    if(!$storageAccount)
    {
        Write-Host "$(Get-Date): $storageAccountName doesn't exist. You can run New-AzureStorageAccount to create a new one."
        return
    }

    $vnetSite = $null
    if(![string]::IsNullOrEmpty($vnetName))
    {
        $vnetSite = Get-AzureVNetSite -VNetName $vnetName
        if(!$vnetSite)
        {
            Write-Host "$(Get-Date): $vnetName doesn't exist."
            return
        }

        $vnetLocation = (Get-AzureAffinityGroup -Name $vnetSite.AffinityGroup).Location
        $storageAccountLocation = $storageAccount.Location
        if(!$storageAccountLocation)
        {
            $storageAccountLocation = (Get-AzureAffinityGroup -Name $storageAccount.AffinityGroup).Location
        }

        if($vnetLocation -ne $storageAccountLocation)
        {
            Write-Host "$(Get-Date): $vnetName should be in the same location as $storageAccountName."
            return
        }
    }

    $cloudService = Get-AzureService -ServiceName $serviceName -ErrorAction Ignore

    if($cloudService -ne $null)
    {
        Write-Host "$(Get-Date): Start to clean up existing cloud service $serviceName."    
        CleanupCloudService $serviceName
    }

    $vmConfig = New-AzureVMConfig -Name $vmName -InstanceSize $vmSize -ImageName $imageName |
                    Add-AzureProvisioningConfig -Windows -EnableWinRMHttp -AdminUsername $adminUserName -Password $adminUserPassword 
         
    Write-Host "$(Get-Date): Start to create virtual machine: $vmName." 

    if(!$vnetSite)
    {
        if(!$storageAccount.Location)
        {
            New-AzureVM -VMs $vmConfig -AffinityGroup $storageAccount.AffinityGroup -ServiceName $serviceName -WaitForBoot
        }
        else
        {
            New-AzureVM -VMs $vmConfig -Location $storageAccount.Location -ServiceName $serviceName -WaitForBoot
        }
    }
    else
    {
        if($subnetNames -ne $null)
        {
            $vmConfig = Set-AzureSubnet -VM $vmConfig -SubnetNames $subnetNames
        }

        New-AzureVM -VMs $vmConfig -VNetName $vnetName -AffinityGroup $vnetSite.AffinityGroup -ServiceName $serviceName -WaitForBoot
    }
}

<#
.Synopsis
   Download and install a WinRm certificate to the certficate store
.DESCRIPTION
   Gets the WinRM certificate from the specified Virtual Machine, and install it on the LocalMachine store.
.INPUTS
   $serviceName - The name of the Cloud Service.
   $vmName - The name of the Virtual Machine.
.OUTPUTS
   NONE
#>

function DownloadAndInstallWinRMCert
{
    param(
        # The name of the Cloud Service
        [string]$serviceName, 

        # The name of the Virtual Machine
        [string]$vmName
        )
    
    $winRMCert = (Get-AzureVM -ServiceName $serviceName -Name $vmname | select -ExpandProperty vm).DefaultWinRMCertificateThumbprint
 
    $AzureX509cert = Get-AzureCertificate -ServiceName $serviceName -Thumbprint $winRMCert -ThumbprintAlgorithm sha1
 
    $certTempFile = [IO.Path]::GetTempFileName()

    $AzureX509cert.Data | Out-File $certTempFile
 
    $certToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certTempFile
 
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"

    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)

    $exists = $false
    foreach($certificate in $store.Certificates)
    {
        if($certificate.Thumbprint -eq $certToImport.Thumbprint)
        {
            $exists = $true
            break
        }
    }
    
    if(!$exists)
    {
        $store.Add($certToImport)
    }

    $store.Close()
 
    Remove-Item $certTempFile
}

# Prepare azure environement

Import-AzurePublishSettingsFile -PublishSettingsFile $azurePublishSettingsFile -ErrorAction Stop
Select-AzureSubscription -SubscriptionName $subscriptionName -ErrorAction Stop
Set-AzureSubscription -SubscriptionName $subscriptionName -CurrentStorageAccount $storageAccountName -ErrorAction Stop

# Use vmName as serviceName. Clean up the existing one before creation.
$serviceName = $vmName
CreateVirtualMachine $imageName $storageAccountName $serviceName $vmName $vmSize $adminUserName $adminUserPassword $vnetName $subnetNames

Write-Host "$(Get-Date): Start to download and install the remoting cert (self-signed) to local machine trusted root"
DownloadAndInstallWinRMCert $serviceName $vmName

$remotingUri = (Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName).AbsoluteUri
$remotingCredential = New-Object System.Management.Automation.PSCredential "$vmName\$adminUserName", (ConvertTo-SecureString -String $adminUserPassword -AsPlainText -Force)

Write-Host "$(Get-Date): Start to configure SharePoint Farm via powershell remoting uri: $remotingUri" 

$configureSPFarmScript = 
{
    Param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
        [string]$localSPFarmAccountName,
        [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$false)]
        [string]$localSPFarmAccountPassword
        )

    $configureSharePointFarmScript = Join-Path -Path $env:SystemDrive -ChildPath "ConfigureDeveloperDesktop\Scripts\ConfigureSharePointFarm.ps1"

    $result = & $configureSharePointFarmScript -localSPFarmAccountName $localSPFarmAccountName -localSPFarmAccountPassword $localSPFarmAccountPassword

    return $result
}
$result = Invoke-Command -ConnectionUri $remotingUri -Credential $remotingCredential -ScriptBlock $configureSPFarmScript -ArgumentList @($localSPFarmAccountName, $localSPFarmAccountPassword)

if($result -ne 0)
{
    Write-Host "$(Get-Date): Failed to configure SharePoint Farm."
    exit
}

Write-Host "$(Get-Date): Please run Get-AzureRemoteDesktopFile to connect the machine and login as $vmName\$adminUserName"
