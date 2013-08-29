<#
.SYNOPSIS
   Copy all Virtual Hard Disks (VHD's) from the current subscription to a different 
   storage account.
.DESCRIPTION
   Start's an asynchronous copy of VHD's to a different storage account.  The storage
   account can be in the current subscription or in a different subscription.
.EXAMPLE
   .\CopyAllVhdBetweenSubscription.ps1 
         -DestContainerName "DestinationContainerName" 
         -DestStorageAccountName "DestinationStorageAccount" 
         -DestStorageAccountKey "DestinationStorageKey"
#>
param 
(
    # Destination Storage Container name 
    [Parameter(Mandatory = $true)]
    [String]$DestContainerName,

    # Destination Storage Account name 
    [Parameter(Mandatory = $true)]
    [String]$DestStorageAccountName,

    # Destination Storage Account Key 
    [Parameter(Mandatory = $true)]
    [String]$DestStorageAccountKey
)

# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3

# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
$VerbosePreference = "Continue"

# Check if Windows Azure Powershell is avaiable
if ((Get-Module -ListAvailable Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please install from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}

# Make sure destination container exists. Create if it does not.
$DestContext = New-AzureStorageContext –StorageAccountName $DestStorageAccountName  -StorageAccountKey $DestStorageAccountKey
$storageContainer = Get-AzureStorageContainer -Name $DestContainerName -Context $DestContext -ErrorAction SilentlyContinue
if ($storageContainer -eq $null)
{
    Write-Verbose "Creating container '$DestContainerName'."
    New-AzureStorageContainer -Name $DestContainerName -Context $DestContext
}

# Copy each VHD in the current storage account.
$storageBlobsCopied = @()
foreach ($azureDisk in Get-AzureDisk)
{
    $src = $azureDisk.MediaLink
    $vhdName = $azureDisk.MediaLink.Segments | Where-Object { $_ -like "*.vhd" }

    if ($vhdName -ne $null)
    {
        # Schedule a blob copy operation
        $storageBlobsCopied += Start-AzureStorageBlobCopy -SrcUri $src -DestContainer $DestContainerName `
                                  -DestBlob $vhdName –destContext $DestContext
    }
}

# Show the status of each blob copy operation.
do
{
    Write-Verbose "Checking storage blob copy status..."
    Write-Verbose "Press Ctrl-C anytime to stop checking status."
    Start-Sleep 10

    $continue = $false

    foreach ($blob in $storageBlobsCopied)
    {
        # Check the copy state for each blob.
        $copyState = $blob | Get-AzureStorageBlobCopyState

        # Continue checking status as long as at least one operations is still pending.
        if (!$continue)
        {
            $continue = $copyState.Status -eq [Microsoft.WindowsAzure.Storage.Blob.CopyStatus]::Pending
        }

        # Show copy status.
        $copyState | Format-Table -AutoSize -Property Status,BytesCopied,TotalBytes,Source
    }
} while ($continue)
