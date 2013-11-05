# CreateVNet #

## Description ##
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
    
## Scenario ##
You want to create a Virtual Network on Windows Azure.

## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013

## See Also ##
- CreateNewADDSForest.ps1
- CreateWebSQLDeveloperMachine.ps1
- CreateSharePointDeveloperMachine.ps1
- CreateSharePointDeveloperMachineInDomain.ps1
