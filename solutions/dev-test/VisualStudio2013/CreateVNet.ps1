<#
    Copyright (c) Microsoft Corporation. All rights reserved.
    THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
    ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
    IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
    PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
#>

<#
.SYNOPSIS
    Create a Virtual Network.
.DESCRIPTION
    Create a Virtual Network using the settings from the Virtual Network configuration file.
 
    The configuration file follows the schema definition which can be found in http://msdn.microsoft.com/en-us/library/windowsazure/jj157100.aspx.
    Here is an example:
    <?xml version="1.0" encoding="utf-8"?> 
    <NetworkConfiguration xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration"> 
        <VirtualNetworkConfiguration> 
            <VirtualNetworkSites> 
                <VirtualNetworkSite name="VNet1" AffinityGroup="AffinityGroup1"> 
                    <AddressSpace> 
                        <AddressPrefix>10.0.0.0/20</AddressPrefix> 
                    </AddressSpace> 
                    <Subnets> 
                        <Subnet name="Subnet1"> 
                            <AddressPrefix>10.0.0.0/28</AddressPrefix> 
                        </Subnet> 
                    </Subnets> 
                </VirtualNetworkSite> 
            </VirtualNetworkSites> 
        </VirtualNetworkConfiguration>
    </NetworkConfiguration>
.EXAMPLE
    .\CreateVNet.ps1 -azurePublishSettingsFile "C:\Sample\Sample.publishsettings" -subscriptionName "SampleSub" -vnetConfigurationPath "C:\Sample\vnet.xml" -affinityGroupName "AffinityGroup1" -affinityGroupLocation "West US" 
#>

Param(
    # The path of the Azure Publish Settings file
    [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
    [string]$azurePublishSettingsFile, 

    # The name of the subscription
    [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$false)]
    [string]$subscriptionName, 

    # The path of the configuration file
    [Parameter(Mandatory=$true, Position=2, ValueFromPipeline=$false)]
    [string]$vnetConfigurationPath,

    # The name of the Affinity Group that Virtual Netwokr will be associated with
    [Parameter(Mandatory=$true, Position=3, ValueFromPipeline=$false)]
    [string]$affinityGroupName,

    # The location of the Affinity Group 
    [Parameter(Mandatory=$true, Position=4, ValueFromPipeline=$false)]
    [string]$affinityGroupLocation
)

if(!(Test-Path $vnetConfigurationPath))
{
    Write-Host "$(Get-Date): $vnetConfigurationPath doesn't exist."
    exit
}

<#
.SYNOPSIS
    Add a new Virtual Network configuration to the existing configuration.
.DESCRIPTION
    Add a new Virtual Network configuration to the existing configuration.
.INPUTS 
    vnetConfigurationPath - Path to the configuration file
.OUTPUTS
    None
#>

function AddVNet 
{	    
    Param(
        # Path to the configuration file
        [string] $vnetConfigurationPath
        )

    $error.Clear()

	$inputVNetConfig = [xml] (Get-Content $vnetConfigurationPath)
	$currentVNetConfig = [xml] (Get-AzureVNetConfig).XMLConfiguration	
    $combinedVNetConfig = $null
	
	#If no configuration found just use the new configuration
	if(!$currentVNetConfig.NetworkConfiguration)
	{
		$combinedVNetConfig = $inputVNetConfig
	}
	else
	{
		# If VNet already exists and identical do nothing
		$inputVNetSite = $inputVNetConfig.SelectSingleNode("/*/*/*[name()='VirtualNetworkSites']/*[name()='VirtualNetworkSite']")
		$existingVNetSite = $currentVNetConfig.SelectSingleNode("/*/*/*[name()='VirtualNetworkSites']/*[name()='VirtualNetworkSite'][@name='" + $inputVNetSite.name + "']")
		if($existingVNetSite -ne $null -and $existingVNetSite.AddressSpace.OuterXml.Equals($inputVNetSite.AddressSpace.OuterXml) -and $existingVNetSite.Subnets.OuterXml.Equals($inputVNetSite.Subnets.OuterXml))
		{
			Write-Host "$(Get-Date): A VNet with name $($inputVNetSite.name) and identical configuration already exists."		
            return
		}
		
		$combinedVNetConfig = $currentVNetConfig
		
		# Combine DNS Servers
		$dnsNode = $combinedVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns
		if($dnsNode -ne $null)
		{
			$inputDnsServers = $inputVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers
			$newDnsServers = MergeXmlChildren $dnsNode.DnsServers $inputDnsServers "name"
			$dnsNode.ReplaceChild($newDnsServers, $dnsNode.DnsServers) | Out-Null
		}
		elseif($currentVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns -ne $null)
		{
			$combinedVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.InsertBefore($currentVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns,
				$combinedVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites) | Out-Null
		}
		
		# Combine Virtual Network Sites
        $virtualNetworkConfigurationNode = $combinedVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration
        if($virtualNetworkConfigurationNode.VirtualNetworkSites -ne $null)
        {        
            $inputVirtualNetworkSites = $inputVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites    
            $newVirtualNetworkSites = MergeXmlChildren $virtualNetworkConfigurationNode.VirtualNetworkSites $inputVirtualNetworkSites "name"
            $virtualNetworkConfigurationNode.ReplaceChild($newVirtualNetworkSites, $virtualNetworkConfigurationNode.VirtualNetworkSites) | Out-Null
        }
        elseif($inputVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites -ne $null)
        {
            $inputVirtualNetworkSites = $inputVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites
            $vns = $combinedVNetConfig.CreateElement("VirtualNetworkSites", $combinedVNetConfig.DocumentElement.NamespaceURI)
            $vns.InnerXML = $inputVirtualNetworkSites.InnerXml
            $combinedVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.AppendChild($vns) | Out-Null 
        }
        else
        {
            Write-Host "$(Get-Date): VirtualNetworkSites are missing from $vnetConfigurationPath."
            return
        }
	}
	
	$combinedVNetConfigurationPath = Join-Path -Path $env:temp -ChildPath "vnet.xml"
	$combinedVNetConfig.Save($combinedVNetConfigurationPath)

    Write-Host "$(Get-Date): Start to update VNet config."
	Set-AzureVNetConfig -ConfigurationPath $combinedVNetConfigurationPath | Out-Null

    if(!$error)
    {
        Write-Host "$(Get-Date): VNet config has been successfully updated."
    }
}

<#
.SYNOPSIS
    Merge the child nodes of two xml elements which have the same schema.
.DESCRIPTION
    Merge the child nodes of two xml elmenets which have the same schema. 
    Use the target attribute value as the key to identify the node. If there exits any key confilction, return $null. 
.INPUTS
    $elem1 - The first xml element. 
    $elem2 - The second xml element.
    $keyAttributeName - The name of the attribute used as the key.
.OUTPUTS
    The combined xml element.
#>

function MergeXmlChildren
{
    Param(
        # The first xml element
        [System.Xml.XmlElement] $elem1,

        # The second xml element
        [System.Xml.XmlElement] $elem2, 

        # The name of the attribute used as the key
        [string] $keyAttributeName
        )

	$elemCombined = $elem1

	# Get key values from $elem1
	$childNodeHash = @{}
	foreach($childNode in $elem1.ChildNodes)
	{
		$childNodeHash.Add($childNode.$keyAttributeName, $childNode)
	}
	
	foreach($childNode in $elem2.ChildNodes)
	{
		if(!($childNodeHash.Keys -contains $childNode.$keyAttributeName))
		{
			# Append children from $elem2 if there is no key conflict
			$importedNode = $elemCombined.AppendChild($elemCombined.OwnerDocument.ImportNode($childNode, $true))
		}
		elseif(!$childNodeHash.Item($childNode.$keyAttributeName).OuterXml.Equals($childNode.OuterXml))
		{
			# Otherwise return $null
			Write-Host "$(Get-Date): Failed to merge XML element $($elem1.Name) because non-identical child elements with the same $keyAttributeName are found."
            return $null
		}
	}

    return $elemCombined
}

# Prepare Azure environment

Import-AzurePublishSettingsFile -PublishSettingsFile $azurePublishSettingsFile -ErrorAction Stop
Select-AzureSubscription -SubscriptionName $subscriptionName -ErrorAction Stop

$affinityGroup = Get-AzureAffinityGroup -Name $affinityGroupName -ErrorAction Ignore
if(!$affinityGroup)
{
    Write-Host "$(Get-Date): Start to create affinity group $affinityGroupName located in $affinityGroupLocation."
	New-AzureAffinityGroup -Name $affinityGroupName -Location $affinityGroupLocation
}
else
{
    # Check if the existing affinity group matches the location
    if ($affinityGroup.Location -ne $affinityGroupLocation)
    {
        Write-Host "$(Get-Date): Affinty group $affinityGroupName already exists but is not located in $affinityGroupLocation."
        exit
    }
}

Write-Host "$(Get-Date): Start to add VNet."
AddVNet $vnetConfigurationPath
