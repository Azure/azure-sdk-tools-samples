<#
.SYNOPSIS
   Copy all Virtual Hard Disks (VHD's) from the current subscription to a different 
   subscription and storage account.
.DESCRIPTION
   Start's an asynchronous copy of VHD's to a different subscription and storage account.
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
        # Copy Blob
        $storageBlobsCopied += Start-AzureStorageBlobCopy -SrcUri $src -DestContainer $DestContainerName `
                                  -DestBlob $vhdName –destContext $DestContext
    }
}

# Wait a few seconds before showing status of copy operations.
Write-Verbose "Gathering storage blob copy status..."
Start-Sleep 3

# Show the status of each blob copy operation.
foreach ($blob in $storageBlobsCopied)
{
    $blob | Get-AzureStorageBlobCopyState | Format-Table -AutoSize -Property Status,BytesCopied,TotalBytes,Source
}
