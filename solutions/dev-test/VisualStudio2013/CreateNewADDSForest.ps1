<#
    Copyright (c) Microsoft Corporation. All rights reserved.
    THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
    ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
    IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
    PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
#>

<#
.SYNOPSIS
    Create a new Virtual Machine with Active Directory Domain Services.
.DESCRIPTION
    Create a new Virtual Machine with Active Directory Domain Services. It's based on the Windows Server 2012 image.

    The script must be executed with elevated privileges.
.EXAMPLE
    .\CreateNewADDSForest.ps1 -ws2012iImageName "a699494373c04fc0bc8f2bb1389d6106__Windows-Server-2012-Datacenter-201309.01-en.us-127GB.vhd" -azurePublishSettingsFile "C:\Sample\Sample.publishsettings" -subscriptionName "SampleSub" -storageAccountName "samplestorage" -vmName "sampleadds" -vmSize "Medium" -adminUserName "SampleUser1" -adminUserPassword "Pass@word1" -domainName "sample.contoso.com" -safeModeAdminPassword "Pass@word1" -domainSPFarmAccountName "sp_farm" -domainSPFarmAccountPassword "Pass@word1" -vnetName "VNet1" -subnetNames "Subnet1"
#>

Param(
    # The name of the Windows Server 2012 image
    [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
    [string]$ws2012iImageName,

    # The path of the Azure Publish Settings file
    [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$false)]
    [string]$azurePublishSettingsFile,

    # The name of the subscription
    [Parameter(Mandatory=$true, Position=2, ValueFromPipeline=$false)]
    [string]$subscriptionName, 

    # The name of the Storage Account which will be used to store the Virtual Machine. Please note the script will not create a storage account.
    [Parameter(Mandatory=$true, Position=3, ValueFromPipeline=$false)]
    [string]$storageAccountName,

    # The name of the Virtual Machine. The name will also be used as the Cloud Service name that will be created. If the name is taken, the script will automatically clean up the existing deployments or virtual machines in the service.
    [Parameter(Mandatory=$true, Position=4, ValueFromPipeline=$false)]
    [string]$vmName, 

    # The size of the Virtual Machine
    [Parameter(Mandatory=$true, Position=5, ValueFromPipeline=$false)]
    [string]$vmSize, 

    # The name of the admin account that you will use to connect to the machine. After Active Directory is configured, the account will be turned into domain admin user. You need to connect to the machine using “domainName\adminUserName”. If you don’t want to create a new domain user, you can use this account as domain users in CreateSharePointDeveloperMachineInDomain.ps1
    [Parameter(Mandatory=$true, Position=6, ValueFromPipeline=$false)]
    [string]$adminUserName, 

    # The password of the admin account
    [Parameter(Mandatory=$true, Position=7, ValueFromPipeline=$false)]
    [string]$adminUserPassword,

    # The fully qualified domain name (FQDN) for the root (first) domain in the forest. For more information see: http://technet.microsoft.com/en-us/library/hh974720(v=wps.620).aspx
    [Parameter(Mandatory=$true, Position=8, ValueFromPipeline=$false)]
    [string]$domainName,

    # The password for the administrator account when the computer is started in Safe Mode or a variant of Safe Mode, such as Directory Services Restore Mode. You must supply a password that meets the password complexity rules of the domain and the password cannot be blank. For more information see: http://technet.microsoft.com/en-us/library/hh974720(v=wps.620).aspx 
    [Parameter(Mandatory=$true, Position=9, ValueFromPipeline=$false)]
    [string]$safeModeAdminPassword,

    # The name of the SharePoint farm domain account
    [Parameter(Mandatory=$true, Position=10, ValueFromPipeline=$false)]
    [string]$domainSPFarmAccountName,

    # The password of the SharePoint farm domain account
    [Parameter(Mandatory=$true, Position=11, ValueFromPipeline=$false)]
    [string]$domainSPFarmAccountPassword,

    # The name of the Virtual Network the Virtual Machine should be provisioned into. The Virtual Network needs to be in the same location as the storage account. Please note that this will not create a Virtual Network
    [Parameter(Mandatory=$true, Position=12, ValueFromPipeline=$false)]
    [string]$vnetName,

    # The subnet names of the Virtual Network the Virtual Machine should be provisioned into
    [Parameter(Mandatory=$false, Position=13, ValueFromPipeline=$false)]
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

<#
.Synopsis
   Add a Virtual Machine to the DNS servers of the specified Virtual Network.
.DESCRIPTION
   Add a Virtual Machine to the DNS servers of the specified Virtual Network.
.INPUTS
   $vnetName - The name of the Virtual Network.
   $serviceName - The name of the Cloud Service.
   $vmName - The name of the Virtual Machine.
.OUTPUTS
   NONE
#>

function AddVNetDNSEntry
{
	param(
        # The name of the Virtual Network
        [string] $vnetName,

        # The name of the Cloud Service
        [string] $serviceName, 

        #
        [string] $vmName
        )
    
    $error.Clear()

    $dnsName = $vmName
    $dnsIPAddress = (Get-AzureVM -ServiceName $serviceName -Name $vmName).IpAddress

	# Export existing Azure VNet Config
	
	$vnetConfig = [xml] (Get-AzureVNetConfig).XMLConfiguration

	# Read the configuration file into memory	
	$namespace = "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration"
	 
	if($vnetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers -eq $null) 
	{
        # Add DNS Server node
		$dnsServersNode = $vnetConfig.CreateElement("DnsServers", $namespace)
		$dnsServerNode = $vnetConfig.CreateElement("DnsServer", $namespace)
	    $dnsServerNode.SetAttribute('name', $dnsName) | Out-Null
		$dnsServerNode.SetAttribute('IPAddress', $dnsIPAddress) | Out-Null
	    $dnsServersNode.AppendChild($dnsServerNode) | Out-Null
		$vnetConfig.NetworkConfiguration.VirtualNetworkConfiguration.GetElementsByTagName('Dns')[0].AppendChild($dnsServersNode) | Out-Null
	}
	else 
	{
        # Update existing DNS Server node
		$dnsServerNode = $vnetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers.SelectSingleNode("descendant::*[name()='DnsServer'][@name='" + $dnsName +"']")
		if($dnsServerNode -eq $null)
		{
			$dnsServerNode = $vnetConfig.CreateElement("DnsServer", $namespace)
		    $dnsServerNode.SetAttribute('name', $dnsName) | Out-Null
			$dnsServerNode.SetAttribute('IPAddress',$dnsIPAddress) | Out-Null
		    $vnetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers.AppendChild($dnsServerNode) | Out-Null
		}
		else
		{
			$dnsServerNode.SetAttribute('IPAddress',$dnsIPAddress) | Out-Null
		}
	}
	
    
	$vnetSite = $vnetConfig.SelectSingleNode("/*/*/*[name()='VirtualNetworkSites']/*[name()='VirtualNetworkSite'][@name='" + $vnetName + "']")
	if($vnetSite.DnsServersRef -eq $null) 
	{
        # Add DNS Servers Ref node
		$dnsServersRefNode = $vnetConfig.CreateElement("DnsServersRef", $namespace)
		$dnsServerRefNode = $vnetConfig.CreateElement("DnsServerRef", $namespace)
	    $dnsServerRefNode.SetAttribute('name', $dnsName) | Out-Null
	    $dnsServersRefNode.AppendChild($dnsServerRefNode) | Out-Null	 
		$vnetSite.AppendChild($dnsServersRefNode) | Out-Null
	}
	else 
	{
        # Update existing DNS Servers Ref node
		$dnsServerRefNode = $vnetSite.DnsServersRef.SelectSingleNode("descendant::*[name()='DnsServerRef'][@name='" + $dnsName +"']")
		if($dnsServerRefNode -eq $null)
		{
			$dnsServerRefNode = $vnetConfig.CreateElement("DnsServerRef", $namespace)
		    $dnsServerRefNode.SetAttribute('name', $dnsName) | Out-Null
		    $vnetSite.DnsServersRef.AppendChild($dnsServerRefNode) | Out-Null
		}
	}
	
    $vnetConfigurationPath =  Join-Path -Path $env:temp -ChildPath "vnet.xml"
	$vnetConfig.Save($vnetConfigurationPath)
	
	Write-Host "$(Get-Date): Start to update VNet config with new DNS Server entry."
	Set-AzureVNetConfig -ConfigurationPath $vnetConfigurationPath | Out-Null

    if(!$error)
    {
        Write-Host "$(Get-Date): VNet config has been successfully updated."
    }
}

# Prepare azure environment

Import-AzurePublishSettingsFile -PublishSettingsFile $azurePublishSettingsFile -ErrorAction Stop
Select-AzureSubscription -SubscriptionName $subscriptionName -ErrorAction Stop
Set-AzureSubscription -SubscriptionName $subscriptionName -CurrentStorageAccount $storageAccountName -ErrorAction Stop

# Use vmName as serviceName. Clean up the existing one before creation.

$serviceName = $vmName
CreateVirtualMachine $ws2012iImageName $storageAccountName $serviceName $vmName $vmSize $adminUserName $adminUserPassword $vnetName $subnetNames

Write-Host "$(Get-Date): Start to download and install the remoting cert (self-signed) to local machine trusted root."
DownloadAndInstallWinRMCert $serviceName $vmName

$remotingUri = (Get-AzureWinRMUri -ServiceName $serviceName -Name $vmName).AbsoluteUri
$remotingCredential = New-Object System.Management.Automation.PSCredential "$vmName\$adminUserName", (ConvertTo-SecureString -String $adminUserPassword -AsPlainText -Force)

Write-Host "$(Get-Date): Start to configure Active Directory Forest via powershell remoting uri: $remotingUri." 
$configureADDSForestScript = 
{
    Param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
        [string]$domainName,
        [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$false)]
        [string]$safeModeAdminPassword
        )

    $isWS2012 = [Environment]::OSVersion.Version -ge (new-object 'Version' 6,2,9200,0)

    if(!$isWS2012)
    {
        Write-Host "(VM) $(Get-Date): Current version only supports Windows Server 2012"
        return 1
    }

    $databasePath = Join-Path -Path $env:SystemDrive -ChildPath "NTDS"		
    $sysvolPath  = Join-Path -Path $env:SystemDrive -ChildPath "SysvolPath"
    $logPath  = Join-Path -Path $env:SystemDrive -ChildPath "Logs"	
				
    New-Item -Path $databasePath -ItemType directory | Out-Null
    New-Item -Path $sysvolPath -ItemType directory | Out-Null
    New-Item -Path $logPath -ItemType directory | Out-Null

    Write-Host "(VM) $(Get-Date): Start to install AD-Domain-Service feature."

    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

    Write-Host "(VM) $(Get-Date): Start to install ADDSForest."

    Install-ADDSForest -DomainName $domainName -DomainMode Win2012 -ForestMode Win2012 -Force -SafeModeAdministratorPassword (ConvertTo-SecureString -String $safeModeAdminPassword -AsPlainText -force) -DatabasePath $databasePath -SYSVOLPath $sysvolPath -LogPath $logPath -NoRebootOnCompletion | Out-Null

    Import-Module -Name DnsServer

    $externalPublicDnsServiceAddress = "8.8.8.8"

    Write-Host "(VM) $(Get-Date): Start to add DNS conditional forward zones for external domains."

    Add-DnsServerConditionalForwarderZone -Name 'com' -MasterServers $externalPublicDnsServiceAddress
    Add-DnsServerConditionalForwarderZone -Name 'net' -MasterServers $externalPublicDnsServiceAddress
    Add-DnsServerConditionalForwarderZone -Name 'ms' -MasterServers $externalPublicDnsServiceAddress

    return 0
}
$result = Invoke-Command -ConnectionUri $remotingUri -Credential $remotingCredential -ScriptBlock $configureADDSForestScript -ArgumentList @($domainName, $safeModeAdminPassword)

if($result -ne 0)
{
    Write-Host "$(Get-Date): Failed to configure Active Directory Forest."
    exit
}
else 
{
    Write-Host "$(Get-Date): Active Directory Forest has been configured successfully. $domainName\$adminUserName is the domain admin user."
}

Write-Host "$(Get-Date): Start to reboot virtual machine: $vmName."
Restart-AzureVM -ServiceName $serviceName -Name $vmName

Write-Host "$(Get-Date): Start to update VNet DNS entry."
AddVNetDNSEntry $vnetName $serviceName $vmName

Write-Host "$(Get-Date): Start to add SPFarm domain user."
$remotingCredential = New-Object System.Management.Automation.PSCredential "$domainName\$adminUserName", (ConvertTo-SecureString -String $adminUserPassword -AsPlainText -Force)
$addDomainUserScript = 
{
    Param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
        [string]$ouName, 
        [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$false)]
        [string]$userName, 
        [Parameter(Mandatory=$true, Position=2, ValueFromPipeline=$false)]
        [string]$displayName, 
        [Parameter(Mandatory=$true, Position=3, ValueFromPipeline=$false)]
        [string]$password
        )

    $Error.Clear()

    Start-Service -Name "ADWS"

    $maxTry = 10
    while (((Get-Service -Name "ADWS").Status -ne "Running") -and ($maxTry -gt 0))
    {
        Write-Host "(VM) $(Get-Date): Wait 10 seconds for Active Directory Web Services running."
        Start-Sleep -Seconds 10
        $maxTry--
    }

    $domainName = (Get-ADDomain).DistinguishedName        

    $ouDN = "OU=$ouName, $domainName"

    $ou = Get-ADOrganizationalUnit -Filter { name -eq $ouName } 

    if(!$ou)
    {
        New-ADOrganizationalUnit -Name $ouName -Path $domainName | Out-Null
    }
    
    New-ADUser -Name $userName -SamAccountName $userName -DisplayName $displayName -Path $ouDN -Enabled $true -ChangePasswordAtLogon $false -AccountPassword (ConvertTo-SecureString $password -AsPlainText -force) -PassThru | Out-NULL

    if(!$Error)
    {
        return 0
    }
    else
    {
        return 1
    }
}
$result = Invoke-Command -ConnectionUri $remotingUri -Credential $remotingCredential -ScriptBlock $addDomainUserScript -ArgumentList @("SharePoint", $domainSPFarmAccountName, "SharePoint Farm Domain Account", $domainSPFarmAccountPassword)

if($result -ne 0)
{
    Write-Host "$(Get-Date): Failed to add SPFarm domain user."
    exit
}

Write-Host "$(Get-Date): New ADDS Forest has been created successfully. Please run Get-AzureRemoteDesktopFile to connect the machine and login as $domainName\$adminUserName."


