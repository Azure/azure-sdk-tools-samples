<#
.SYNOPSIS
  Creates a cluster with specified configuration.
.DESCRIPTION
  Creates a HDInsight cluster configured with one storage account and default metastores. If storage account or container are not specified they are created 
  automatically under the same name as the one provided for cluster. If ClusterSize is not specified it defaults to create small cluster with 2 nodes. 
  User is prompted for credentials to use to provision the cluster.

  During the provisioning operation which usually takes around 15 minutes the script monitors status and reports when cluster is transitioning through the 
  provisioning states.

  Note: This script requires an Azure HDInsight cmdlets to be installed on the machine in addition to Azure PowerShell Tools. Azure HDInsight cmdlets can be 
  installed according to the instructions here: https://hadoopsdk.codeplex.com/wikipage?title=PowerShell%20Cmdlets%20for%20Cluster%20Management

.EXAMPLE
  .\New-HDInsightCluster.ps1 -Cluster "MyClusterName" -Location "North Europe"

  .\New-HDInsightCluster.ps1 -Cluster "MyClusterName" -Location "North Europe"  `
      -DefaultStorageAccount mystorage -DefaultStorageContainer myContainer `
      -ClusterSizeInNodes 4
#>

param (
    # Cluster dns name to create
    [Parameter(Mandatory = $true)]
    [String]$Cluster,
    
    # Location
    [Parameter(Mandatory = $true)]
    [String]$Location,
    
    # Blob storage account that new cluster will be connected to
    [Parameter(Mandatory = $false)]
    [String]$DefaultStorageAccount = "",
    
    # Blob storage container that new cluster will use by default
    [Parameter(Mandatory = $false)]
    [String]$DefaultStorageContainer = "",
    
    # Number of data nodes that will be provisioned in the new cluster
    [Parameter(Mandatory = $false)]
    [Int32]$ClusterSizeInNodes = 2,

    # Credentials to be used for the new cluster
    [Parameter(Mandatory = $false)]
    [PSCredential]$Credential = $null)


# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3

# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
$VerbosePreference = "Continue"

# Check if Windows Azure Powershell is avaiable
if ((Get-Module -ListAvailable Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please make sure to install them from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}

# Check if HDInsight Powershell is avaiable
$module = Get-Module -Name Microsoft.WindowsAzure.Management.HDInsight.Cmdlet
if ($module -eq $null)
{
    throw "HDInsight Powershell module not found! Please make sure to install them from https://hadoopsdk.codeplex.com/wikipage?title=PowerShell%20Cmdlets%20for%20Cluster%20Management"
}

# Get the current subscription
$subid = Get-AzureSubscription -Current | %{ $_.SubscriptionId }

# Create storage account and container if not specified
if ($DefaultStorageAccount -eq "") {
    $DefaultStorageAccount = $Cluster.ToLowerInvariant()
    
    # Check if account already exists then use it
    $storageAccount = Get-AzureStorageAccount -StorageAccountName $DefaultStorageAccount -ErrorAction SilentlyContinue
    if ($storageAccount -eq $null) {
        Write-Verbose "Creating new storage account $DefaultStorageAccount."
        $storageAccount = New-AzureStorageAccount –StorageAccountName $DefaultStorageAccount -Location $Location
    } else {
        Write-Verbose "Using existing storage account $DefaultStorageAccount."
    }
}

# Check if container already exists then use it
if ($DefaultStorageContainer -eq "") {
    $storageContext = New-AzureStorageContext –StorageAccountName $DefaultStorageAccount -StorageAccountKey (Get-AzureStorageKey $DefaultStorageAccount).Primary

    $DefaultStorageContainer = $DefaultStorageAccount
    $storageContainer = Get-AzureStorageContainer -Name $DefaultStorageContainer -Context $storageContext -ErrorAction SilentlyContinue
    if ($storageContainer -eq $null) {
        Write-Verbose "Creating new storage container $DefaultStorageContainer."
        $storageContainer = New-AzureStorageContainer -Name $DefaultStorageContainer -Context $storageContext
    } else {
        Write-Verbose "Using existing storage container $DefaultStorageContainer."
    }
}

if ($Credential -eq $null) {
    # Get user credentials to use when provisioning the cluster.
    Write-Verbose "Prompt user for administrator credentials to use when provisioning the cluster."
    $credential = Get-Credential
    Write-Verbose "Administrator credentials captured.  Use these credentials to login to the cluster when the script is complete."
}

# Initiate cluster provisioning
$storage = Get-AzureStorageAccount $DefaultStorageAccount

$provJob = Start-Job –Scriptblock {
    param(
        $subid,
        $Cluster,
        $Location,
        $storage,
        $DefaultStorageAccount,
        $DefaultStorageContainer,
        $creds,
        $ClusterSizeInNodes,
        $modulePath
    )
    Import-Module $modulePath
    New-AzureHDInsightCluster -Subscription $subid -Name $Cluster -Location $Location `
        -DefaultStorageAccountName ($storage.StorageAccountName + ".blob.core.windows.net") `
        -DefaultStorageAccountKey (Get-AzureStorageKey $DefaultStorageAccount).Primary `
        -DefaultStorageContainerName $DefaultStorageContainer `
        -Credentials $creds `
        -ClusterSizeInNodes $ClusterSizeInNodes
} -Arg @(`
        $subid,`
        $Cluster,`
        $Location,`
        $storage,`
        $DefaultStorageAccount,`
        $DefaultStorageContainer,`
        $credential,`
        $ClusterSizeInNodes,`
        $module.Path)

Write-Host "Sending request to provision cluster $Cluster"

# Poll and report status of the cluster during the provisioning process
Start-Sleep -s 15;
$state = ""
while($provJob.State -ne "Completed" -and $state -ne "Running") {
    Start-Sleep -s 5;
    $clusterObj = (Get-AzureHDInsightCluster -Subscription $subid -Name $Cluster)
    if ($clusterObj.State -ne $state -and $clusterObj.State -ne $null -and $clusterObj.State -ne "") {
        $state = $clusterObj.State
        Write-Host ("Status: " + $clusterObj.State)
    }
}

# Report errors from the background job if any
Receive-Job $provJob
