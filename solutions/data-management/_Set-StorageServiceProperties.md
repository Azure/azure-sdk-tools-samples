# Set-StorageServiceProperties #
## Description ##
Sets storage logging and metrics settings on storage accounts in the current subscription.  Settings can be enable or disabled.

**Note:** This script requires an Azure Storage Account to run.  The storage account can be specified by setting the subscription configuration.  For example,

    Set-AzureSubscription -SubscriptionName "MySubscription" -CurrentStorageAccount "MyStorageAccount"
    
## Scenario ##
You want to enable or disable logging and/or metrics on one or more storage accounts in a subscription.

## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013

## See Also ##
- Set-AzureSubscription