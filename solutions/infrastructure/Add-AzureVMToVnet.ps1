<#
.Synopsis
   Adds the given VM's based on the provided configurations to the VNet.
.DESCRIPTION
   Add a given VM to a VNet under the given cloud service, or create the cloud service and the Vnet if they do not exist, if a location parameter is given, then creates the VM.
   The omdlet supports two parameter sets, one for adding the VM to an existing VNet (thus no 
   location information needs to be given. The other is to create the VNET and add ah VM to it.

   If the location parameter is provided, the cmdlet cheks the existence of the VNet at that location and the cloud service and returns with an error if there is a VNet with that name, or a cloud service.
   If the location provider is not provided and the Vnet is not found, the cmdlet returns and error.
.EXAMPLE
  Following is an example on how to consturct the hastable the script operates on:
    $imageName = "a699494373c04fc0bc8f2bb1389d6106__Windows-Server-2012-Datacenter-201305.01-en.us-127GB.vhd"
    $credential = Get-Credential

    $vm11 = New-AzureVMConfig -Name f11 -InstanceSize Small -ImageName $imageName | Add-AzureProvisioningConfig -Windows -AdminUsername $credential.GetNetworkCredential().username -Password $credential.GetNetworkCredential().password
    $vm12 = New-AzureVMConfig -Name f12 -InstanceSize Small -ImageName $imageName | Add-AzureProvisioningConfig -Windows -AdminUsername $credential.GetNetworkCredential().username -Password $credential.GetNetworkCredential().password

    $vm21 = New-AzureVMConfig -Name f11 -InstanceSize Small -ImageName $imageName | Add-AzureProvisioningConfig -Windows -AdminUsername $credential.GetNetworkCredential().username -Password $credential.GetNetworkCredential().password
    $vm22 = New-AzureVMConfig -Name f12 -InstanceSize Small -ImageName $imageName | Add-AzureProvisioningConfig -Windows -AdminUsername $credential.GetNetworkCredential().username -Password $credential.GetNetworkCredential().password


    $vmArray1 = @($vm11, $vm12)
    $vmArray2 = @($vm21, $vm22)

    $vms = @{
        "vmtestsrv" = $vmArray1;
        "vmtestsrv1" = $vmArray2
    }

  New-AzureVMToVnet.ps1 -VNetName "testvnet" -Location "West US" -VMs $vms
#>
Param
(

    # Name of the the virtual network
    [Parameter(Mandatory = $true)]
    [String]
    $VNetName,

    # Location for the new services. If the service exists, this value will be ignored.
    [Parameter(Mandatory = $true)]
    [String]
    $Location,

    # Services and the VM configurations deployed to those services
    [Parameter(Mandatory = $true)]
    [Hashtable]
    $ServicesAndTheirVMs)

# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3

# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
$VerbosePreference = "Continue"

# Check if Windows Azure Powershell is avaiable
if ((Get-Module Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please make sure to install them from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}
    
<#
.SYNOPSIS
    Adds a new affinity group if it does not exist.
.DESCRIPTION
   Looks up the current subscription's (as set by Set-AzureSubscription cmdlet) affinity groups and creates a new
   affinity group if it does not exist.
.EXAMPLE
   New-AzureAffinityGroupIfNotExists -AffinityGroupNme newAffinityGroup -Locstion "West US"
.INPUTS
   None
.OUTPUTS
   None
#>
function New-AzureAffinityGroupIfNotExists
{
    param
    (
        
        # Name of the affinity group
        [Parameter(Mandatory = $true)]
        [String]
        $AffinityGroupName,
        
        # Location where the affinity group will be pointing to
        [Parameter(Mandatory = $true)]
        [String]
        $Location)
    
    $affinityGroup = Get-AzureAffinityGroup -Name $AffinityGroupName -ErrorAction SilentlyContinue
    if ($affinityGroup -eq $null)
    {
        New-AzureAffinityGroup -Name $AffinityGroupName -Location $Location -Label $AffinityGroupName `
        -ErrorVariable lastError -ErrorAction SilentlyContinue | Out-Null
        if (!($?))
        {
            throw "Cannot create the affinity group $AffinityGroupName on $Location"
        }
        Write-Verbose "Created affinity group $AffinityGroupName"
    }
    else
    {
        if ($affinityGroup.Location -ne $Location)
        {
            Write-Warning "Affinity group with name $AffinityGroupName already exists but in location `
            $affinityGroup.Location, not in $Location"
        }
    }
}


<#
.Synopsis
   Create an empty VNet configuration file.
.DESCRIPTION
   Create an empty VNet configuration file.
.EXAMPLE
    Add-AzureVnetConfigurationFile -Path c:\temp\vnet.xml
.INPUTS
   None
.OUTPUTS
   None
#>
function Add-AzureVnetConfigurationFile
{
    param ([string] $Path)
    
    $configFileContent = [Xml] "<?xml version=""1.0"" encoding=""utf-8""?>
            <NetworkConfiguration xmlns:xsd=""http://www.w3.org/2001/XMLSchema"" xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xmlns=""http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration"">
              <VirtualNetworkConfiguration>
                <Dns />
                <VirtualNetworkSites/>
              </VirtualNetworkConfiguration>
            </NetworkConfiguration>"

    $configFileContent.Save($Path)
}

<#
.SYNOPSIS
   Sets the provided values in the VNet file of a subscription's VNet file 
.DESCRIPTION
   It sets the VNetSiteName and AffinityGroup of a given subscription's VNEt configuration file.
.EXAMPLE
    Set-VNetFileValues -FilePath c:\temp\servvnet.xml -VNet testvnet -AffinityGroupName affinityGroup1
.INPUTS
   None
.OUTPUTS
   None
#>
function Set-VNetFileValues
{
    [CmdletBinding()]
    param (

        # The path to the exported VNet file
        [String]$FilePath, 
        
        # Name of the new VNet site
        [String]$VNet, 
        
        # The affinity group the new Vnet site will be associated with
        [String]$AffinityGroupName, 
        
        # Address prefix for the Vnet. For the sake of examples in this scripts, the smallest address space possible for Azure is default
        [String]$VNetAddressPrefix = "10.0.0.0/8", 
        
        # The name of the subnet to be added to the Vnet
        [String] $DefaultSubnetName = "Subnet-1", 
        
        # Addres space for the Subnet
        [String] $SubnetAddressPrefix = "10.0.0.0/29")
    
    [Xml]$xml = New-Object XML
    $xml.Load($filePath)
    
    $foundVirtualNetworkSite = $null
    if ($xml.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites -ne $null)
    {
        $foundVirtualNetworkSite = $xml.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.VirtualNetworkSite | Where-Object {$_.name -eq $VNet}
    }
    
    if ($foundVirtualNetworkSite -ne $null)
    {
        $foundVirtualNetworkSite.AffinityGroup = $AffinityGroupName
    }
    else
    {
        $virtualNetworkSites = $xml.NetworkConfiguration.VirtualNetworkConfiguration.GetElementsByTagName("VirtualNetworkSites")
        if ($null -ne $virtualNetworkSites)
        {
            
            $virtualNetworkElement = $xml.CreateElement("VirtualNetworkSite", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            
            $vNetSiteNameAttribute = $xml.CreateAttribute("name")
            $vNetSiteNameAttribute.InnerText = $VNet
            $virtualNetworkElement.Attributes.Append($vNetSiteNameAttribute) | Out-Null
            
            $affinityGroupAttribute = $xml.CreateAttribute("AffinityGroup")
            $affinityGroupAttribute.InnerText = $AffinityGroupName
            $virtualNetworkElement.Attributes.Append($affinityGroupAttribute) | Out-Null
            
            $addressSpaceElement = $xml.CreateElement("AddressSpace", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")            
            $addressPrefixElement = $xml.CreateElement("AddressPrefix", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $addressPrefixElement.InnerText = $VNetAddressPrefix
            $addressSpaceElement.AppendChild($addressPrefixElement) | Out-Null
            $virtualNetworkElement.AppendChild($addressSpaceElement) | Out-Null
            
            $subnetsElement = $xml.CreateElement("Subnets", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $subnetElement = $xml.CreateElement("Subnet", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $subnetNameAttribute = $xml.CreateAttribute("name")
            $subnetNameAttribute.InnerText = $DefaultSubnetName
            $subnetElement.Attributes.Append($subnetNameAttribute) | Out-Null
            $subnetAddressPrefixElement = $xml.CreateElement("AddressPrefix", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $subnetAddressPrefixElement.InnerText = $SubnetAddressPrefix
            $subnetElement.AppendChild($subnetAddressPrefixElement) | Out-Null
            $subnetsElement.AppendChild($subnetElement) | Out-Null
            $virtualNetworkElement.AppendChild($subnetsElement) | Out-Null
            
            $virtualNetworkSites.AppendChild($virtualNetworkElement) | Out-Null
        }
        else
        {
            throw "Can't find 'VirtualNetworkSite' tag"
        }
    }
    
    $xml.Save($filePath)
}

<#
.SYNOPSIS
   Creates a Virtual Network Site if it does not exist and sets the subnet details.
.DESCRIPTION
   Creates the VNet site if it does not exist. It first downloads the neetwork configuration for the subscription.
   If there is no network configuration, it creates an empty one first using the Add-AzureVnetConfigurationFile helper
   function, then updates the network file with the provided Vnet settings also by adding the subnet.
.EXAMPLE
   New-VNetSiteIfNotExists -VNetSiteName testVnet -SubnetName mongoSubnet -AffinityGroupName mongoAffinity
#>
function New-VNetSiteIfNotExists
{
    [CmdletBinding()]
    param
    (
        # Name of the Vnet site
        [Parameter(Mandatory = $true)]
        [String]
        $VNetSiteName,
        
        # Name of the subnet
        [Parameter(Mandatory = $true)]
        [String]
        $SubnetName,
        
        # THe affinity group the vnet will be associated with
        [Parameter(Mandatory = $true)]
        [String]
        $AffinityGroupName,
        
        # Address prefix for the Vnet. For the sake of examples in this scripts, 

        # the smallest address space possible for Azure is default
        [String]$VNetAddressPrefix = "10.0.0.0/8", 
        
        # The name of the subnet to be added to the Vnet
        [String] $DefaultSubnetName = "Subnet-1", 
        
        # Addres space for the Subnet
        [String] $SubnetAddressPrefix = "10.0.0.0/29")
    
    # Check the VNet site, and add it to the configuration if it does not exist.
    $vNet = Get-AzureVNetSite -VNetName $VNetSiteName -ErrorAction SilentlyContinue
    if ($vNet -eq $null)
    {
        $vNetFilePath = "$env:temp\$AffinityGroupName" + "vnet.xml"
        Get-AzureVNetConfig -ExportToFile $vNetFilePath | Out-Null
        if (!(Test-Path $vNetFilePath))
        {
            Add-AzureVnetConfigurationFile -Path $vNetFilePath
        }
        
        Set-VNetFileValues -FilePath $vNetFilePath -VNet $vNetSiteName -DefaultSubnetName $SubnetName -AffinityGroup $AffinityGroupName -VNetAddressPrefix $VNetAddressPrefix -SubnetAddressPrefix $SubnetAddressPrefix
        Set-AzureVNetConfig -ConfigurationPath $vNetFilePath -ErrorAction SilentlyContinue -ErrorVariable errorVariable | Out-Null
        if (!($?))
        {
            throw "Cannot set the vnet configuration for the subscription, please see the file $vNetFilePath. Error detail is: $errorVariable"
        }
        Write-Verbose "Modified and saved the VNET Configuration for the subscription"
        
        Remove-Item $vNetFilePath
    }
}

# Check the related affinity group. If the affinity group already exists, the location parameter will be ignored
$affinityGroupName = $VNetName + "affinity"
New-AzureAffinityGroupIfNotExists -AffinityGroupName $affinityGroupName -Location $Location
$affinityGroup = Get-AzureAffinityGroup -Name $affinityGroupName

# Check if Virtual Network Site exists
$existingVNetSite = Get-AzureVNetSite -VNetName $VNetName -ErrorAction SilentlyContinue
if ($existingVNetSite -ne $null)
{
    $vnetAffinityGroupLocation = (Get-AzureAffinityGroup -Name $existingVNetSite.AffinityGroup).Location
    $affinityGroupLocation = $affinityGroup.Location
    if ($vnetAffinityGroupLocation -ne $vnetAffinityGroupLocation)
    {
        throw "Existing VNet's location ($vnetAffinityGroupLocation) and affinity group's `
            location ($affinityGroupLocation) do not match."
    }
}
            
# If there is an exsiting affinity group with that name, override the location with the affinity group's
$Location = $affinityGroup.Location 

$subnetName = "$VNetName-Default"

# Override the default subnet prefix to allow for a larger one.
New-VNetSiteIfNotExists -VNetSiteName $VNetName -SubnetName $subnetName -SubnetAddressPrefix "10.0.0.0/8" -AffinityGroupName $affinityGroupName

foreach ($serviceNameKey in $ServicesAndTheirVMs.Keys)
{
        
    # Update the VM configurations to set the subnet
    $vms = $ServicesAndTheirVMs[$serviceNameKey]
    foreach ($vm in $vms)
    {
        $vm = $vm | Set-AzureSubnet $subnetName
    }

    $service = Get-AzureService -ServiceName $ServiceNameKey -ErrorAction SilentlyContinue            
    
    if ($service -eq $null)
    {
        # Deploy Virtual Machines to Virtual Network
        New-AzureVM -ServiceName $serviceNameKey -AffinityGroup $affinityGroupName -Location $Location -VMs $vms -VNetName $VNetName
    }
    else
    {
        New-AzureVM -ServiceName $serviceNameKey -VMs $vms
    }
}

