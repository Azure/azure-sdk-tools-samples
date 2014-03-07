<#
 * Copyright Microsoft Corporation
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
#>

param(
	$subscriptionFilePath,
	$subscriptionName,
	$storageAccount,
	$dcLocation,
	$affinityGroupName,	
	$vmName, 
	$serviceName, 
	$availabilitySet,
	$size,
	$imageName,	
	$subnetNames,
	$password,
	$adminUserName,	
	$dataDisks,			
	$vnetName,	
    $netBiosDomainName,	
	$dcInstallMode, 	
	$dnsDomain,
    $createVNET
)


# Include script file for shared functions
$scriptFolder = Split-Path -parent $MyInvocation.MyCommand.Definition
. "$scriptFolder\..\SharedComponents\SharedFunctions.ps1"


################## Functions ##############################

function CreateVNet()
{
	#Get the NetworkConfig.xml path
	$vnetConfigPath = (Join-Path -Path $scriptFolder -ChildPath "..\Config\AD-VNET\NetworkConfig.xml")
    $vnetConfigPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($vnetConfigPath)
	
	#Get the CreateVnet.ps1 script path
	$vnetScriptPath = (Join-Path -Path $scriptFolder -ChildPath "CreateVNet.ps1")
    $vnetScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($vnetScriptPath)
	
	#Populate the argument list
	$createVNetArgumentList = @()
	$createVNetArgumentList += ("-DCLocation", '$dcLocation')
	$createVNetArgumentList += ("-AffinityGroupName", $affinityGroupName)
    $createVNetArgumentList += ("-VNetConfigPath",'$vnetConfigPath')
	
	Write-Host $vnetConfigPath
    
	#Invoke the CreateVNet script with arguments
    Invoke-Expression ".'$vnetScriptPath' $createVNetArgumentList"    
}

function CreateRemotePSEnabledVM
{
	#Get the CreateRPSEnabledVM.ps1 script path
	$RPSVmScriptPath = (Join-Path -Path $scriptFolder -ChildPath "CreateRPSEnabledVM.ps1")
    $RPSVmScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RPSVmScriptPath)
	
	
	#fill in the argument list
	$createVMArgumentList = @()
	$createVMArgumentList += ("-VMName", $vmName)
	$createVMArgumentList += ("-ImageName", '$imageName')
    $createVMArgumentList += ("-Size",$size)
	$createVMArgumentList += ("-SubnetNames",$subnetNames)
	$createVMArgumentList += ("-AdminUserName",$adminUserName)
	$createVMArgumentList += ("-Password",'$password')
	$createVMArgumentList += ("-ServiceName",$serviceName)	
	$createVMArgumentList += ("-AvailabilitySet",$availabilitySet)
	$createVMArgumentList += ("-VNetName",$vnetName)
	$createVMArgumentList += ("-DiskLabelPrefix",$diskLabelPrefix)
	$createVMArgumentList += ("-AffinityGroup",$affinityGroupName)
    $createVMArgumentList += ("-DCInstallMode",$dcInstallMode)
	$createVMArgumentList += ("-DomainJoin",$dnsDomain)
	$createVMArgumentList += ("-Domain",$netBiosDomainName)
	$createVMArgumentList += ("-DataDisks",'(,$dataDisks)')
	
	#Invoke the CreateRPSEnabledVM script with arguments
    Invoke-Expression ". '$RPSVmScriptPath' $createVMArgumentList"
}

function FormatDisk
{
	#Get the FormatDisk.ps1 script path
	$FormatDiskScriptPath = (Join-Path -Path $scriptFolder -ChildPath "FormatDisk.ps1")
    $FormatDiskScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FormatDiskScriptPath)
	
	#fill in the argument list
	$formatDiskargumentList = @()
	$formatDiskargumentList += ("-VMName",$vmName)
	$formatDiskargumentList += ("-ServiceName",$serviceName)
	$formatDiskargumentList += ("-AdminUserName",$adminUserName)
	$formatDiskargumentList += ("-Password",'$password')
	
	#Invoke Format disk with arguments
	Invoke-Expression ". '$FormatDiskScriptPath' $formatDiskargumentList"
}

function ConfigureDC
{
	#Get the ConfigureDC.ps1 script path
	$ConfigureDCScriptPath = (Join-Path -Path $scriptFolder -ChildPath "ConfigureDC.ps1")
    $ConfigureDCScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigureDCScriptPath)
	
	#fill in the argument list
	$configureDCArgumentList = @()
	$configureDCArgumentList += ("-VMName",$vmName)
	$configureDCArgumentList += ("-ServiceName",$serviceName)
	$configureDCArgumentList += ("-AdminUserName",$adminUserName)
	$configureDCArgumentList += ("-Password",'$password')
	$configureDCArgumentList += ("-DCInstallMode",'$dcInstallMode')
	$configureDCArgumentList += ("-NetBiosDomainName",'$netBiosDomainName')
	$configureDCArgumentList += ("-Domain",'$dnsDomain')
	
	#Invoke Configure DC with arguments
	Invoke-Expression ". '$ConfigureDCScriptPath' $configureDCArgumentList"
}

function UpdateVNetDNSEntry()
{
	param([string] $dnsServerName, [string] $domainControllerIP)
	
	Write-Output "DC IP is : $domainControllerIP" 
	Write-Host "Adding Active Directory DNS to VNET"

	#Get the NetworkConfig.xml path
	$vnetConfigurationPath =  "$env:temp\spvnet.xml"
	
	Write-Output "Exporting existing VNet..."
	Get-AzureVNetConfig -ExportToFile  $vnetConfigurationPath | Out-Null

	$namespace = "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration"

	# Read the configuration file into memory	
	Write-Output "Read the configuration file into memory..."
	[xml]$doc =  Get-Content $vnetConfigurationPath
	 
	if($doc.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers -eq $null) 
	{
		Write-Output "Adding Dns Server node...";
		$dnsServersNode = $doc.CreateElement("DnsServers", $namespace);
		$dnsServerNode = $doc.CreateElement("DnsServer", $namespace);
	    $dnsServerNode.SetAttribute('name', $dnsServerName);
		$dnsServerNode.SetAttribute('IPAddress', $domainControllerIP);
	    $dnsServersNode.AppendChild($dnsServerNode);	 
		$doc.NetworkConfiguration.VirtualNetworkConfiguration.GetElementsByTagName('Dns')[0].AppendChild($dnsServersNode);
	}
	else 
	{
		Write-Output "Updating existing Dns Server node..."
		$dnsServerNode = $doc.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers.SelectSingleNode("descendant::*[name()='DnsServer'][@name='" + $dnsServerName +"']");
		if($dnsServerNode -eq $null)
		{
			$dnsServerNode = $doc.CreateElement("DnsServer", $namespace);
		    $dnsServerNode.SetAttribute('name', $dnsServerName);
			$dnsServerNode.SetAttribute('IPAddress',$domainControllerIP);	    
		    $doc.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers.AppendChild($dnsServerNode);
		}
		else
		{
			$dnsServerNode.SetAttribute('IPAddress',$domainControllerIP);	    
		}
	}
	
	$vnetSite = $doc.SelectSingleNode("/*/*/*[name()='VirtualNetworkSites']/*[name()='VirtualNetworkSite'][@name='" + $vnetName + "']");
	if($vnetSite.DnsServersRef -eq $null) 
	{
		Write-Output "Adding Dns Servers Ref node...";
		$dnsServersRefNode = $doc.CreateElement("DnsServersRef", $namespace);
		$dnsServerRefNode = $doc.CreateElement("DnsServerRef", $namespace);
	    $dnsServerRefNode.SetAttribute('name', $dnsServerName);
	    $dnsServersRefNode.AppendChild($dnsServerRefNode);	 
		$vnetSite.AppendChild($dnsServersRefNode);
	}
	else 
	{
		Write-Output "Updating existing Dns Servers Ref node..."
		$dnsServerRefNode = $vnetSite.DnsServersRef.SelectSingleNode("descendant::*[name()='DnsServerRef'][@name='" + $dnsServerName +"']");
		if($dnsServerRefNode -eq $null)
		{
			$dnsServerRefNode = $doc.CreateElement("DnsServerRef", $namespace);
		    $dnsServerRefNode.SetAttribute('name', $dnsServerName);
		    $vnetSite.DnsServersRef.AppendChild($dnsServerRefNode);
		}
	}
	
	$doc.Save($vnetConfigurationPath)
	
	Write-Output "Updating VNet with Dns Server entry..."
	Set-AzureVNetConfig -ConfigurationPath $vnetConfigurationPath	
}

################## Functions ##############################

################## Script execution begin ###########

Import-Module "C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1"
Select-AzureSubscription -SubscriptionName $subscriptionName -verbose
Set-AzureSubscription -SubscriptionName $subscriptionName -CurrentStorageAccount $storageAccount -verbose

$scriptFolder = Split-Path -parent $MyInvocation.MyCommand.Definition
$secPassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($adminUserName, $secPassword)
$domainCredential = New-Object System.Management.Automation.PSCredential("$netBiosDomainName\$adminUserName", $secPassword)

if(($createVNET -eq $true) -and ($dcInstallMode -eq "NewForest"))
{
	CreateVNet
}

CreateRemotePSEnabledVM

FormatDisk

ConfigureDC

# Get the DC IP 
$vm = Get-AzureVM -ServiceName $serviceName -Name $vmName
$domainControllerIP = $vm.IpAddress

Write-Output "Configuring $vmName with a static internal IP, $domainControllerIP. This will allow stopping the VM later and still retain the IP."

# Set the IP as a static internal IP for the DC, to avoid losing it later. 
Set-AzureStaticVNETIP -IPAddress $domainControllerIP -VM $vm | Update-AzureVM

#Call UpdateVNetDNSEntry with the static internal IP.
if(-not [String]::IsNullOrEmpty($domainControllerIP))
{
	UpdateVNetDNSEntry $vmName $domainControllerIP
}


################## Script execution end ##############
