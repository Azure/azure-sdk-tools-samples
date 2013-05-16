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

Param(
[string]
$dcLocation, 
[string]
$affinityGroupName, 
[string]
$vnetConfigPath
)

################## Functions ##############################

#Function to Create Affinity Group
function CreateAffinityGroup()
{	
	#Call the New-AzureAffinityGroup cmdlet with required parameters
	$affinityGroupExists = $false
	Get-AzureAffinityGroup | ForEach-Object {if($_.Name -eq $affinityGroupName) {$affinityGroupExists = $true } }
	if(-not $affinityGroupExists)
	{
		New-AzureAffinityGroup -Name $affinityGroupName -Location $dcLocation -verbose
	}
	else
	{
		Write-Host "Affinity group already exists."
	}
}

function MergeXmlChildren()
{Param([System.Xml.XmlElement] $elem1, [System.Xml.XmlElement] $elem2, [string] $keyAttributeName)
	$elemCombined = $elem1

	# Get key values from $elem1
	$childNodeHash = @{}
	foreach($childNode in $elem1.ChildNodes)
	{
		$childNodeHash.Add($childNode.$keyAttributeName, $childNode)
	}
	
	foreach($childNode in $elem2.ChildNodes)
	{
		if(-not ($childNodeHash.Keys -contains $childNode.$keyAttributeName))
		{
			# Append children from $elem2 if there is no key conflict
			$importedNode = $elemCombined.AppendChild($elemCombined.OwnerDocument.ImportNode($childNode, $true))
		}
		elseif(-not $childNodeHash.Item($childNode.$keyAttributeName).OuterXml.Equals($childNode.OuterXml))
		{
			# Otherwise throw Exception
			Throw Write-Error ("Failed to merge XML element {0} because non-identical child elements with the same {1} are found." -f $elem1.Name, $keyAttributeName)
		}
	}
	
	$elemCombined
}

#Function to Create VNet
function CreateVNet()
{
	Write-Output $vnetConfigPath
	(Get-AzureSubscription -Current).SubscriptionName
	
	$outputVNetConfigPath = "$env:temp\spvnet.xml"
	$inputVNetConfig = [xml] (Get-Content $vnetConfigPath)
	#Get current VNet Configuration
	$currentVNetConfig = [xml] (Get-AzureVNetConfig).XMLConfiguration
	
	Write-Output $currentVNetConfig
	
	#If no configuration found just use the new configuration
	if($currentVNetConfig.NetworkConfiguration -eq $null)
	{
		$combinedVNetConfig = $inputVNetConfig
	}
	else
	{
		# If VNet already exists and identical do nothing
		$inputVNetSite = $inputVNetConfig.SelectSingleNode("/*/*/*[name()='VirtualNetworkSites']/*[name()='VirtualNetworkSite']")
		$existingVNetSite = $currentVNetConfig.SelectSingleNode("/*/*/*[name()='VirtualNetworkSites']/*[name()='VirtualNetworkSite'][@name='" + $inputVNetSite.name + "']")
		if($existingVNetSite -ne $null -and $existingVNetSite.AddressSpace.OuterXml.Equals($inputVNetSite.AddressSpace.OuterXml) `
			-and $existingVNetSite.Subnets.OuterXml.Equals($inputVNetSite.Subnets.OuterXml))
		{
			Write-Host ("A VNet with name {0} and identical configuration already exists." -f $inputVNetSite.name)
			return
		}
		
		$combinedVNetConfig = $currentVNetConfig
		
		#Combine DNS Servers
		$dnsNode = $combinedVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns
		if($dnsNode -ne $null)
		{
			$inputDnsServers = $inputVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers
			$newDnsServers = MergeXmlChildren $dnsNode.DnsServers $inputDnsServers "name"
			$dnsNode.ReplaceChild($newDnsServers, $dnsNode.DnsServers)
		}
		elseif($currentVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns -ne $null)
		{
			$combinedVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.InsertBefore($currentVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns,
				$combinedVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites)
		}
		
		#Combine VNets
        $virtualNetworkConfigurationNode = $combinedVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration
		
        
        # If VNET Config exists but there are no currently defined sites
        if($virtualNetworkConfigurationNode.VirtualNetworkSites -ne $null)
        {        
            $inputVirtualNetworkSites = $inputVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites    
            $virtualNetworkConfigurationNode.ReplaceChild((MergeXmlChildren $virtualNetworkConfigurationNode.VirtualNetworkSites $inputVirtualNetworkSites "name"), $virtualNetworkConfigurationNode.VirtualNetworkSites)
        }
        else
        {
            $inputVirtualNetworkSites = $inputVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites
            $vns = $combinedVNetConfig.CreateElement("VirtualNetworkSites", $combinedVNetConfig.DocumentElement.NamespaceURI)
            $vns.InnerXML = $inputVirtualNetworkSites.InnerXml
            $combinedVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.AppendChild($vns)
        }
	}
	
	#Call the Set-AzureVNetConfig cmdlet with required parameters
	$combinedVNetConfig.Save($outputVNetConfigPath)
	Set-AzureVNetConfig -ConfigurationPath $outputVNetConfigPath

}

################## Functions ##############################

################## Script execution begin ###########

#function calls to CreateAffinityGroup & CreateVnet
#Call CreateAffinityGroup
CreateAffinityGroup
#Call CreateVnet
CreateVnet

################## Script execution end #############
