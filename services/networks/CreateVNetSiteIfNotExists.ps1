<#
.Synopsis
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
    Param
    (
        # Name of the Vnet site
        [Parameter(Mandatory = $true)]
        [string]
        $VNetSiteName,

        # Name of the subnet
        [Parameter(Mandatory = $true)]
        [string]
        $SubnetName,

        # THe affinity group the vnet will be associated with
        [Parameter(Mandatory = $true)]
        [string]
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