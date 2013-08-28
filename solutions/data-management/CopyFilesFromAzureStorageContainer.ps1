<#
.SYNOPSIS
    Copies files from a storage container to a local folder.
.DESCRIPTION
    Copies blobs from a single storage container or all storage containers to a local
    directory.  If the blobs have "/" in the name to represent a directory hierarchy,
    then the script will recreate that directory hierarchy under the local destination
    path specified.

    The script supports the -Whatif switch so you can quickly see how complex the copy
    operation would be.

    Note: This script requires an Azure Storage Account to run.  The storage account 
    can be specified by setting the subscription configuration.  For example:
        Set-AzureSubscription -SubscriptionName "MySubscription" -CurrentStorageAccount "MyStorageAccount"
.EXAMPLE
    .\CopyFilesFromAzureStorageContainer -LocalPath "c:\users\<myUserName>\documents" `
        -StorageContainer "myuserdocuments" -Recurse -CreateStorageContainer
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # The destination path to copy files to.
    [Parameter(Mandatory = $true)]
    [string]$LocalPath,

    # The name of the storage container to copy files from.  
    # This parameter is ignored if -All is specified.
    [Parameter(Mandatory = $false)]
    [string]$StorageContainer,

    # If specified, will download all containers.  
    [Parameter(Mandatory = $false)]
    [switch]$All,

    # If specified, will create the destination path.
    [Parameter(Mandatory = $false)]
    [switch]$CreateLocalPath,
    
    # If specified, will overwrite existing files in the destination path.
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

<#
.SYNOPSIS
    Downloads all blobs in a container to a local file path.
.DESCRIPTION
    A subdirectory is created in the local path given matching the container name.
    All blobs in the container are copied to the subdirectory.
.EXAMPLE
    DownloadContainer -StoraceContainerName "conatinername" -DestLocalPath "c:\Temp"
#>
function DownloadContainer
{
    param(
        # The name of storage container to copy.
        [Parameter(Mandatory = $true)]
        [string]$SourceContainerName, 

        # The destination local path to copy to.
        [Parameter(Mandatory = $true)]
        $DestLocalPath)

    # Get a reference to the container.
    $container = Get-AzureStorageContainer -Name $SourceContainerName -ErrorAction SilentlyContinue
    if ($container -eq $null)
    {
        throw "Unable to reach storage container '$SourceContainerName'."
    }

    # Copy blobs from storage container to local file path.
    $blobs = Get-AzureStorageBlob -Container $SourceContainerName
    foreach ($blob in $blobs)
    {
        $sourceBlob = $SourceContainerName + "\" + $blob.Name
        $destFilePath = $DestLocalPath + "\" + $blob.Name

        # Create a sub-directory using the container name.
        $destDirectory = [System.IO.Path]::GetDirectoryName($destFilePath)
        $destFilePath = $destDirectory + "\" + [System.IO.Path]::GetFileName($destFilePath)
        if (-not (Test-Path $destDirectory -PathType Container))
        {
            New-Item -Path $destDirectory -ItemType Directory
        }
  
        # Copy blob from container to local path.
        if ($PSCmdlet.ShouldProcess($destFilePath, "Copy File"))
        {
            Get-AzureStorageBlobContent `
                -Container $SourceContainerName -Blob $blob.Name -Destination $destFilePath | `
                    Format-Table -Property Length,Name -AutoSize
        }
    }
}

# Ensure the local path given exists. Create it if switch specified to do so.
if (-not (Test-Path $LocalPath))
{
    if ($CreateLocalPath.IsPresent)
    {
        New-Item -Path $LocalPath -ItemType Directory
    }
    else
    {
        throw "Path '$LocalPath' does not exist.  Specify an existing path or provide the CreateLocalPath switch to create it."
    }
}

$localContainerPath = ""
if ($All.IsPresent)
{
    # Enumerate through all containers and download blobs for each one.
    $containers = Get-AzureStorageContainer 
    foreach ($container in $containers)
    {
        $localContainerPath = $LocalPath + "\" + $container.Name
        DownloadContainer -SourceContainerName $container.Name -DestLocalPath $localContainerPath
    }

}
elseif ($StorageContainer -ne $null -and $StorageContainer -ne "" )
{
    # Download blobs for the specified container.    
    $localContainerPath = $LocalPath + "\" + $StorageContainer
    DownloadContainer -SourceContainerName $StorageContainer -DestLocalPath $localContainerPath
}
else
{
    throw "Provide a valid storage container name using the 'StorageContainer' parameter or include the -All switch to copy all containers."
}
