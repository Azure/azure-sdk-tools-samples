# Add-DataDisksToVM#
## Description ##
Creates a Virtual Machine (small) configured with two data disks.  After the Virtual Machine is provisioned and running, the data disks are then formatted and drive letters assigned.  User is prompted for credentials to use to provision the new Virtual Machine.

**Note:** This script requires an Azure Storage Account to run.  The storage account can be specified by setting the subscription configuration.  For example,

    Set-AzureSubscription -SubscriptionName "MySubscription" -CurrentStorageAccount "MyStorageAccount"
    
## Scenario ##
You want to provision a Virtual Machine with one or more data disks pre-formatted.
## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013

## See Also ##
- Set-AzureSubscription
