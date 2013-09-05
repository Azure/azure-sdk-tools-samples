<#
.SYNOPSIS
   Remove all blobs (including snapshots)from one storage account.
.DESCRIPTION 
   This script will run through a single Azure storage account and delete all blobs in 
   all containers including snapshots.
.EXAMPLE
    .\Remove-BlobsFromAllContainers.ps1 -StorageAccountName "storageaccountname" -Force
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
           
    # StorageAccount name for BLOB deletion
    [Parameter(Mandatory = $true)] 
    [string]$StorageAccountName,

    # If specified, will remove the containers rather than individual blobs.
    [Parameter(Mandatory = $false)]
    [switch]$RemoveContainer,

    # If specified, will remove blobs without prompting user to confirm.
    [Parameter(Mandatory = $false)]
    [switch]$Force
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
    if ($RemoveContainer.IsPresent)
    {
        if (($Force.IsPresent) -or 
            ($PSCmdlet.ShouldContinue(
                "Remove container " + $container.Name + " and all blobs in the container?", 
                "Confirm Remove Operation")))
        {
            Remove-AzureStorageContainer -Name $container.Name -Force
        }
    }
    else
    {
        $blobsRemoved = 0

        Write-Verbose ("Searching Container: {0}" -f $container.Name)   
        $blobs = Get-AzureStorageBlob -Container $container.Name -Context $context 

        if ($blobs -ne $null)
        {
            if ($blobs.Count -gt 0)
            {
                if (($Force.IsPresent) -or 
                    ($PSCmdlet.ShouldContinue(
                        "Remove " + $blobs.Length + " files from container " + $container.Name + "?", 
                        "Confirm Remove Operation")))
                {
                    foreach ($blob in $blobs)
                    { 
                        Write-Verbose ("Removing Blob: {0}" -f $blob.Name) 
                        Remove-AzureStorageBlob -ICloudBlob $blob.ICloudBlob -Context $context
                        $blobsRemoved += 1
                    }
                } 
            }
        }

        Write-Verbose ("{0} blobs removed from container {1}." -f $blobsRemoved, $container.Name)
    }
} 

