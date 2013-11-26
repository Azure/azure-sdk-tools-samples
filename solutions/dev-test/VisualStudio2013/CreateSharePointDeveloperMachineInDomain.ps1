<#
    Copyright (c) Microsoft Corporation. All rights reserved.
    THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
    ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
    IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
    PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
#>

<#
.SYNOPSIS
    Create a new Virtual Machine for SharePoint development in the in the specified domain
.DESCRIPTION
    Create a new Virtual Machine for SharePoint development in the specified domain based on Visual Studio 2013 image. 
    The script configures SQL Server Database Engine, Reporting Service, Analysis Service, Integration Service, Agent Service and create a defulat instance (MSSQLSERVER).
    The script also configures the following SharePoint environment in the Virtual Machine.
    - SharePoint configuration database: "SP2013_Configuration".
    - SharePoint Central Administration content database: "SP2013_Content_CentralAdministration" Central Administration Port: 11111 Central Administration Authentication: NTLM.
    - Web Application "Developer Test Site" on port 80 with default authentication provider. Using default app pool running under –localSPFarmAccountName identity.
    - Root site collection "Developer Test Site Collection" Based on team site template. Primary site collection owner is the logged on user.
    
    Before executing, follow the steps to enable CredSSP on the client machine for delegation.
    - Run Set-WSManQuickConfig to make sure WinRM service is running.
    - Run Enable-WSManCredSSP -Role Client -DelegateComputer "*.cloudapp.net" Note: This command will fail if your client machine is connected to any networks defined as "Public network" in "Network and Sharing Center." 
    - Enable delegating of fresh credentials using group policy editor on your client machine. Run gpedit.msc -> Computer Configuration -> Administrative Templates -> System -> Credentials Delegation and then change the state of "Allow Delegating Fresh Credentials with NTLM-only server authentication" to "Enabled."(Its default state will say, "Not configured.") In the Add Servers sections add : WSMAN/*.cloudapp.net. Click here for more details on enabling CredSSP.

    The script must be executed with elevated privileges.
.EXAMPLE
    .\CreateSharePointDeveloperMachineInDomain.ps1 -imageName "03f55de797f546a1b29d1b8d66be687a__Visual-Studio-2013-Ultimate-12.0.21005.1-AzureSDK-2.2" -azurePublishSettingsFile "C:\Sample\Sample.publishsettings" -subscriptionName "SampleSub" -storageAccountName "samplestorage" -vmName "samplespdev" -vmSize "ExtraLarge" -adminUserName "SampleUser2" -adminUserPassword "Pass@word1" -domainDnsName "sample.contoso.com" -domainName "sample" -domainUserName "SampleUser1" -domainUserPassword "Pass@word1" -domainSPFarmAccountName "sp_farm" -domainSPFarmAccountPassword "Pass@word1" -vnetName "VNet1" -subnetNames "Subnet1"     
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

    # The fully qualified domain name (FQDN) of the Windows domain to join
    [Parameter(Mandatory=$true, Position=8, ValueFromPipeline=$false)]
    [string]$domainDnsName,

    # The domain name of the domain user account that has permission to add the computer to a domain
    [Parameter(Mandatory=$true, Position=9, ValueFromPipeline=$false)]
    [string]$domainName,

    # The name of the domain user account that has permission to add the computer to a domain. The user will be added to the administrator group of the virtual machine. The user will also be added as the primary site collection owner for the demo site collection. After the setup, you will use this account to connect to the machine.
    [Parameter(Mandatory=$true, Position=10, ValueFromPipeline=$false)] 
    [string]$domainUserName,

    # The password of the domain user account that has permission to add the computer to a domain
    [Parameter(Mandatory=$true, Position=11, ValueFromPipeline=$false)]
    [string]$domainUserPassword,

    # The name of the SharePoint Farm domain account
    [Parameter(Mandatory=$true, Position=12, ValueFromPipeline=$false)]
    [string]$domainSPFarmAccountName,

    # The password of the SharePoint Farm domain account
    [Parameter(Mandatory=$true, Position=13, ValueFromPipeline=$false)]
    [string]$domainSPFarmAccountPassword,

    # The name of the Virtual Network the Virtual Machine should be provisioned into. The Virtual Network needs to be in the same location as the storage account. Please note that this will not create a Virtual Network
    [Parameter(Mandatory=$true, Position=14, ValueFromPipeline=$false)]
    [string]$vnetName,

    # The subnet names of the Virtual Network the Virtual Machine should be provisioned into
    [Parameter(Mandatory=$false, Position=15, ValueFromPipeline=$false)]
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
    Create a new Virtual Machine in the specified domain
.DESCRIPTION
    Create a new Virtual Machine in the specified domain. If there exits a Cloud Service with the same name, it will be removed along with its deployments.
.INPUTS
    $imageName - The name of the base Virtual Machine image.
    $storageAccountName - The name of the Storage Account which will be used to store the Virtual Machine.
    $serviceName - The name of the Cloud Service for the Virtual Machine.
    $vmName - The name of the Virtual Machine.
    $vmSize - The size of the Virtual Machine.
    $adminUserName - The name of the admin account.
    $adminUserPassword - The password of the admin account.
    $domainDnsName - The fully qualified domain name (FQDN) of the Windows domain to join.
    $domainName - The domain name of the domain user account that has permission to add the computer to a domain.
    $domainUserName - The name of the domain user account that has permission to add the computer to a domain.
    $domainPassword - The name of the domain user account that has permission to add the computer to a domain.
    $vnetName - The name of the Virtual Network.
    $subnetNames - The subnet names of the Virtual Network. 
.OUTPUTS
    None.
#>

function CreateVirtualMachineInDomain
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
    
        # The fully qualified domain name (FQDN) of the Windows domain to join
        [string]$domainDnsName,

        # The domain name of the domain user account that has permission to add the computer to a domain
        [string]$domainName,

        # The name of the domain user account that has permission to add the computer to a domain
        [string]$domainUserName,

        # The password of the SharePoint Farm domain account
        [string]$domainPassword,

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
        return 1
    }

    $storageAccount = Get-AzureStorageAccount -StorageAccountName $storageAccountName
    if(!$storageAccount)
    {
        Write-Host "$(Get-Date): $storageAccountName doesn't exist. You can run New-AzureStorageAccount to create a new one."
        return 1
    }

    $vnetSite = Get-AzureVNetSite -VNetName $vnetName
    if(!$vnetSite)
    {
        Write-Host "$(Get-Date): $vnetName doesn't exist."
        return 1
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
        return 1
    }

    $cloudService = Get-AzureService -ServiceName $serviceName -ErrorAction Ignore

    if($cloudService -ne $null)
    {
        Write-Host "$(Get-Date): Start to clean up existing cloud service $serviceName."    
        CleanupCloudService $serviceName
    }

    $vmConfig = New-AzureVMConfig -Name $vmName -InstanceSize $vmSize -ImageName $imageName |
                    Add-AzureProvisioningConfig -WindowsDomain -EnableWinRMHttp -AdminUsername $adminUserName -Password $adminUserPassword -JoinDomain $domainDnsName -Domain $domainName -DomainUserName $domainUserName -DomainPassword $domainPassword
         
    if($subnetNames -ne $null)
    {
        $vmConfig = Set-AzureSubnet -VM $vmConfig -SubnetNames $subnetNames
    }

    Write-Host "$(Get-Date): Start to create virtual machine: $vmName." 

    New-AzureVM -VMs $vmConfig -VNetName $vnetName -AffinityGroup $vnetSite.AffinityGroup -ServiceName $serviceName -WaitForBoot
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
CreateVirtualMachineInDomain $imageName $storageAccountName $serviceName $vmName $vmSize $adminUserName $adminUserPassword $domainDnsName $domainName $domainUserName $domainUserPassword $vnetName $subnetNames

Write-Host "$(Get-Date): Start to download and install the remoting cert (self-signed) to local machine trusted root."
DownloadAndInstallWinRMCert $serviceName $vmName

$remotingUri = (Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName).AbsoluteUri
$remotingCredential = New-Object System.Management.Automation.PSCredential "$vmName\$adminUserName", (ConvertTo-SecureString -String $adminUserPassword -AsPlainText -Force)

Write-Host "$(Get-Date): Start to add domain user to local admin group via powershell remoting uri: $remotingUri." 
$addDomainUserToLocalGroupScript = 
{
    Param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
        [string]$domainName,
        [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$false)]
        [string]$domainUserName,
        [Parameter(Mandatory=$true, Position=2, ValueFromPipeline=$false)]
        [string]$groupName
        )

    $Error.Clear()

    ([ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group").Add("WinNT://$domainName/$domainUserName")

    if(!$Error)
    {
        return 0
    }
    else
    {
        return 1
    }
}
$result = Invoke-Command -ConnectionUri $remotingUri -Credential $remotingCredential -ScriptBlock $addDomainUserToLocalGroupScript -ArgumentList @($domainName, $domainUserName, "Administrators")

if($result -ne 0)
{
    Write-Host "$(Get-Date): Failed to add domain user to local admin group."     
    exit
}

Write-Host "$(Get-Date): Start to enable CredSSP via powershell remoting uri: $remotingUri." 
$enableCredSSPScript = 
{
    Param()

    $Error.Clear()

    $credSSP = winrm g winrm/config/service/auth | Where-Object {$_.Contains('CredSSP = true')}

    if(!$credSSP)
    {
	    Write-Host "(VM) $(Get-Date): Start to enable CredSSP."

	    winrm s winrm/config/service/auth '@{CredSSP="true"}' | Out-Null	
    }
    else
    {
	    Write-Host "(VM) $(Get-Date): CredSSP is already enabled."
    }

    if(!$Error)
    {
        return 0
    }
    else
    {
        return 1
    }    
}
$result = Invoke-Command -ConnectionUri $remotingUri -Credential $remotingCredential -ScriptBlock $enableCredSSPScript

if($result -ne 0)
{
    Write-Host "$(Get-Date): Failed to enable CredSSP."     
    exit
}

Write-Host "$(Get-Date): Start to configure SharePoint Farm in domain via powershell remoting uri: $remotingUri." 
$remotingCredential = New-Object System.Management.Automation.PSCredential "$domainName\$domainUserName", (ConvertTo-SecureString -String $domainUserPassword -AsPlainText -Force)
$configureSPFarmInDomainScript = 
{
    Param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
        [string]$domainSPFarmAccountName,
        [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$false)]
        [string]$domainSPFarmAccountPassword
        )

    $configureSharePointFarmInDomainScript = Join-Path -Path $env:SystemDrive -ChildPath "ConfigureDeveloperDesktop\Scripts\ConfigureSharePointFarmInDomain.ps1"

    $result = & $configureSharePointFarmInDomainScript -domainSPFarmAccountName $domainSPFarmAccountName -domainSPFarmAccountPassword $domainSPFarmAccountPassword

    return $result
}
$result = Invoke-Command -ConnectionUri $remotingUri -Credential $remotingCredential -Authentication Credssp -ScriptBlock $configureSPFarmInDomainScript -ArgumentList @($domainSPFarmAccountName, $domainSPFarmAccountPassword)

if($result -ne 0)
{
    Write-Host "$(Get-Date): Failed to configure SharePoint Farm in domain."
    exit
}

Write-Host "$(Get-Date): Please run Get-AzureRemoteDesktopFile to connect the machine and login as $domainName\$domainUserName." 
