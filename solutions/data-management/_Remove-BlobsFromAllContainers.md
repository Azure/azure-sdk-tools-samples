# Remove-BlobsFromAllContainers #
## Description ##
Removes blobs from blob storage containers.  The script will enumerate through all containers and remove the blobs, maintaining the existence of the container.  If you want to remove the containers, then you can include the RemoveContainer switch.  This will be faster than removing the individual blobs in the container but will require you to recreate the container if you wish to use it again.

Prior to removing all blobs in a container or the container itself, the user is prompted to confirm the operation.  This enables you to apply the operation to some (but not all) containers.  If you include the Force switch, then all blobs will be removed from all containers and all containers will be removed if the RemoveContainer switch is applied.

**Note:** This script requires an Azure Storage Account to run.  The storage account can be specified by setting the subscription configuration.  For example,

    Set-AzureSubscription -SubscriptionName "MySubscription" -CurrentStorageAccount "MyStorageAccount"
    
## Scenario ##
You want to remove all blobs from a container or set of containers.  Or, you want to remove containers and the blobs within the container.

## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013

## See Also ##
- Set-AzureSubscription