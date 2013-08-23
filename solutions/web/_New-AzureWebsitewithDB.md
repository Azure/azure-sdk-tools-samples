# New-AzureWebsitewithDB #
## Description ##
Creates a Windows Azure Website and links to a SQL Azure DB and a storage account.  

If the storage account specified does not exist, the storage account will be created.

When the SQL Azure database server is created, a firewall rule is added for the client's IP Address and also for Azure Services (to connect to from the new WebSite).

The user is prompted for administrator credentials to be used when creating the login for the new SQL Azure database

**Note:** This script requires an Azure Storage Account to run.  The storage account can be specified by setting the subscription configuration.  For example,

    Set-AzureSubscription -SubscriptionName "MySubscription" -CurrentStorageAccount "MyStorageAccount"
    
## Scenario ##
You want to quickly create a new Azure Website and link it to an Azure storage account and a new SQL Azure database.

## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013

## See Also ##
- Set-AzureSubscription
