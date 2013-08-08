
<#
.SYNOPSIS
    Turn on storage logging and metrics for all storage accounts under one Subscription.  
.DESCRIPTION 
   This script will turn on the logging and metrics for all storage accounts under the default subscription. 
   You can also, provide the storage account name to restrict the action to that one. 
   
.EXAMPLE
    Enable-AzureStorageMeteringAndLogs.ps1 -StorageAccountName "StorageAccountName"
#>


param(
    [CmdletBinding( SupportsShouldProcess=$true)]
         
    # The Storage account name to which you will enable logging and monitoring  
    [Parameter(Mandatory = $false)]
    [String]$StorageAccountName
           
    )
    
<#
.SYNOPSIS
     Enable the logging and monitoring for the storage account 
.DESCRIPTION
     1. Get the Storage account by name
     2. Configure the Logging and Metering properties.
     3. Set them to the storage account. 
.EXAMPLE
     EnableMeteringtoStorage -storageAccount "storageAccount"
#>
Function EnableMeteringtoStorage($StorageAccount)
{

    $name = $StorageAccount.StorageAccountName 
    Write-Verbose ("[Start] Enabling meter and Logging for storage account {0}" -f $name )  
    $fullkeys = Get-AzureStorageKey -StorageAccountName $name 
    $key = $fullkeys[0].Primary 
    $context = New-AzureStorageContext -StorageAccountName $name -StorageAccountKey $key 
    $blobClient = $context.StorageAccount.CreateCloudBlobClient(); 

    #Configure the Logging parameters 
    $sp = New-Object -TypeName Microsoft.WindowsAzure.Storage.Shared.Protocol.ServiceProperties 
    $sp.Logging.Version = "1.0"; 
    $sp.Logging.RetentionDays = 7; 
    $sp.Logging.LoggingOperations = [Microsoft.WindowsAzure.Storage.Shared.Protocol.LoggingOperations]::All; 

    #Configure the metrics parameters 
    $sp.Metrics.Version = "1.0"; 
    $sp.Metrics.MetricsLevel = [Microsoft.WindowsAzure.Storage.Shared.Protocol.MetricsLevel]::ServiceAndApi; 

    #Set the service properties 
    $blobClient.SetServiceProperties($sp); 

    #display service properties 
    $blobClient.GetServiceProperties(); 
    Write-Verbose ("[Finish] Enabling meter and Logging for storage account {0}" -f $name )  
  }

Set-StrictMode -Version 3


# Mark the start time of the script execution
$startTime = Get-Date

# Check if Windows Azure Powershell is available
if ((Get-Module Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please make sure to install them 
            from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}

# Execute the Enabling Meter and Logging function if the Storage Account Name is provided as parameter
if ($StorageAccountName.Length -gt 1)
{
    $storageAccount = Get-AzureStorageAccount | Where-Object {$_.StorageAccountName -eq $StorageAccountName } 
    # Verify if the Storage Account exists
    if($storageAccount -eq $null) {
        #exit
        throw "Storage account does no exists" 
    }
    else 
    {
        #Execute the Enabling Meter and Logging function
        EnableMeteringtoStorage($storageAccount)
       
    }
    
}
else
{
    #Get the storage accounts for the default suscription
    $accounts = Get-AzureStorageAccount
   
    #Iterate
    foreach($StorageAccount in $accounts)
     { 
        #Execute the Enabling Meter and Logging function
        EnableMeteringtoStorage($StorageAccount)
     } 
}

# Output the time consumed in seconds
$finishTime = Get-Date
Write-Verbose ("Total time used (seconds): {0}" -f ($finishTime - $startTime).TotalSeconds)
