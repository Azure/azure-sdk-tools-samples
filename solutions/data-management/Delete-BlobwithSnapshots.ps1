<#
.SYNOPSIS
   Remove all blobs (including snapshots)from one storage account.
.DESCRIPTION 
   This script will run through a single Azure storage account and delete all blobs in 
   all containers including snapshots.
    `
.EXAMPLE
    Delete-BlobWithSnapshots.ps1 -StorageAccountName "storageaccountname" 
#>
param(
           
    # StorageAccount name for BLOB deletion
    [Parameter(Mandatory = $true)] 
    [string]$StorageAccountName
    )

Set-StrictMode -Version 3

# getting Azure storage account key
$fullkeys = Get-AzureStorageKey -StorageAccountName $StorageAccountName 

# the script will be using primary key. 
$key = $fullkeys[0].Primary

# getting storage account content 
$context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $key 

$containers = Get-AzureStorageContainer -Context $context 
# loop through each container and get list of blobs for each container and delete
foreach($container in $containers) 
{ 
    Write-Verbose ("Searching Container: {0}" -f $container.Name)   
    $blobs = Get-AzureStorageBlob -Container $container.Name -Context $context 
    foreach ($blob in $blobs) 
    { 
        Write-Verbose ("Removing Blob: {0}" -f $blob.Name) 
        
            Remove-AzureStorageBlob -ICloudBlob $blob.ICloudBlob -Context $context 
        
    } 
} 

