# CopyFilesToAzureStorageContainer #
## Description ##
Copies files (in parallel) from a local folder to a named Azure storage blob container.  The copy operation can optionally recurse the local folder using the -Recurse switch.  The storage container is assumed to already exist unless the -CreateContainer switch is provided.


**Note:** This script requires an Azure Storage Account to run.  The storage account can be specified by setting the subscription configuration.  For example,

    Set-AzureSubscription -SubscriptionName "MySubscription" -CurrentStorageAccount "MyStorageAccount"
    
## Scenario ##
You want to efficiently copy files from a local folder to an Azure storage container.

## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013

## See Also ##
- Set-AzureSubscription
