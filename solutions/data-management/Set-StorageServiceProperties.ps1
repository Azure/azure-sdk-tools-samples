<#
.SYNOPSIS
    Turn on/off storage logging and metrics for all storage accounts under one Subscription.  
.DESCRIPTION 
   This script will turn on/off the logging and metrics for all storage accounts under the default subscription. 
   You can also, provide the storage account name to restrict the action to that one. 
.EXAMPLE
   Enable logging and metrics for a single storage account.
   .\Set-StorageServiceProperties.ps1 -StorageAccountName "StorageAccountName" -Enable

   Disable logging and metrics for all storage accounts.
   .\Set-StorageServiceProperties.ps1 -Disable -All

#>

param(
    [CmdletBinding( SupportsShouldProcess=$true)]

    # The Storage account name to enable logging and monitoring on.
    [Parameter(Mandatory = $false)]
    [String]$StorageAccountName,

    # Turn logging on.
    [Parameter(Mandatory = $false)]
    [switch]$Enable,
         
    # Turn logging off.
    [Parameter(Mandatory = $false)]
    [switch]$Disable,

    # If specfied, will enable logging and metrice for all storage accounts in the subscription.
    [Parameter(Mandatory = $false)]
    [switch]$All)

# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3

# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
$VerbosePreference = "Continue"

# Check if Windows Azure Powershell is avaiable
if ((Get-Module -ListAvailable Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please install from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}
    
<#
.SYNOPSIS
     Enable the logging and monitoring for the storage account. 
.DESCRIPTION
    Initializes an instance of ServiceProperties and then sets the service
    properties for all three storage services (blob, table, queue)
.EXAMPLE
     EnableMeteringtoStorage -Name "storageAccountName"
#>
function EnableMeteringtoStorage
{
    param(
        # Name of storage account
        [Parameter(Mandatory = $true)]
        [String]
        $Name,

        # Name of storage account
        [Parameter(Mandatory = $true)]
        [Bool]
        $SetDefault)

    # Initialize ServiceProperties Instance
  
    # Configure the Logging parameters 
    $sp = New-Object -TypeName Microsoft.WindowsAzure.Storage.Shared.Protocol.ServiceProperties 
    if ($SetDefault)
    {
        Write-Verbose ("Disabling logging and metrics for storage account {0}" -f $Name )  
        $sp.Logging.Version = "1.0"; 
        $sp.Logging.RetentionDays = $null;
        $sp.Logging.LoggingOperations = [Microsoft.WindowsAzure.Storage.Shared.Protocol.LoggingOperations]::None; 

        # Configure the metrics parameters 
        $sp.Metrics.Version = "1.0";
        $sp.Metrics.RetentionDays = $null;
        $sp.Metrics.MetricsLevel = [Microsoft.WindowsAzure.Storage.Shared.Protocol.MetricsLevel]::None; 
    }
    else
    {
        Write-Verbose ("Enabling logging and metrics for storage account {0}" -f $Name )  
        $sp.Logging.Version = "1.0"; 
        $sp.Logging.RetentionDays = 7; 
        $sp.Logging.LoggingOperations = [Microsoft.WindowsAzure.Storage.Shared.Protocol.LoggingOperations]::All; 

        # Configure the metrics parameters 
        $sp.Metrics.Version = "1.0";
        $sp.Metrics.RetentionDays = 7;
        $sp.Metrics.MetricsLevel = [Microsoft.WindowsAzure.Storage.Shared.Protocol.MetricsLevel]::ServiceAndApi; 
    }

    # Create a storage context for the account.
    $keys = Get-AzureStorageKey -StorageAccountName $Name
    $context = New-AzureStorageContext -StorageAccountName $Name -StorageAccountKey $keys.Primary

    #Set the service properties for the blob service.
    $blobClient = $context.StorageAccount.CreateCloudBlobClient();
    $blobClient.SetServiceProperties($sp); 

    #Set the service properties for the table service.
    $tableClient = $context.StorageAccount.CreateCloudTableClient();
    $tableClient.SetServiceProperties($sp); 

    #Set the service properties for the table service.
    $queueClient = $context.StorageAccount.CreateCloudQueueClient();
    $queueClient.SetServiceProperties($sp); 
}

# Validate that either Enable or Disable was specified.
if (!($Enable.IsPresent) -and !($Disable.IsPresent))
{
    throw "You must specify either the Enable or Disable switch."
}

$accounts = $null

if ($All.IsPresent)
{
    #Get all the storage accounts for the default suscription
    $accounts = Get-AzureStorageAccount
}
elseif ($StorageAccountName -ne $null)
{
    # Get a specific storage account by name.
    $accounts = Get-AzureStorageAccount | Where-Object {$_.StorageAccountName -eq $StorageAccountName } 
}

# Enable logging and metrics for storage account(s).
if ($accounts -ne $null)
{
    foreach($StorageAccount in $accounts)
    { 
        EnableMeteringtoStorage -Name $StorageAccount.StorageAccountName -SetDefault $Disable.IsPresent
    } 
}
else
{
    Write-Warning "No storage account found.  Specify a storage account by name or include the -All switch."
}
