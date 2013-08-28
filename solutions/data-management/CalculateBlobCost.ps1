<#
.SYNOPSIS
    Calculates cost of all blobs in a container or storage account.
.DESCRIPTION
    Enumerates all blobs in either one container or one storage account and sums
    up all costs associated.  This includes all block and page blobs, all metadata
    on either blobs or containers.  It also includes both committed and uncommitted
    blocks in the case that a blob is partially uploaded.
 
    The details of the calculations can be found in this post:
    http://blogs.msdn.com/b/windowsazurestorage/archive/2010/07/09/understanding-windows-azure-storage-billing-bandwidth-transactions-and-capacity.aspx
 
    Note: This script requires an Azure Storage Account to run.  The storage account 
    can be specified by setting the subscription configuration.  For example:
    Set-AzureSubscription -SubscriptionName "MySubscription" -CurrentStorageAccount "MyStorageAccount"
.EXAMPLE
    .\CalculateBlobCost.ps1 -StorageAccountName "mystorageaccountname"
    .\CalculateBlobCost.ps1 -StorageAccountName "mystorageaccountname" -ContainerName "mycontainername"
#>
 
param(
     # The name of the storage account to enumerate.
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,
 
   # The name of the storage container to enumerate.
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ContainerName
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

<#
.SYNOPSIS
   Gets the size (in bytes) of a blob.
.DESCRIPTION
   Given a blob name, sum up all bytes consumed including the blob itself and any metadata,
   all committed blocks and uncommitted blocks.

   Formula reference for calculating size of blob:
       http://blogs.msdn.com/b/windowsazurestorage/archive/2010/07/09/understanding-windows-azure-storage-billing-bandwidth-transactions-and-capacity.aspx
.INPUTS
   $Blob - The blob to calculate the size of.
.OUTPUTS
   $blobSizeInBytes - The calculated sizeo of the blob.
#>
function Get-BlobBytes
{
    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.WindowsAzure.Management.Storage.Model.ResourceModel.AzureStorageBlob]$Blob)
 
    # Base + blob name
    $blobSizeInBytes = 124 + $Blob.Name.Length * 2
 
    # Get size of metadata
    $metadataEnumerator = $Blob.ICloudBlob.Metadata.GetEnumerator()
    while ($metadataEnumerator.MoveNext())
    {
        $blobSizeInBytes += 3 + $metadataEnumerator.Current.Key.Length + $metadataEnumerator.Current.Value.Length
    }
 
    if ($Blob.BlobType -eq [Microsoft.WindowsAzure.Storage.Blob.BlobType]::BlockBlob)
    {
        $blobSizeInBytes += 8
        $Blob.ICloudBlob.DownloadBlockList() | 
            ForEach-Object { $blobSizeInBytes += $_.Length + $_.Name.Length }
    }
    else
    {
        $Blob.ICloudBlob.GetPageRanges() | 
            ForEach-Object { $blobSizeInBytes += 12 + $_.EndOffset - $_.StartOffset }
    }

    return $blobSizeInBytes
}
 
<#
.SYNOPSIS
   Gets the size (in bytes) of a blob container.
.DESCRIPTION
   Given a container name, sum up all bytes consumed including the container itself and any metadata,
   all blobs in the container together with metadata, all committed blocks and uncommitted blocks.
.INPUTS
   $Container - The container to calculate the size of. 
.OUTPUTS
   $containerSizeInBytes - The calculated size of the container.
#>
function Get-ContainerBytes
{
    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.WindowsAzure.Storage.Blob.CloudBlobContainer]$Container)
 
    # Base + name of container
    $containerSizeInBytes = 48 + $Container.Name.Length * 2
 
    # Get size of metadata
    $metadataEnumerator = $Container.Metadata.GetEnumerator()
    while ($metadataEnumerator.MoveNext())
    {
        $containerSizeInBytes += 3 + $metadataEnumerator.Current.Key.Length + 
                                     $metadataEnumerator.Current.Value.Length
    }

    # Get size for Shared Access Policies
    $containerSizeInBytes += $Container.GetPermissions().SharedAccessPolicies.Count * 512
 
    # Calculate size of all blobs.
    $blobCount = 0
    Get-AzureStorageBlob -Context $storageContext -Container $Container.Name | 
        ForEach-Object { 
            $containerSizeInBytes += Get-BlobBytes $_ 
            $blobCount++
            }
 
    return @{ "containerSize" = $containerSizeInBytes; "blobCount" = $blobCount }
}

$storageAccount = Get-AzureStorageAccount -StorageAccountName $StorageAccountName -ErrorAction SilentlyContinue
if ($storageAccount -eq $null)
{
    throw "The storage account specified does not exist in this subscription."
}
 
# Instantiate a storage context for the storage account.
$storagePrimaryKey = (Get-AzureStorageKey -StorageAccountName $StorageAccountName).Primary
$storageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storagePrimaryKey

# Get a list of containers to process.
$containers = New-Object System.Collections.ArrayList
if ($ContainerName.Length -ne 0)
{
    $container = Get-AzureStorageContainer -Context $storageContext `
                      -Name $ContainerName -ErrorAction SilentlyContinue | 
                          ForEach-Object { $containers.Add($_) } | Out-Null
}
else
{
    Get-AzureStorageContainer -Context $storageContext | ForEach-Object { $containers.Add($_) } | Out-Null
}

# Calculate size.
$sizeInBytes = 0
if ($containers.Count -gt 0)
{
    $containers | ForEach-Object { 
                      $result = Get-ContainerBytes $_.CloudBlobContainer                   
                      $sizeInBytes += $result.containerSize
                      Write-Verbose ("Container '{0}' with {1} blobs has a size of {2:F2}MB." -f `
                          $_.CloudBlobContainer.Name, $result.blobCount, ($result.containerSize / 1MB))
                      }
    Write-Output ("Total size calculated for {0} containers is {1:F2}GB." -f $containers.Count, ($sizeInBytes / 1GB))

    # Launch default browser to azure calculator for data management.
    Start-Process -FilePath http://www.windowsazure.com/en-us/pricing/calculator/?scenario=data-management
}
else
{
    Write-Warning "No containers found to process in storage account '$StorageAccountName'."
}
