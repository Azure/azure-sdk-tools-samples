<#
.SYNOPSIS
  Creates a cluster with specified configuration.
.DESCRIPTION
  Creates a HDInsight cluster configured with one storage account and default metastores. User is prompted for credentials to use to provision the cluster.
  During the provisioning operation which usually takes around 15 minutes the script monitors status and report when cluster is transitioning through the 
  provisioning states.

  Note: This script requires an Azure HDInsight cmdlets to be installed on the machine in addition to Azure PowerShell Tools. Azure HDInsight cmdlets can be 
  installed according to the instructions here: https://hadoopsdk.codeplex.com/wikipage?title=PowerShell%20Cmdlets%20for%20Cluster%20Management

  Note: Current version of the script expects storage container to exist.

.EXAMPLE
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
    [Parameter(Mandatory = $true)]
    [String]$DefaultStorageAccount,
    
    # Blob storage container that new cluster will use by default
    [Parameter(Mandatory = $true)]
    [String]$DefaultStorageContainer,
    
    # Number of data nodes that will be provisioned in the new cluster
    [Parameter(Mandatory = $true)]
    [Int32]$ClusterSizeInNodes)


# The script has been tested on Powershell 3.0
Set-StrictMode -Version 3

# Following modifies the Write-Verbose behavior to turn the messages on globally for this session
$VerbosePreference = "Continue"


# Check if Windows Azure Powershell is avaiable
if ((Get-Module -ListAvailable Azure) -eq $null)
{
    throw "Windows Azure Powershell not found! Please make sure to install them from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
}

# Get the current subscription
$subid = Get-AzureSubscription -Current | %{ $_.SubscriptionId }

# Get user credentials to 
Write-Verbose "Prompt user for administrator credentials to use when provisioning the cluster."
$credential = Get-Credential
Write-Verbose "Administrator credentials captured.  Use these credentials to login to the cluster when the script is complete."

# Initiate cluster provisioning as background job
$userName = $credential.GetNetworkCredential().UserName
$password = $credential.GetNetworkCredential().Password

$storage = Get-AzureStorageAccount $DefaultStorageAccount

$provJob = Start-Job –Scriptblock {
    param(
        $subid,
        $Cluster,
        $Location,
        $storage,
        $DefaultStorageAccount,
        $DefaultStorageContainer,
        $userName,
        $password,
        $ClusterSizeInNodes
    )
    New-AzureHDInsightCluster -Subscription $subid -Name $Cluster -Location $Location `
        -DefaultStorageAccountName ($storage.StorageAccountName + ".blob.core.windows.net") `
        -DefaultStorageAccountKey (Get-AzureStorageKey $DefaultStorageAccount).Primary `
        -DefaultStorageContainerName $DefaultStorageContainer `
        -UserName $userName -Password $password `
        -ClusterSizeInNodes $ClusterSizeInNodes
} -Arg @(`
        $subid,`
        $Cluster,`
        $Location,`
        $storage,`
        $DefaultStorageAccount,`
        $DefaultStorageContainer,`
        $userName,`
        $password,`
        $ClusterSizeInNodes)

Write-Host "Sending request to provision cluster $Cluster"

# Poll and report status of the cluster during the provisioning process
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
