# Get-AzureWebsiteLogAnalysis #
## Description ##
Downloads IIS logs from an Azure Website and searches the log for any HTTP 400 and above status codes.

If Http logging is not enabled on the website, then it will enable logging if the EnableHttpLogging switch is specified.

The downloaded logs are unzipped and then fed into LogParser (if installed), querying for any HTTP status codes 400 and above.  The output of the LogParser query is output to the console.


**Note:** This script requires an Azure Storage Account to run.  The storage account can be specified by setting the subscription configuration.  For example,

    Set-AzureSubscription -SubscriptionName "MySubscription" -CurrentStorageAccount "MyStorageAccount"
    
## Scenario ##
You want to quickly check the IIS logs for an Azure Website to find HTTP errors.

## Requirements ##
- PowerShell Version 3.0
- Windows Azure PowerShell June 2013

## See Also ##
- Set-AzureSubscription
